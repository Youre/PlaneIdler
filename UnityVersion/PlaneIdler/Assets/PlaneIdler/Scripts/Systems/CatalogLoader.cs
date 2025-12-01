using System;
using System.Collections.Generic;
using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Ports catalog_loader.gd. Loads aircraft/upgrades data from JSON (Godot parity) and exposes typed records.
    /// Later we can swap to ScriptableObjects but keep JSON to validate parity.
    /// </summary>
    public class CatalogLoader : MonoBehaviour
    {
        [Serializable]
        public class AircraftDef
        {
            public string id;
            public string displayName;
            public string @class;
            public Fees fees;
            public RunwayReq runway;
            public string standClass;
            public DwellMinutes dwellMinutes;
            public float spawnWeight;
            public int tierUnlock;
            public int mtowKg;
        }

        [Serializable]
        public class DwellMinutes
        {
            public float min;
            public float max;
        }

        [Serializable]
        public class Fees
        {
            public float landing;
            public float parkingPerMinute;
            public float fboService;
        }

        [Serializable]
        public class RunwayReq
        {
            public float minLengthMeters;
            public string surface;
            public string widthClass;
        }

        [Serializable]
        public class UpgradeEffect
        {
            public string type;           // e.g., add_stand, multiplier, unlock_nav, extend_runway
            public string target;         // e.g., income, arrival_rate
            public string capability;     // e.g., night_ops
            public string standClass;     // for add_stand
            public int count;             // for add_stand, slots, etc.
            public float value;           // multiplier value
            public float lengthMeters;    // for extend_runway
            public string surface;        // for upgrade_surface
            public string widthClass;     // for widen_runway
        }

        [Serializable]
        public class UpgradeDef
        {
            public string id;
            public string displayName;
            public string category;
            public int cost;
            public int buildTimeSeconds;
            public int maxPurchases;
            public string[] prerequisites;
            public UpgradeEffect[] effects;
            public int tierUnlock;
        }

        [Header("JSON Sources (optional if using Resources)")]
        public TextAsset aircraftJson;
        public TextAsset upgradesJson;

        private const string AircraftResPath = "PlaneIdler/Data/aircraft";
        private const string UpgradesResPath = "PlaneIdler/Data/upgrades";

        public IReadOnlyList<AircraftDef> Aircraft => _aircraft;
        public IReadOnlyList<UpgradeDef> Upgrades => _upgrades;

        private List<AircraftDef> _aircraft = new();
        private List<UpgradeDef> _upgrades = new();

        private void Awake()
        {
            Load();
        }

        public void Load()
        {
            var aircraftAsset = aircraftJson ?? LoadByName("aircraft");
            var upgradesAsset = upgradesJson ?? LoadByName("upgrades");

            _aircraft = ParseList<AircraftDef>(aircraftAsset, "aircraft");
            _upgrades = ParseList<UpgradeDef>(upgradesAsset, "upgrades");
        }

        private static List<T> ParseList<T>(TextAsset json, string label)
        {
            if (json == null || string.IsNullOrWhiteSpace(json.text))
            {
                Debug.LogError($"CatalogLoader: Missing JSON for {label}");
                return new List<T>();
            }

            try
            {
                return JsonUtility.FromJson<Wrapper<T>>(Wrap(json.text)).items;
            }
            catch (Exception ex)
            {
                Debug.LogError($"CatalogLoader: Failed to parse {label} JSON: {ex.Message}");
                return new List<T>();
            }
        }

        // Unity's JsonUtility needs a wrapper object for arrays.
        [Serializable]
        private class Wrapper<T>
        {
            public List<T> items;
        }

        private static string Wrap(string arrayJson) => $"{{\"items\":{arrayJson}}}";

        private static TextAsset LoadByName(string name)
        {
            // Try specific paths first
            var asset = Resources.Load<TextAsset>($"PlaneIdler/Data/{name}");
            if (asset != null) return asset;
            asset = Resources.Load<TextAsset>($"Data/{name}");
            if (asset != null) return asset;
            // Fallback: search all TextAssets in Resources and match filename
            foreach (var ta in Resources.LoadAll<TextAsset>(""))
            {
                if (ta != null && ta.name.Equals(name, System.StringComparison.OrdinalIgnoreCase))
                    return ta;
            }
            return null;
        }
    }
}
