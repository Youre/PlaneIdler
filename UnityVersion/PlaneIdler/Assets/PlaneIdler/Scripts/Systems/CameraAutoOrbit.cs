using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Non-interactive top-down-ish camera that orbits the airport slowly.
    /// Matches the Godot behavior: player does not control camera.
    /// </summary>
    public class CameraAutoOrbit : MonoBehaviour
    {
        [Header("Target")]
        public Transform runwayTarget;
        public Vector3 center = Vector3.zero;

        [Header("Orbit")]
        public float radius = 180f;
        public float height = 100f;
        public float angularSpeed = 8f; // degrees per second
        public float pitchDegrees = 45f;

        [Header("Scaling (Godot parity)")]
        // Minimum bounds; actual radius/height derived from Godot main.gd formula.
        public float minRadius = 160f;
        public float minHeight = 90f;

        private float _angle;
        private PlaneIdler.Airport.Runway _runway;

        private void Start()
        {
            _angle = 0f;
            ResolveRunway();
            // Start centered on the runway if available; otherwise origin.
            center = _runway != null ? _runway.transform.position : Vector3.zero;

            // Clamp the main camera FOV for a more zoomed-in, orthographic-feel view.
            var cam = GetComponent<Camera>();
            if (cam != null)
                cam.fieldOfView = 45f;
        }

        private void ResolveRunway()
        {
            if (runwayTarget != null)
                _runway = runwayTarget.GetComponent<PlaneIdler.Airport.Runway>();
            if (_runway == null)
                _runway = Object.FindFirstObjectByType<PlaneIdler.Airport.Runway>();
            if (_runway != null)
                runwayTarget = _runway.transform;
        }

        private void UpdateCenterAndScale()
        {
            // Derive center/radius/height using the same scale as the Godot implementation:
            //
            //   base_size = max(180, runway.length_m * 0.7)
            //   size      = base_size * 0.6
            //   dist      = size
            //   height    = dist * 0.7
            if (_runway != null)
            {
                center = _runway.transform.position;
                float baseSize = Mathf.Max(180f, _runway.LengthMeters * 0.7f);
                float size = baseSize * 0.6f;
                float dist = size;
                radius = Mathf.Max(minRadius, dist);
                // Raise camera altitude relative to distance to keep more of the field in view.
                height = Mathf.Max(minHeight, dist * 1.0f);
            }
            else if (runwayTarget != null)
            {
                center = runwayTarget.position;
            }
        }

        private void LateUpdate()
        {
            if (_runway == null && runwayTarget == null)
                ResolveRunway();
            UpdateCenterAndScale();

            _angle += angularSpeed * Time.deltaTime;
            var rad = _angle * Mathf.Deg2Rad;
            var pos = new Vector3(
                center.x + Mathf.Cos(rad) * radius,
                center.y + height,
                center.z + Mathf.Sin(rad) * radius
            );
            transform.position = pos;
            // Look at the runway center with a fixed pitch, allowing yaw to follow orbit
            var lookDir = (center - pos).normalized;
            var yaw = Mathf.Atan2(lookDir.x, lookDir.z) * Mathf.Rad2Deg;
            transform.rotation = Quaternion.Euler(pitchDegrees, yaw, 0f);
        }
    }
}
