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
        public float radius = 120f;
        public float height = 70f;
        public float angularSpeed = 8f; // degrees per second
        public float pitchDegrees = 55f;

        [Header("Scaling")]
        public float radiusMultiplier = 0.25f; // radius ~= 25% of runway length
        public float heightMultiplier = 0.15f; // height ~= 15% of runway length
        public float minRadius = 80f;
        public float minHeight = 50f;

        private float _angle;
        private PlaneIdler.Airport.Runway _runway;

        private void Start()
        {
            _angle = 0f;
            ResolveRunway();
            UpdateCenterAndScale();
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
            if (runwayTarget != null)
                center = runwayTarget.position;
            if (_runway != null)
            {
                radius = Mathf.Max(minRadius, _runway.LengthMeters * radiusMultiplier);
                height = Mathf.Max(minHeight, _runway.LengthMeters * heightMultiplier);
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
