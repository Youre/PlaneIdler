using System.Collections.Generic;
using UnityEngine;

namespace PlaneIdler.Sim
{
    /// <summary>
    /// Central simulation driver (trimmed parity with Godot sim_controller.gd).
    /// Handles tick scheduling, arrival spawning, stand allocation, and simple dwell/departure flow.
    /// </summary>
    public class SimController : MonoBehaviour
    {
        [SerializeField] private float tickIntervalSeconds = 0.2f;
        [SerializeField] private float timeScale = 1f;
        [SerializeField] private Systems.CatalogLoader catalog;
        [SerializeField] private ArrivalGenerator arrivalGenerator;
        [SerializeField] private Airport.StandManager standManager;
        [SerializeField] private Airport.Runway runway;
        [SerializeField] private SimState simState;
        [SerializeField] private GameObject aircraftActorPrefab;

        private float _accumulator;
        private readonly List<DwellTimer> _dwellTimers = new();
        private bool _runwayBusy;
        private readonly Queue<DepartureJob> _departureQueue = new();

        // ATC / holding pattern support (ported from Godot)
        private class PatternEntry
        {
            public Systems.CatalogLoader.AircraftDef Aircraft;
            public PlaneIdler.Actors.AircraftActor Actor;
            public List<Vector3> Points;
            public float WaitMinutes;
        }

        // FIFO of arrivals waiting for a runway slot when ATC is active.
        private readonly List<PatternEntry> _arrivalQueue = new();
        private readonly List<PatternEntry> _patternEntries = new();
        private readonly Eligibility _eligibility = new();

        public SimState State => simState;

        public void SetTimeScale(float value)
        {
            timeScale = Mathf.Max(0.01f, value);
            Systems.Events.RaiseTimeScale(timeScale);
        }

        public float GetTimeScale() => timeScale;

        private void Awake()
        {
            catalog ??= FindFirstObjectByType<Systems.CatalogLoader>();
            arrivalGenerator ??= FindFirstObjectByType<ArrivalGenerator>();
            standManager ??= FindFirstObjectByType<Airport.StandManager>();
            runway ??= FindFirstObjectByType<Airport.Runway>();
            if (simState == null)
            {
                simState = Resources.Load<SimState>("Settings/SimState");
                if (simState == null)
                    simState = ScriptableObject.CreateInstance<SimState>();
            }
            if (aircraftActorPrefab == null)
            {
                aircraftActorPrefab = Resources.Load<GameObject>("Prefabs/AircraftActor");
            }
            if (arrivalGenerator != null && catalog != null)
                arrivalGenerator.Init(catalog);
        }

        private void Start()
        {
            // Safety: ensure the Airport root is active after all objects
            // have been instantiated so the runway and stands render.
            var airportMgr = FindFirstObjectByType<Airport.AirportManager>(FindObjectsInactive.Include);
            if (airportMgr == null)
                return;

            if (!airportMgr.gameObject.activeSelf)
                airportMgr.gameObject.SetActive(true);
        }

        private void Update()
        {
            _accumulator += Time.deltaTime * timeScale;
            while (_accumulator >= tickIntervalSeconds)
            {
                _accumulator -= tickIntervalSeconds;
                Tick(tickIntervalSeconds);
            }
        }

        private void Tick(float dt)
        {
            // Arrivals (may be multiple per tick, like Godot)
            if (arrivalGenerator != null)
            {
                var spawns = arrivalGenerator.UpdateGenerator(dt);
                if (spawns != null)
                {
                    foreach (var ac in spawns)
                    {
                        if (ac != null)
                            HandleArrival(ac);
                    }
                }
            }

            // Dwell timers and departures
            ProcessDwell(dt);
            ServiceRunwayQueue();

            // Advance time of day
            simState?.Advance(dt);
            UpdatePatternFlights(dt);

        }

