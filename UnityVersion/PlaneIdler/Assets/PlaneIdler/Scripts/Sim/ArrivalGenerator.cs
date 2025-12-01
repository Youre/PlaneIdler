using System.Collections.Generic;
using UnityEngine;

namespace PlaneIdler.Sim
{
    /// <summary>
    /// Direct port of Godot arrival_generator.gd.
    /// Uses progression tier + tier upgrade counts to bias traffic mix.
    /// </summary>
    public class ArrivalGenerator : MonoBehaviour
    {
        [SerializeField] private float minIntervalSeconds = 30f;
        [SerializeField] private float maxIntervalSeconds = 60f;
        [SerializeField] private float initialDelaySeconds = 5f;
        [SerializeField] private SimState simState;

        private float _timer;
        private float _nextSpawn;
        private Systems.CatalogLoader _catalog;

        public void Init(Systems.CatalogLoader catalog)
        {
            _catalog = catalog;
            Reset();
        }

        private void Start()
        {
            // Ensure we are using the same SimState instance as the main SimController.
            if (simState == null)
            {
                var controller = FindFirstObjectByType<SimController>();
                if (controller != null)
                    simState = controller.State;
                else
                    simState = Resources.Load<SimState>("Settings/SimState");
            }
        }

        public void Reset()
        {
            _timer = 0f;
            _nextSpawn = initialDelaySeconds;
        }

        /// <summary>
        /// Mirrors Godot's update(dt, sim) and may emit zero or more arrivals.
        /// </summary>
        public List<Systems.CatalogLoader.AircraftDef> UpdateGenerator(float deltaTime)
        {
            var spawns = new List<Systems.CatalogLoader.AircraftDef>();
            if (_catalog == null || _catalog.Aircraft == null || _catalog.Aircraft.Count == 0)
                return spawns;

            _timer += deltaTime;

            // Night-ops gate: if night ops not unlocked, skip spawns at night.
            if (simState != null && !simState.IsDaytime() && !simState.nightOpsUnlocked)
                return spawns;

            int tier = simState != null ? simState.progressionTier : 0;
            while (_timer >= _nextSpawn)
            {
                var chosen = PickForTier(tier);
                if (chosen != null)
                    spawns.Add(chosen);
                _timer -= _nextSpawn;
                float rate = simState != null ? Mathf.Max(0.1f, simState.trafficRateMultiplier) : 1f;
                _nextSpawn = Random.Range(minIntervalSeconds, maxIntervalSeconds) / rate;
            }

            return spawns;
        }

        private Systems.CatalogLoader.AircraftDef PickForTier(int tier)
        {
            if (_catalog == null || _catalog.Aircraft == null || _catalog.Aircraft.Count == 0)
                return null;

            // Filter by tier unlock.
            var eligible = new List<Systems.CatalogLoader.AircraftDef>();
            foreach (var a in _catalog.Aircraft)
            {
                if (a == null) continue;
                if (a.tierUnlock <= tier)
                    eligible.Add(a);
            }
            if (eligible.Count == 0)
                return null;

            // Tier upgrade counts (1..4) influence mix of small/medium/large.
            int t1 = 0, t2 = 0, t3 = 0, t4 = 0;
            if (simState != null && simState.tierUpgradeCounts != null)
            {
                simState.tierUpgradeCounts.TryGetValue(1, out t1);
                simState.tierUpgradeCounts.TryGetValue(2, out t2);
                simState.tierUpgradeCounts.TryGetValue(3, out t3);
                simState.tierUpgradeCounts.TryGetValue(4, out t4);
            }

            var weighted = new List<(Systems.CatalogLoader.AircraftDef def, float weight)>();
            float totalWeight = 0f;

            foreach (var a in eligible)
            {
                string cls = a.@class ?? string.Empty;
                string standClass = a.standClass ?? string.Empty;
                bool isSmall = cls == "ga_small";
                bool isMedium = cls == "turboprop" || standClass == "ga_medium";
                bool isLarge = cls == "regional_jet" ||
                               cls == "narrowbody" ||
                               cls == "widebody" ||
                               cls == "cargo_wide" ||
                               cls == "cargo_small";

                float votes = 0f;
                // Base votes: only small GA start with one.
                if (isSmall)
                    votes += 1f;
                // Tier 1 upgrades: small + medium GA.
                if (t1 > 0 && (isSmall || isMedium))
                    votes += t1;
                // Tier 2 upgrades: small + medium + large.
                if (t2 > 0 && (isSmall || isMedium || isLarge))
                    votes += t2;
                // Tier 3 upgrades: medium + large.
                if (t3 > 0 && (isMedium || isLarge))
                    votes += t3;
                // Tier 4 upgrades: large only.
                if (t4 > 0 && isLarge)
                    votes += t4;

                if (votes <= 0f)
                    continue;

                weighted.Add((a, votes));
                totalWeight += votes;
            }

            if (weighted.Count == 0)
                return null;

            float r = Random.Range(0f, totalWeight);
            foreach (var entry in weighted)
            {
                r -= entry.weight;
                if (r <= 0f)
                    return entry.def;
            }

            return weighted[weighted.Count - 1].def;
        }
    }
}
