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
            // Arrivals
            Systems.CatalogLoader.AircraftDef spawn = null;
            if (arrivalGenerator != null)
                spawn = arrivalGenerator.UpdateGenerator(dt);
            if (spawn != null)
                HandleArrival(spawn);

            // Dwell timers and departures
            ProcessDwell(dt);
            ServiceDepartureQueue();

            // Advance time of day
            simState?.Advance(dt);

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

            // If runway is already in use, divert (Unity build has no ATC / holding pattern logic).
            if (_runwayBusy)
            {
                simState?.AddMissed();
                Systems.Events.RaiseMissed(simState.missed);
                Log($"Arrival diverted: runway busy for {aircraft.id}");
                // Optional visual: a one-off holding / flyby pattern.
                if (aircraftActorPrefab != null && runway != null)
                    SpawnHoldingPattern(aircraft);
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
                ServiceDepartureQueue();
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
                ServiceDepartureQueue();
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

        private void SpawnHoldingPattern(Systems.CatalogLoader.AircraftDef aircraft)
        {
            var actor = Instantiate(aircraftActorPrefab);
            var fwd = runway.transform.right.normalized;
            var right = runway.transform.forward.normalized;
            float alt = 45f;
            float legLong = 450f;
            float legShort = 220f;
            var center = runway.transform.position;
            var p1 = center - fwd * (legLong * 0.5f) + right * legShort + Vector3.up * alt;
            var p2 = center + fwd * (legLong * 0.5f) + right * legShort + Vector3.up * alt;
            var p3 = center + fwd * (legLong * 0.5f) - right * legShort + Vector3.up * alt;
            var p4 = center - fwd * (legLong * 0.5f) - right * legShort + Vector3.up * alt;
            actor.GetComponent<Actors.AircraftActor>()?.StartPath(new[] { p1, p2, p3, p4, p1 }, () =>
            {
                Destroy(actor);
            });
        }

        private void Log(string msg)
        {
            Systems.Events.RaiseLog(msg);
            Debug.Log(msg);
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