        private void HandleArrival(Systems.CatalogLoader.AircraftDef aircraft)
        {
            if (runway != null && !_eligibility.RunwayOk(runway, aircraft))
            {
                simState?.AddDiverted();
                Systems.Events.RaiseDiverted(simState.diverted);
                Log($"Arrival diverted: runway unsuitable for {aircraft.id}");
                return;
            }

            bool hasAtc = HasAtc();
            // If runway is already in use and there is no ATC, divert with a clear reason.
            if (_runwayBusy && !hasAtc)
            {
                simState?.AddMissed();
                Systems.Events.RaiseMissed(simState.missed);
                Log($"Arrival diverted: runway in use and no ATC for {aircraft.id}");
                return;
            }

            // If runway is busy but ATC is available, enqueue into a holding pattern.
            if (_runwayBusy && hasAtc)
            {
                EnqueuePatternArrival(aircraft);
                return;
            }

            var stand = standManager?.FindFree(aircraft.standClass);
            if (stand == null)
            {
                simState?.AddMissed();
                Systems.Events.RaiseMissed(simState.missed);
                Log($"Arrival diverted: no free stand for {aircraft.standClass}");
                return;
            }

            stand.Occupy();
            simState?.AddReceived();
            Systems.Events.RaiseArrivals(simState.received);
            AddIncome(aircraft);
            TryFboService(aircraft, stand);

            var dwellMin = Mathf.Max(aircraft.dwellMinutes.min, 1f);
            var dwellMax = Mathf.Max(aircraft.dwellMinutes.max, dwellMin);
            var dwellSec = UnityEngine.Random.Range(dwellMin * 15f, dwellMax * 30f); // mimic Godot scaling
            _dwellTimers.Add(new DwellTimer { Stand = stand, Remaining = dwellSec, Aircraft = aircraft });

            _runwayBusy = true;
            SpawnArrivalActor(aircraft, stand, () =>
            {
                _runwayBusy = false;
                ServiceRunwayQueue();
            });

            Log($"[ARR] {aircraft.displayName} arrived -> {stand.Label} ({aircraft.standClass})");
        }

        private void ProcessDwell(float dt)
        {
            for (int i = _dwellTimers.Count - 1; i >= 0; i--)
            {
                var t = _dwellTimers[i];
                t.Remaining -= dt;
                if (t.Remaining <= 0f)
                {
                    _dwellTimers.RemoveAt(i);
                    if (_runwayBusy)
                    {
                        _departureQueue.Enqueue(new DepartureJob { Stand = t.Stand, Aircraft = t.Aircraft });
                    }
                    else
                    {
                        LaunchDeparture(t.Stand, t.Aircraft);
                    }
                }
                else
                {
                    _dwellTimers[i] = t;
                }
            }
        }

        private void ServiceDepartureQueue()
        {
            if (_runwayBusy || _departureQueue.Count == 0) return;
            var job = _departureQueue.Dequeue();
            LaunchDeparture(job.Stand, job.Aircraft);
        }

        private void ServiceRunwayQueue()
        {
            if (_runwayBusy)
                return;

            // First, service any queued arrivals managed by ATC.
            if (_arrivalQueue.Count > 0)
            {
                var entry = _arrivalQueue[0];
                _arrivalQueue.RemoveAt(0);
                if (entry.Actor != null)
                    Destroy(entry.Actor.gameObject);
                _patternEntries.Remove(entry);
                if (entry.Aircraft != null)
                    HandleArrival(entry.Aircraft);
                return;
            }

            // Then fall back to departures.
            ServiceDepartureQueue();
        }

