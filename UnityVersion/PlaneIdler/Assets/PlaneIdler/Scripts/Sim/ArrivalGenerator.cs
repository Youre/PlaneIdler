using UnityEngine;

namespace PlaneIdler.Sim
{
    /// <summary>
    /// Ports arrival_generator.gd. Simplified: uses spawnWeight from CatalogLoader to pick aircraft at intervals.
    /// </summary>
    public class ArrivalGenerator : MonoBehaviour
    {
        [SerializeField] private float spawnIntervalSeconds = 8f;
        [SerializeField] private float jitterSeconds = 3f;
        [SerializeField] private SimState simState;

        private float _timer;
        private Systems.CatalogLoader _catalog;

        public void Init(Systems.CatalogLoader catalog)
        {
            _catalog = catalog;
            ResetTimer();
        }

        public void ResetTimer()
        {
            _timer = spawnIntervalSeconds + Random.Range(-jitterSeconds, jitterSeconds);
        }

        public Systems.CatalogLoader.AircraftDef UpdateGenerator(float deltaTime)
        {
            if (_catalog == null || _catalog.Aircraft == null || _catalog.Aircraft.Count == 0)
                return null;

            float rate = simState != null ? Mathf.Max(0.1f, simState.arrivalRateMultiplier) : 1f;
            _timer -= deltaTime * rate;
            if (_timer > 0f) return null;

            ResetTimer();
            return PickByWeight();
        }

        private Systems.CatalogLoader.AircraftDef PickByWeight()
        {
            float total = 0f;
            foreach (var a in _catalog.Aircraft)
                total += Mathf.Max(0.01f, a.spawnWeight);
            var roll = Random.Range(0f, total);
            float acc = 0f;
            foreach (var a in _catalog.Aircraft)
            {
                acc += Mathf.Max(0.01f, a.spawnWeight);
                if (roll <= acc) return a;
            }
            return _catalog.Aircraft[0];
        }
    }
}
