using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Simple stacked bar chart for daily received/missed traffic.
    /// </summary>
    public class StackedBarChart : MaskableGraphic
    {
        public Color receivedColor = new Color(0.2f, 0.8f, 0.3f, 0.9f);
        public Color missedColor = new Color(0.9f, 0.2f, 0.2f, 0.9f);
        public int maxPoints = 12;

        private readonly List<float> _received = new();
        private readonly List<float> _missed = new();

        public void SetData(IList<float> received, IList<float> missed)
        {
            _received.Clear();
            _missed.Clear();
            if (received != null) _received.AddRange(received);
            if (missed != null) _missed.AddRange(missed);
            Trim(maxPoints);
            SetVerticesDirty();
        }

        private void Trim(int limit)
        {
            if (_received.Count > limit) _received.RemoveRange(0, _received.Count - limit);
            if (_missed.Count > limit) _missed.RemoveRange(0, _missed.Count - limit);
        }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            int count = Mathf.Max(_received.Count, _missed.Count);
            if (count == 0) return;

            var rect = rectTransform.rect;
            const float margin = 4f;
            float w = rect.width - margin * 2f;
            float h = rect.height - margin * 2f;
            if (w <= 0f || h <= 0f) return;

            // Determine scale from total traffic per day.
            float maxVal = 1f;
            for (int i = 0; i < count; i++)
            {
                float total = Get(_received, i) + Get(_missed, i);
                if (total > maxVal) maxVal = total;
            }

            float spacing = 2f;
            float barWidth = (w - spacing * (count - 1)) / Mathf.Max(1, count);
            if (barWidth < 1f) barWidth = 1f;

            Vector2 origin = new Vector2(rect.xMin + margin, rect.yMin + margin);

            // Border
            AddBar(vh, origin, w, 1.5f, border: true);                       // bottom
            AddBar(vh, new Vector2(origin.x, origin.y + h - 1.5f), w, 1.5f, border: true); // top
            AddBar(vh, origin, 1.5f, h, border: true);                        // left
            AddBar(vh, new Vector2(origin.x + w - 1.5f, origin.y), 1.5f, h, border: true); // right

            for (int i = 0; i < count; i++)
            {
                float rec = Get(_received, i);
                float mis = Get(_missed, i);
                float total = rec + mis;
                if (total <= 0f) continue;

                float x = origin.x + i * (barWidth + spacing);
                float totalRatio = Mathf.Clamp01(total / maxVal);
                float totalH = h * totalRatio;
                float baseY = origin.y + (h - totalH);

                float recRatio = Mathf.Clamp01(rec / maxVal);
                float recH = h * recRatio;
                float missRatio = Mathf.Clamp01(mis / maxVal);
                float missH = h * missRatio;

                // Received segment
                AddQuad(vh, new Vector2(x, origin.y + h - recH), barWidth, recH, receivedColor);
                // Missed segment stacked
                AddQuad(vh, new Vector2(x, baseY), barWidth, missH, missedColor);
            }
        }

        private static float Get(List<float> list, int index)
        {
            return index < list.Count ? list[index] : 0f;
        }

        private void AddBar(VertexHelper vh, Vector2 bottomLeft, float width, float height, bool border)
        {
            var color = border ? new Color(1f, 1f, 1f, 0.4f) : Color.white;
            AddQuad(vh, bottomLeft, width, height, color);
        }

        private void AddQuad(VertexHelper vh, Vector2 bottomLeft, float width, float height, Color color)
        {
            int start = vh.currentVertCount;
            var v0 = new Vector3(bottomLeft.x, bottomLeft.y);
            var v1 = new Vector3(bottomLeft.x, bottomLeft.y + height);
            var v2 = new Vector3(bottomLeft.x + width, bottomLeft.y + height);
            var v3 = new Vector3(bottomLeft.x + width, bottomLeft.y);

            vh.AddVert(v0, color, Vector2.zero);
            vh.AddVert(v1, color, Vector2.zero);
            vh.AddVert(v2, color, Vector2.zero);
            vh.AddVert(v3, color, Vector2.zero);
            vh.AddTriangle(start + 0, start + 1, start + 2);
            vh.AddTriangle(start + 0, start + 2, start + 3);
        }
    }
}