        private void LaunchDeparture(Airport.Stand stand, Systems.CatalogLoader.AircraftDef aircraft)
        {
            if (stand == null) return;
            if (runway != null && !_eligibility.RunwayOk(runway, aircraft))
            {
                stand.Vacate();
                simState?.AddDiverted();
                Log($"Departure blocked: runway unsuitable for {aircraft.id}");
                return;
            }
            _runwayBusy = true;
            SpawnDepartureActor(stand, aircraft, () =>
            {
                _runwayBusy = false;
                ServiceRunwayQueue();
            });
            stand.Vacate();
            simState.activeAircraft = Mathf.Max(0, simState.activeAircraft - 1);
            Log($"[DEP] {aircraft.displayName} departed from {stand.Label}");
        }

        private void AddIncome(Systems.CatalogLoader.AircraftDef aircraft)
        {
            float landing = aircraft.fees.landing;
            float dwell = aircraft.fees.parkingPerMinute * Mathf.Max(aircraft.dwellMinutes.min, 1f);
            float amount = (landing + dwell) * Mathf.Max(0f, simState?.income_multiplier ?? 1f);
            simState?.AddIncome(amount);
            Systems.Events.RaiseBank(simState.bank);
            Log($"[+$]{amount:0} bank={simState?.bank:0}");
        }

        private void TryFboService(Systems.CatalogLoader.AircraftDef aircraft, Airport.Stand stand)
        {
            if (simState == null) return;
            if (!_eligibility.EligibleForFbo(aircraft, simState)) return;
            // 35% chance like Godot implementation
            if (UnityEngine.Random.value > 0.35f) return;
            simState.fboSlotsUsed++;
            float fee = Mathf.Max(aircraft.fees.fboService, 0f);
            fee *= Mathf.Max(0f, simState.income_multiplier);
            simState.AddIncome(fee);
            Systems.Events.RaiseBank(simState.bank);
            Log($"[FBO] {aircraft.displayName} used FBO (+{fee:0})");
        }

        private void SpawnArrivalActor(Systems.CatalogLoader.AircraftDef aircraft, Airport.Stand stand, System.Action onComplete)
        {
            if (aircraftActorPrefab == null || runway == null || stand == null) return;
            var actor = Instantiate(aircraftActorPrefab);
            actor.transform.position = runway.transform.position + Vector3.back * 250f + Vector3.up * 12f;
            var fwd = runway.transform.right.normalized; // runway length axis (X)
            var right = runway.transform.forward.normalized;
            var lateral = right * UnityEngine.Random.Range(-40f, 40f);
            var start = runway.transform.position - fwd * 300f + lateral + Vector3.up * 30f;
            var final = runway.transform.position - fwd * 40f + Vector3.up * 5f;
            var touchdown = runway.transform.position + Vector3.up * 0.2f;
            var roll = runway.transform.position + fwd * 40f + Vector3.up * 0.2f;
            var turnoff = stand.transform.position + Vector3.up * 0.4f;
            var standPos = stand.transform.position + Vector3.up * 0.4f;
            actor.GetComponent<Actors.AircraftActor>()?.StartPath(new[] { start, final, touchdown, roll, turnoff, standPos }, onComplete);
            simState.activeAircraft++;
        }

        private void SpawnDepartureActor(Airport.Stand stand, Systems.CatalogLoader.AircraftDef aircraft, System.Action onComplete)
        {
            if (aircraftActorPrefab == null || runway == null || stand == null) return;
            var actor = Instantiate(aircraftActorPrefab);
            actor.transform.position = stand.transform.position + Vector3.up * 0.5f;
            var fwd = runway.transform.right.normalized;
            var start = stand.transform.position + Vector3.up * 0.5f;
            var lineup = runway.transform.position - fwd * 30f + Vector3.up * 0.2f;
            var accel = runway.transform.position + fwd * 100f + Vector3.up * 0.2f;
            var rotate = runway.transform.position + fwd * 180f + Vector3.up * 2f;
            var climb = runway.transform.position + fwd * 350f + Vector3.up * 30f;
            actor.GetComponent<Actors.AircraftActor>()?.StartPath(new[] { start, lineup, accel, rotate, climb }, onComplete);
        }

