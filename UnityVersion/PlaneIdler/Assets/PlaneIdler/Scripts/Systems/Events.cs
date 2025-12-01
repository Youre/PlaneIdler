using System;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Simple event hub to mirror Godot signals.
    /// </summary>
    public static class Events
    {
    public static event Action<float> BankChanged;
    public static event Action<int> ArrivalsChanged;
    public static event Action<int> MissedChanged;
    public static event Action<int> DivertedChanged;
    public static event Action<float> TimeScaleChanged;
    public static event Action ConstructionUpdated;
    public static event Action<string> LogLine;

    public static void RaiseBank(float value) => BankChanged?.Invoke(value);
    public static void RaiseArrivals(int value) => ArrivalsChanged?.Invoke(value);
    public static void RaiseMissed(int value) => MissedChanged?.Invoke(value);
    public static void RaiseDiverted(int value) => DivertedChanged?.Invoke(value);
    public static void RaiseTimeScale(float value) => TimeScaleChanged?.Invoke(value);
    public static void RaiseConstructionUpdated() => ConstructionUpdated?.Invoke();
    public static void RaiseLog(string text) => LogLine?.Invoke(text);
}
}
