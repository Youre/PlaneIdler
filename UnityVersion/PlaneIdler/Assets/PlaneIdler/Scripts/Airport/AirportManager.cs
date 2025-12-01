using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports airport_manager.gd. Coordinates runways, stands, fueling, tower interactions.
    /// </summary>
    public class AirportManager : MonoBehaviour
    {
        [SerializeField] private StandManager standManager;
        [SerializeField] private Runway primaryRunway;
        [SerializeField] private Stand standPrefab;
        [SerializeField] private Transform standsRoot;
        [SerializeField] private Transform hangarsRoot;
        [SerializeField] private Tower tower;
        [SerializeField] private FuelStation fuelStation;
        [SerializeField] private Transform taxiwaysRoot;
        [SerializeField] private PlaneIdler.Systems.RunwayLightsController runwayLights;

        [Header("Layout")]
        [SerializeField] private float standSpacing = 25f;
        [SerializeField] private Vector3 standRowOrigin = new Vector3(0f, 0.1f, -15f);
        [SerializeField] private float hangarSpacing = 40f;

        private readonly System.Collections.Generic.List<Runway> _runways = new();

        private void Awake()
        {
            if (standManager == null)
                standManager = GetComponent<StandManager>();
            if (primaryRunway == null)
                primaryRunway = GetComponentInChildren<Runway>();
            if (standsRoot == null && standManager != null)
                standsRoot = standManager.transform;
            if (hangarsRoot == null)
                hangarsRoot = transform;
            if (primaryRunway != null && !_runways.Contains(primaryRunway))
                _runways.Add(primaryRunway);

            // Resolve optional visual helpers.
            if (tower == null)
                tower = GetComponentInChildren<Tower>(true);
            if (fuelStation == null)
                fuelStation = GetComponentInChildren<FuelStation>(true);
            if (taxiwaysRoot == null)
            {
                var t = transform.Find("Taxiways");
                if (t != null) taxiwaysRoot = t;
            }
            if (runwayLights == null)
                runwayLights = FindObjectOfType<PlaneIdler.Systems.RunwayLightsController>();

            // Default: hide upgrade-driven visuals until purchased.
            if (tower != null)
                tower.gameObject.SetActive(false);
            if (fuelStation != null)
                fuelStation.gameObject.SetActive(false);
            if (taxiwaysRoot != null)
                taxiwaysRoot.gameObject.SetActive(false);
            if (runwayLights != null)
                runwayLights.gameObject.SetActive(false);
        }

        public void OnAircraftArrive(string aircraftId)
        {
            // TODO: request stand, manage taxi flow, hand off to tower.
        }

        public void OnAircraftDepart(string aircraftId)
        {
            // Hook for future expansion.
        }

        public void ShowTower()
        {
            if (tower != null)
                tower.gameObject.SetActive(true);
        }

        public void ShowFuelStation()
        {
            if (fuelStation != null)
                fuelStation.gameObject.SetActive(true);
        }

        public void AddStands(string standClass, int count)
        {
            if (standManager == null || count <= 0) return;
            if (standPrefab == null)
                standPrefab = FindObjectOfType<Stand>();
            if (standPrefab == null) return;

            if (standsRoot == null)
                standsRoot = standManager.transform;

            var current = standsRoot.GetComponentsInChildren<Stand>();
            int startIndex = current.Length;
            for (int i = 0; i < count; i++)
            {
                int idx = startIndex + i + 1;
                var s = Instantiate(standPrefab, standsRoot);
                s.StandClass = standClass;
                s.Label = $"{standClass.ToUpper().Substring(0, Mathf.Min(2, standClass.Length))}{idx}";
                var pos = standRowOrigin + new Vector3((idx - 1) * standSpacing, 0f, 0f);
                s.transform.localPosition = pos;
            }

            // Refresh stand manager list so sim sees new stands.
            standManager.RegisterStands(standsRoot.GetComponentsInChildren<Stand>());
        }

        public void AddHangars(int slotCount)
        {
            if (slotCount <= 0) return;
            if (hangarsRoot == null)
                hangarsRoot = transform;

            int buildings = Mathf.CeilToInt(slotCount / 2f);
            for (int i = 0; i < buildings; i++)
            {
                float x = -80f + (i * hangarSpacing);
                var root = new GameObject("Hangar").AddComponent<Transform>();
                root.SetParent(hangarsRoot, false);
                root.localPosition = new Vector3(x, 0f, standRowOrigin.z - 40f);
                // Simple box as visual placeholder.
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.name = "HangarBody";
                go.transform.SetParent(root, false);
                go.transform.localScale = new Vector3(18f, 6f, 12f);
            }
        }

        public Runway AddParallelRunway(float offset)
        {
            if (primaryRunway == null) return null;
            var go = new GameObject("Runway_Parallel");
            var rwy = go.AddComponent<Runway>();
            rwy.LengthMeters = primaryRunway.LengthMeters;
            rwy.WidthMeters = primaryRunway.WidthMeters;
            rwy.Surface = primaryRunway.Surface;
            go.transform.SetParent(transform.parent ?? transform, false);
            go.transform.position = primaryRunway.transform.position + primaryRunway.transform.right.normalized * offset;
            go.transform.rotation = primaryRunway.transform.rotation;
            _runways.Add(rwy);
            return rwy;
        }

        public void EnableTaxiways()
        {
            if (taxiwaysRoot != null)
                taxiwaysRoot.gameObject.SetActive(true);
        }

        public void EnableRunwayLights()
        {
            if (runwayLights != null)
                runwayLights.gameObject.SetActive(true);
        }
    }
}
