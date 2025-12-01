using UnityEngine;
using PlaneIdler.Sim;
using System.Linq;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Ports upgrade_manager.gd. Applies upgrades that affect income, capacity, etc.
    /// </summary>
    public class UpgradeManager : MonoBehaviour
    {
        [SerializeField] private CatalogLoader catalog;
        [SerializeField] private SimState simState;
        [SerializeField] private ArrivalGenerator arrivalGenerator;
        [SerializeField] private PlaneIdler.Airport.AirportManager airportManager;
        [SerializeField] private PlaneIdler.Airport.Runway primaryRunway;
        [SerializeField] private SimController simController;

        private readonly System.Collections.Generic.Dictionary<string, int> _purchaseCounts = new();
        private readonly System.Collections.Generic.List<BuildEntry> _buildQueue = new();

        private void Awake()
        {
            if (catalog == null) catalog = GetComponent<CatalogLoader>();
            if (simState == null) simState = Resources.Load<SimState>("Settings/SimState");
            if (arrivalGenerator == null) arrivalGenerator = FindFirstObjectByType<ArrivalGenerator>();
            if (airportManager == null) airportManager = FindFirstObjectByType<PlaneIdler.Airport.AirportManager>();
            if (primaryRunway == null) primaryRunway = FindFirstObjectByType<PlaneIdler.Airport.Runway>();
            if (simController == null) simController = FindFirstObjectByType<SimController>();
        }

        private void Update()
        {
            if (_buildQueue.Count == 0) return;
            float dt = Time.deltaTime;
            if (simController != null)
                dt *= simController.GetTimeScale();
            for (int i = _buildQueue.Count - 1; i >= 0; i--)
            {
                var e = _buildQueue[i];
                e.remainingSeconds -= dt;
                if (e.remainingSeconds <= 0f)
                {
                    var up = catalog?.Upgrades?.FirstOrDefault(u => u.id == e.id);
                    if (up != null) ApplyUpgrade(up);
                    _buildQueue.RemoveAt(i);
                    Events.RaiseConstructionUpdated();
                }
                else
                {
                    _buildQueue[i] = e;
                }
            }
        }

        public void ApplyUpgrade(string upgradeId)
        {
            var up = catalog?.Upgrades?.FirstOrDefault(u => u.id == upgradeId);
            if (up == null)
            {
                Debug.LogWarning($"UpgradeManager: upgrade {upgradeId} not found");
                return;
            }
            ApplyUpgrade(up);
        }

        public bool Purchase(string upgradeId)
        {
            var up = catalog?.Upgrades?.FirstOrDefault(u => u.id == upgradeId);
            if (up == null || simState == null) return false;

            _purchaseCounts.TryGetValue(up.id, out var bought);
            if (bought >= up.maxPurchases) return false;
            if (simState.bank < up.cost) return false;

            simState.bank -= up.cost;
            Systems.Events.RaiseBank(simState.bank);
            _purchaseCounts[up.id] = bought + 1;

            if (up.buildTimeSeconds <= 0f)
            {
                ApplyUpgrade(up);
                Events.RaiseConstructionUpdated();
                return true;
            }

            _buildQueue.Add(new BuildEntry
            {
                id = up.id,
                displayName = up.displayName,
                remainingSeconds = up.buildTimeSeconds
            });
            Events.RaiseConstructionUpdated();
            return true;
        }

        public System.Collections.Generic.IReadOnlyList<BuildEntry> GetConstructionEntries() => _buildQueue;

        public int GetPurchaseCount(string id)
        {
            _purchaseCounts.TryGetValue(id, out var count);
            return count;
        }

        public bool IsUnderConstruction(string id)
        {
            return _buildQueue.Any(b => b.id == id);
        }

        public void ApplyUpgrade(CatalogLoader.UpgradeDef up)
        {
            if (up?.effects == null) return;
            foreach (var e in up.effects)
            {
                switch (e.type)
                {
                    case "multiplier":
                        ApplyMultiplier(e);
                        break;
                    case "unlock_nav":
                        ApplyNav(e);
                        break;
                    case "add_stand":
                        ApplyAddStand(e);
                        break;
                    case "extend_runway":
                        ApplyExtendRunway(e);
                        break;
                    case "widen_runway":
                        ApplyWidenRunway(e);
                        break;
                    case "add_runway":
                        ApplyAddRunway(e);
                        break;
                    case "upgrade_surface":
                        ApplyUpgradeSurface(e);
                        break;
                    case "add_hangar":
                    case "add_taxi_exit":
                        ApplyInfra(e);
                        break;
                    default:
                        Debug.Log($"UpgradeManager: unhandled effect {e.type}");
                        break;
                }
            }

            // Track progression tier and tier-specific counts for spawn weighting.
            if (simState != null)
            {
                int tier = up.tierUnlock;
                if (tier >= 0)
                {
                    if (tier > simState.progressionTier)
                        simState.progressionTier = tier;
                    if (!simState.tierUpgradeCounts.ContainsKey(tier))
                        simState.tierUpgradeCounts[tier] = 0;
                    simState.tierUpgradeCounts[tier]++;
                }
            }

            // ID-specific hooks mirroring Godot behavior.
            if (airportManager != null)
            {
                switch (up.id)
                {
                    case "tower_upgrade":
                        airportManager.ShowTower();
                        break;
                    case "fuel_farm":
                        airportManager.ShowFuelStation();
                        break;
                    case "ils_lighting":
                        airportManager.EnableRunwayLights();
                        break;
                }
            }

            Events.RaiseConstructionUpdated();
        }

        private void ApplyMultiplier(CatalogLoader.UpgradeEffect e)
        {
            if (simState == null) return;
            switch (e.target)
            {
                case "income":
                    simState.income_multiplier *= e.value;
                    break;
                case "arrival_rate":
                    simState.trafficRateMultiplier *= e.value;
                    break;
            }
        }

        private void ApplyNav(CatalogLoader.UpgradeEffect e)
        {
            if (simState == null) return;
            switch (e.capability)
            {
                case "night_ops":
                    simState.nightOpsUnlocked = true;
                    break;
                case "atc":
                    simState.atcUnlocked = true;
                    break;
            }
        }

        private void ApplyAddStand(CatalogLoader.UpgradeEffect e)
        {
            if (airportManager == null) return;
            int count = e.count;
            if (count <= 0) return;
            string standClass = e.standClass;
            airportManager.AddStands(standClass, count);
        }

        private void ApplyExtendRunway(CatalogLoader.UpgradeEffect e)
        {
            if (primaryRunway == null) return;
            float meters = e.lengthMeters;
            if (meters <= 0f) return;
            primaryRunway.LengthMeters += meters;
            Debug.Log($"UpgradeManager: extended runway by {meters:0} m");
        }

        private void ApplyWidenRunway(CatalogLoader.UpgradeEffect e)
        {
            if (primaryRunway == null) return;
            float minWidth = e.widthClass == "wide" ? 45f : e.lengthMeters;
            if (minWidth <= 0f) minWidth = 45f;
            if (primaryRunway.WidthMeters < minWidth)
                primaryRunway.WidthMeters = minWidth;
            Debug.Log($"UpgradeManager: widened runways to >= {minWidth:0} m");
        }

        private void ApplyAddRunway(CatalogLoader.UpgradeEffect e)
        {
            if (airportManager == null) return;
            float lengthMeters = e.lengthMeters;
            string surface = string.IsNullOrEmpty(e.surface) ? "asphalt" : e.surface;
            string widthClass = string.IsNullOrEmpty(e.widthClass) ? "standard" : e.widthClass;

            var newRunway = airportManager.AddParallelRunway(80f);
            if (newRunway == null) return;
            if (lengthMeters > 0f)
                newRunway.LengthMeters = lengthMeters;
            newRunway.Surface = surface;
            if (widthClass == "wide" && newRunway.WidthMeters < 45f)
                newRunway.WidthMeters = 45f;

            // Bump traffic rate like Godot does.
            if (simState != null)
            {
                if (simState.trafficRateMultiplier <= 0f)
                    simState.trafficRateMultiplier = 1f;
                simState.trafficRateMultiplier *= 1.4f;
            }
            Debug.Log("UpgradeManager: built additional runway");
        }

        private void ApplyUpgradeSurface(CatalogLoader.UpgradeEffect e)
        {
            if (primaryRunway == null) return;
            string toSurface = string.IsNullOrEmpty(e.surface) ? "asphalt" : e.surface;
            if (!string.IsNullOrEmpty(toSurface))
            {
                primaryRunway.Surface = toSurface;
                Debug.Log($"UpgradeManager: upgraded runway surface to {toSurface}");
            }
        }

        private void ApplyInfra(CatalogLoader.UpgradeEffect e)
        {
            if (airportManager == null || simState == null) return;
            switch (e.type)
            {
                case "add_hangar":
                    airportManager.AddHangars(e.count);
                    // Hangars also register FBO slots via SimController/SimState in Godot;
                    // we mirror the slot count on SimState so FBO service can use it.
                    simState.fboSlotsTotal += e.count;
                    break;
                case "add_taxi_exit":
                    airportManager.EnableTaxiways();
                    if (simState.trafficRateMultiplier <= 0f)
                        simState.trafficRateMultiplier = 1f;
                    float bonus = e.target == "rapid" ? 1.1f : 1.05f;
                    simState.trafficRateMultiplier *= bonus;
                    break;
            }
        }

        public struct BuildEntry
        {
            public string id;
            public string displayName;
            public float remainingSeconds;
        }
    }
}
