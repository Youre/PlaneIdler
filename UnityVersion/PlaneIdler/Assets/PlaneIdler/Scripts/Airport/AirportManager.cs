using UnityEngine;
using UnityEngine.Rendering;

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

            // Layout any existing stands beside the primary runway so they
            // are not buried under the runway mesh.
            LayoutStandsRow();

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

            // Ensure all airport geometry both casts and receives shadows so
            // the moving sun light produces visible aircraft / runway shadows.
            foreach (var r in GetComponentsInChildren<Renderer>(true))
            {
                if (r == null) continue;
                r.shadowCastingMode = ShadowCastingMode.On;
                r.receiveShadows = true;
            }
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

        /// <summary>
        /// Positions all stands in a single row parallel to the primary
        /// runway, offset to one side. This mirrors the Godot layout and
        /// keeps parking spots visible next to the runway instead of
        /// overlapping it.
        /// </summary>
        private void LayoutStandsRow()
        {
            if (standManager == null || primaryRunway == null) return;

            var stands = standManager.GetComponentsInChildren<Stand>();
            if (stands == null || stands.Length == 0) return;

            var fwd = primaryRunway.transform.right.normalized;   // along runway
            var right = primaryRunway.transform.forward.normalized; // perpendicular

            float lateralOffset = 25f;          // meters from centerline
            float spacing = standSpacing;       // reuse configured spacing

            float firstAlong = -spacing * (stands.Length - 1) * 0.5f;
            var baseOrigin = primaryRunway.transform.position
                             + right * -lateralOffset; // choose one side

            for (int i = 0; i < stands.Length; i++)
            {
                float along = firstAlong + i * spacing;
                var worldPos = baseOrigin + fwd * along + Vector3.up * 0.1f;
                stands[i].transform.position = worldPos;
            }
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
                s.transform.localPosition = standRowOrigin; // temporary; LayoutStandsRow will reposition
            }

            // Refresh stand manager list so sim sees new stands.
            standManager.RegisterStands(standsRoot.GetComponentsInChildren<Stand>());

            // Re-layout all stands beside the runway after adding new ones.
            LayoutStandsRow();
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
