using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Drives sun/moon lighting based on SimState clock.
    /// </summary>
    public class DayNightController : MonoBehaviour
    {
        public Light sun;
        public Light moon;
        public Sim.SimState simState;

        [Header("Intensity")]
        public float sunDayIntensity = 1.2f;
        public float sunNightIntensity = 0f;
        public float moonNightIntensity = 0.2f;

        [Header("Colors")]
        public Gradient sunColor;
        public Color moonColor = new Color(0.6f, 0.7f, 1f);

        private void Awake()
        {
            if (simState == null)
                simState = Resources.Load<Sim.SimState>("Settings/SimState");
            if (sunColor == null || sunColor.colorKeys.Length == 0)
            {
                sunColor = new Gradient
                {
                    colorKeys = new[]
                    {
                        new GradientColorKey(new Color(0.9f,0.55f,0.35f), 0f),
                        new GradientColorKey(new Color(1f,0.95f,0.85f), 0.2f),
                        new GradientColorKey(new Color(1f,1f,0.95f), 0.5f),
                        new GradientColorKey(new Color(0.9f,0.55f,0.35f), 1f),
                    }
                };
            }
        }

        private void LateUpdate()
        {
            if (simState == null || sun == null || moon == null) return;
            float tDay = simState.clockMinutes / Sim.SimState.MINUTES_PER_DAY;

            // Sun angle: 0 -> midnight; noon at 0.5
            float sunAngle = (tDay * 360f) - 90f;
            sun.transform.rotation = Quaternion.Euler(sunAngle, -30f, 0f);
            moon.transform.rotation = Quaternion.Euler(sunAngle + 180f, -30f, 0f);

            bool isDay = simState.IsDaytime();
            float dawnDusk = Mathf.Clamp01(Mathf.InverseLerp(Sim.SimState.DAY_START_MIN - 60f, Sim.SimState.DAY_START_MIN + 60f, simState.clockMinutes));
            float dusk = Mathf.Clamp01(Mathf.InverseLerp(Sim.SimState.DAY_END_MIN + 60f, Sim.SimState.DAY_END_MIN - 60f, simState.clockMinutes));
            float blend = isDay ? Mathf.Max(dawnDusk, 1f - dusk) : 0f;

            sun.intensity = Mathf.Lerp(sunNightIntensity, sunDayIntensity, blend);
            sun.color = sunColor.Evaluate(blend);

            float nightBlend = 1f - blend;
            moon.intensity = Mathf.Lerp(0f, moonNightIntensity, nightBlend);
            moon.color = moonColor;
        }
    }
}
