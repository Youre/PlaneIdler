using System.Text;
using TMPro;
using UnityEngine;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Captures Unity logs and appends to a TMP text area.
    /// </summary>
    public class ConsoleLogSink : MonoBehaviour
    {
        public TMP_Text consoleText;
        public int maxLines = 200;
        public UnityEngine.UI.ScrollRect scrollRect;

        private readonly StringBuilder _buffer = new();

        private void OnEnable()
        {
            Application.logMessageReceived += HandleLog;
            Systems.Events.LogLine += HandleLogLine;
            if (scrollRect == null)
                scrollRect = GetComponentInParent<UnityEngine.UI.ScrollRect>();
        }

        private void OnDisable()
        {
            Application.logMessageReceived -= HandleLog;
            Systems.Events.LogLine -= HandleLogLine;
        }

        private void HandleLog(string condition, string stackTrace, LogType type)
        {
            if (consoleText == null) return;
            bool atBottom = IsAtBottom();
            var line = $"[{type}] {condition}";
            _buffer.AppendLine(line);
            TrimLines();
            consoleText.text = _buffer.ToString();
            ScrollIfNeeded(atBottom);
        }

        private void HandleLogLine(string line)
        {
            if (consoleText == null) return;
            bool atBottom = IsAtBottom();
            _buffer.AppendLine(line);
            TrimLines();
            consoleText.text = _buffer.ToString();
            ScrollIfNeeded(atBottom);
        }

        private bool IsAtBottom()
        {
            if (scrollRect == null || scrollRect.content == null || scrollRect.viewport == null)
                return true;
            // If content fits inside viewport, treat as "at bottom" so we auto-scroll.
            if (scrollRect.content.rect.height <= scrollRect.viewport.rect.height + 0.5f)
                return true;
            // Otherwise, check whether we're already at the bottom.
            // verticalNormalizedPosition == 0 means bottom; allow small epsilon.
            return scrollRect.verticalNormalizedPosition <= 0.001f;
        }

        private void ScrollIfNeeded(bool wasAtBottom)
        {
            if (!wasAtBottom || scrollRect == null) return;
            // Ensure layout is up to date before snapping to bottom.
            Canvas.ForceUpdateCanvases();
            scrollRect.verticalNormalizedPosition = 0f;
            Canvas.ForceUpdateCanvases();
        }

        private void TrimLines()
        {
            var text = _buffer.ToString();
            var lines = text.Split('\n');
            if (lines.Length <= maxLines) return;
            int start = lines.Length - maxLines;
            _buffer.Clear();
            for (int i = start; i < lines.Length; i++)
            {
                if (lines[i].Length > 0)
                    _buffer.AppendLine(lines[i]);
            }
        }
    }
}
