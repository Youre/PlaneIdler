using TMPro;
using UnityEngine;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Minimal HUD wiring to mirror Godot bank/traffic counters.
    /// Listens to Events hub.
    /// </summary>
    public class HudController : MonoBehaviour
    {
        [SerializeField] private TMP_Text bankText;
        [SerializeField] private TMP_Text arrivalsText;
        [SerializeField] private TMP_Text missedText;
        [SerializeField] private TMP_Text divertedText;
        [SerializeField] private SimpleLineChart incomeChart;
        [SerializeField] private SimpleLineChart trafficChart;

        private void OnEnable()
        {
            Systems.Events.BankChanged += OnBank;
            Systems.Events.ArrivalsChanged += OnArrivals;
            Systems.Events.MissedChanged += OnMissed;
            Systems.Events.DivertedChanged += OnDiverted;
        }

        private void OnDisable()
        {
            Systems.Events.BankChanged -= OnBank;
            Systems.Events.ArrivalsChanged -= OnArrivals;
            Systems.Events.MissedChanged -= OnMissed;
            Systems.Events.DivertedChanged -= OnDiverted;
        }

        private void OnBank(float value) => Set(bankText, $"Bank: {value:0}");
        private void OnArrivals(int value) => Set(arrivalsText, $"Arrivals: {value}");
        private void OnMissed(int value) => Set(missedText, $"Missed: {value}");
        private void OnDiverted(int value) => Set(divertedText, $"Diverted: {value}");

        private static void Set(TMP_Text label, string text)
        {
            if (label != null) label.text = text;
        }
    }
}
