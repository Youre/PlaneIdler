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

        private readonly System.Collections.Generic.Dictionary<string, int> _purchaseCounts = new();
        private readonly System.Collections.Generic.List<BuildEntry> _buildQueue = new();

        private void Awake()
        {
            if (catalog == null) catalog = GetComponent<CatalogLoader>();
            if (simState == null) simState = Resources.Load<SimState>("Settings/SimState");
            if (arrivalGenerator == null) arrivalGenerator = FindFirstObjectByType<ArrivalGenerator>();
        }

        private void Update()
        {
            if (_buildQueue.Count == 0) return;
            float dt = Time.deltaTime;
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
                        // Placeholder: UI/build system would instantiate stands; here we just log.
                        Debug.Log($"UpgradeManager: add_stand {e.standClass} x{e.count}");
                        break;
                    case "extend_runway":
                    case "widen_runway":
                    case "add_runway":
                    case "upgrade_surface":
                        Debug.Log($"UpgradeManager: runway upgrade {e.type}");
                        break;
                    case "add_hangar":
                    case "add_taxi_exit":
                Debug.Log($"UpgradeManager: infra upgrade {e.type}");
                break;
            default:
                Debug.Log($"UpgradeManager: unhandled effect {e.type}");
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
                    simState.arrivalRateMultiplier *= e.value;
                    break;
            }
        }

        private void ApplyNav(CatalogLoader.UpgradeEffect e)
        {
            if (simState == null) return;
            if (e.capability == "night_ops")
            {
                simState.nightOpsUnlocked = true;
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
