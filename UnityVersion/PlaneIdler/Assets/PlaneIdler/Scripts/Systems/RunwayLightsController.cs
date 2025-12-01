using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Simple emissive runway/stand lights that toggle with time of day.
    /// </summary>
    public class RunwayLightsController : MonoBehaviour
    {
        public Light[] lights;
        public Sim.SimState simState;
        public Color runwayColor = new Color(0.2f, 0.6f, 1f);
        public float runwayIntensity = 3f;

        private void Awake()
        {
            if (simState == null)
                simState = Resources.Load<Sim.SimState>("Settings/SimState");
            if (lights == null || lights.Length == 0)
                lights = GetComponentsInChildren<Light>();
            foreach (var l in lights)
            {
                l.color = runwayColor;
                l.intensity = runwayIntensity;
                l.enabled = false;
            }
        }

        private void LateUpdate()
        {
            if (simState == null || lights == null) return;
            bool on = !simState.IsDaytime();
            foreach (var l in lights)
            {
                if (l == null) continue;
                l.enabled = on;
            }
        }
    }
}