        private void Log(string msg)
        {
            Systems.Events.RaiseLog(msg);
            Debug.Log(msg);
        }

        private bool HasAtc()
        {
            return simState != null && simState.atcUnlocked;
        }

        private void EnqueuePatternArrival(Systems.CatalogLoader.AircraftDef aircraft)
        {
            if (aircraft == null)
                return;

            // When ATC is available and the runway is busy, create a visual
            // aircraft flying a rectangular traffic pattern while it waits.
            PatternEntry entry = new PatternEntry
            {
                Aircraft = aircraft,
                Points = new List<Vector3>(),
                WaitMinutes = 0f
            };

            if (aircraftActorPrefab != null && runway != null)
            {
                var actorGo = Instantiate(aircraftActorPrefab);
                var actor = actorGo.GetComponent<PlaneIdler.Actors.AircraftActor>();
                entry.Actor = actor;
                if (actor != null)
                    actor.taxiSpeed = 55f;

                var center = runway.transform.position;
                var fwd = runway.transform.right.normalized;
                var right = runway.transform.forward.normalized;
                float alt = 45f;
                float legLong = 450f;
                float legShort = 220f;

                entry.Points.Add(center - fwd * (legLong * 0.5f) + right * legShort + Vector3.up * alt);
                entry.Points.Add(center + fwd * (legLong * 0.5f) + right * legShort + Vector3.up * alt);
                entry.Points.Add(center + fwd * (legLong * 0.5f) - right * legShort + Vector3.up * alt);
                entry.Points.Add(center - fwd * (legLong * 0.5f) - right * legShort + Vector3.up * alt);
                entry.Points.Add(entry.Points[0]);

                StartPatternLoop(entry);
            }

            _patternEntries.Add(entry);
            _arrivalQueue.Add(entry);
            Log($"[ATC] Queued arrival for {aircraft.displayName} in holding pattern");
        }

        private void StartPatternLoop(PatternEntry entry)
        {
            if (entry.Actor == null || entry.Points == null || entry.Points.Count < 2)
                return;

            var actor = entry.Actor;
            var pts = entry.Points.ToArray();
            actor.StartPath(pts, () =>
            {
                // Loop until entry is removed from _patternEntries.
                if (_patternEntries.Contains(entry))
                    StartPatternLoop(entry);
                else if (actor != null)
                    Destroy(actor.gameObject);
            });
        }

        private void UpdatePatternFlights(float dt)
        {
            if (simState == null || _patternEntries.Count == 0)
                return;

            // Convert real seconds to sim minutes using same rate as SimState.Advance.
            float rate = simState.IsDaytime()
                ? SimState.DAY_RATE_MIN_PER_SEC
                : (simState.nightOpsUnlocked ? SimState.NIGHT_RATE_MIN_PER_SEC : SimState.NIGHT_RATE_NO_LIGHTS_MIN_PER_SEC);

            for (int i = _patternEntries.Count - 1; i >= 0; i--)
            {
                var entry = _patternEntries[i];
                entry.WaitMinutes += dt * rate;
                if (entry.WaitMinutes >= 30f)
                {
                    // After 30 simulated minutes, divert this flight.
                    simState.AddMissed();
                    Systems.Events.RaiseMissed(simState.missed);
                    Log($"Arrival diverted: holding timeout (30 min) for {entry.Aircraft?.displayName}");

                    if (entry.Actor != null)
                        Destroy(entry.Actor.gameObject);

                    _patternEntries.RemoveAt(i);
                    _arrivalQueue.Remove(entry);
                }
            }
        }

        private struct DwellTimer
        {
            public Airport.Stand Stand;
            public Systems.CatalogLoader.AircraftDef Aircraft;
            public float Remaining;
        }

        private struct DepartureJob
        {
            public Airport.Stand Stand;
            public Systems.CatalogLoader.AircraftDef Aircraft;
        }
    }
}
