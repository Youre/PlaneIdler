using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Drives a directional "sun" light from SimState time of day,
    /// mirroring the Godot implementation: sun rises in the east,
    /// arcs overhead, and sets in the west while casting shadows.
    /// </summary>
    [RequireComponent(typeof(Light))]
    public class SunLightController : MonoBehaviour
    {
        [Tooltip("Simulation state providing time-of-day.")]
        public Sim.SimState simState;

        [Tooltip("Minimum sun elevation at sunrise/sunset (degrees).")]
        public float horizonElevation = 5f;

        [Tooltip("Maximum sun elevation at noon (degrees).")]
        public float noonElevation = 65f;

        [Tooltip("World-space direction for 'east' (sunrise).")]
        public Vector3 eastDirection = new Vector3(1f, 0f, 0f);

        private Light _light;

        private void Awake()
        {
            _light = GetComponent<Light>();
            _light.type = LightType.Directional;
            _light.shadows = LightShadows.Soft;

            if (simState == null)
                simState = Resources.Load<Sim.SimState>("Settings/SimState");
        }

        private void LateUpdate()
        {
            if (simState == null || _light == null)
                return;

            // Map sim clock (0-1440 minutes) to a 0-1 "day phase".
            float t = simState.clockMinutes / Sim.SimState.MINUTES_PER_DAY;

            // Simple sun model: 0.0 dawn, 0.25 noon, 0.5 dusk, 0.75 midnight.
            // Use a sine curve for elevation and a full 360° azimuth sweep.
            float azimuthDeg = t * 360f; // spin around once per sim day
            float elevFactor = Mathf.Clamp01(Mathf.Sin(t * Mathf.PI)); // 0 at night, 1 at noon
            float elevationDeg = Mathf.Lerp(horizonElevation, noonElevation, elevFactor);

            // Build a direction vector from azimuth (around Y) and elevation.
            float azimuthRad = azimuthDeg * Mathf.Deg2Rad;
            float elevationRad = elevationDeg * Mathf.Deg2Rad;

            // Base east direction projected in XZ.
            Vector3 east = eastDirection;
            east.y = 0f;
            if (east.sqrMagnitude < 0.001f)
                east = Vector3.right;
            east.Normalize();

            // Rotate east around Y by azimuth, then tilt up by elevation.
            var horizontal = Quaternion.AngleAxis(azimuthDeg, Vector3.up) * east;
            var dir = new Vector3(horizontal.x,
                                  Mathf.Sin(elevationRad),
                                  horizontal.z).normalized;

            // Directional light points *from* source *toward* scene.
            transform.rotation = Quaternion.LookRotation(-dir, Vector3.up);

            // Optional: dim light at night.
            float baseIntensity = 1.1f;
            _light.intensity = baseIntensity * elevFactor;
            _light.enabled = elevFactor > 0.02f;
        }
    }
}

