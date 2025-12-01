using UnityEngine;

namespace PlaneIdler.Sim
{
    /// <summary>
    /// Holds mutable simulation state (time, cash, traffic, queues).
    /// Ports Godot's sim_state.gd.
    /// </summary>
    [CreateAssetMenu(fileName = "SimState", menuName = "PlaneIdler/Sim/SimState")]
    public class SimState : ScriptableObject
    {
        [Header("Economy")]
        public float bank;
        public float income_multiplier = 1f;
        public float incomePerTick;
        public System.Collections.Generic.List<float> dailyIncome = new();

        [Header("Traffic")]
        public int activeAircraft;
        public int totalArrivals;
        public int diverted;
        public int missed;
        public int received;
        public int fboSlotsTotal;
        public int fboSlotsUsed;
        public System.Collections.Generic.List<float> dailyReceived = new();
        public System.Collections.Generic.List<float> dailyMissed = new();

        [Header("Rates")]
        public float arrivalRateMultiplier = 1f;

        [Header("Time")]
        public float timeSeconds;
        public float clockMinutes = DAY_START_MIN; // 0-1440
        public int dayIndex = 1;

        public const float MINUTES_PER_DAY = 1440f;
        public const float DAY_START_MIN = 6f * 60f;
        public const float DAY_END_MIN = 20f * 60f;
        public const float DAY_RATE_MIN_PER_SEC = 1.4f;
        public const float NIGHT_RATE_MIN_PER_SEC = 4.0f;
        public const float NIGHT_RATE_NO_LIGHTS_MIN_PER_SEC = 10.0f;

        public bool nightOpsUnlocked;

        public void Advance(float dt)
        {
            timeSeconds += dt;
            var prev = clockMinutes;
            var rate = IsDaytime() ? DAY_RATE_MIN_PER_SEC : (nightOpsUnlocked ? NIGHT_RATE_MIN_PER_SEC : NIGHT_RATE_NO_LIGHTS_MIN_PER_SEC);
            clockMinutes += dt * rate;
            clockMinutes = Mathf.Repeat(clockMinutes, MINUTES_PER_DAY);
            if (clockMinutes < prev)
            {
                dayIndex++;
                StartNewDayBucket();
            }
        }

        public bool IsDaytime() => clockMinutes >= DAY_START_MIN && clockMinutes < DAY_END_MIN;

        public string GetClockHHMM()
        {
            var mins = (int)clockMinutes % (int)MINUTES_PER_DAY;
            int hh = mins / 60;
            int mm = mins % 60;
            return $"{hh:00}:{mm:00}";
        }

        public void AddIncome(float amount)
        {
            bank += amount;
            EnsureBuckets();
            dailyIncome[^1] += amount;
        }

        public void AddReceived(float count = 1f)
        {
            EnsureBuckets();
            dailyReceived[^1] += count;
            totalArrivals += (int)count;
        }

        public void AddMissed(float count = 1f)
        {
            EnsureBuckets();
            dailyMissed[^1] += count;
        }

        public void AddDiverted(float count = 1f) => AddMissed(count);

        private void EnsureBuckets()
        {
            if (dailyIncome.Count == 0)
            {
                dailyIncome.Add(0);
                dailyReceived.Add(0);
                dailyMissed.Add(0);
            }
        }

        private void StartNewDayBucket()
        {
            dailyIncome.Add(0);
            dailyReceived.Add(0);
            dailyMissed.Add(0);
            if (dailyIncome.Count > 10) dailyIncome.RemoveAt(0);
            if (dailyReceived.Count > 10) dailyReceived.RemoveAt(0);
            if (dailyMissed.Count > 10) dailyMissed.RemoveAt(0);
        }
    }
}
