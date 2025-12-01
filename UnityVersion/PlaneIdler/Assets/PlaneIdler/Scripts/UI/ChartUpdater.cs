using UnityEngine;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Pushes daily buckets from SimState into charts.
    /// </summary>
    public class ChartUpdater : MonoBehaviour
    {
        public IncomeBarChart incomeChart;
        public StackedBarChart trafficChart;
        public Sim.SimState simState;

        private float _timer;

        private void Awake()
        {
            if (simState == null)
                simState = Resources.Load<Sim.SimState>("Settings/SimState");
        }

        private void Start()
        {
            var simController = FindFirstObjectByType<Sim.SimController>();
            if (simController != null)
                simState = simController.State;
        }

        private void Update()
        {
            _timer += Time.deltaTime;
            if (_timer >= 1f)
            {
                _timer = 0f;
                if (simState == null) return;
                if (incomeChart != null)
                    incomeChart.SetData(simState.dailyIncome, simState.bank);
                if (trafficChart != null)
                    trafficChart.SetData(simState.dailyReceived, simState.dailyMissed);
            }
        }
    }
}
