using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Bar chart for daily income, mirroring Godot's IncomeChart.
    /// </summary>
    public class IncomeBarChart : MaskableGraphic
    {
        public Color barColor = new Color(0.2f, 0.8f, 0.3f, 0.9f);
        public Color borderColor = new Color(1f, 1f, 1f, 0.4f);
        public int maxPoints = 10;

        private readonly List<float> _values = new();
        private float _fallbackBank;

        public void SetData(IList<float> values, float fallbackBank)
        {
            _values.Clear();
            if (values != null)
                _values.AddRange(values);
            _fallbackBank = Mathf.Max(0f, fallbackBank);
            if (_values.Count > maxPoints)
                _values.RemoveRange(0, _values.Count - maxPoints);
            SetVerticesDirty();
        }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            var rect = rectTransform.rect;
            const float margin = 4f;
            float w = rect.width - margin * 2f;
            float h = rect.height - margin * 2f;
            if (w <= 0f || h <= 0f) return;

            // Choose data: daily income or fallback to bank.
            var data = new List<float>(_values);
            bool hasPositive = false;
            foreach (var v in data)
            {
                if (v > 0f) { hasPositive = true; break; }
            }
            if (!hasPositive && _fallbackBank > 0f)
            {
                data.Clear();
                data.Add(_fallbackBank);
            }
            if (data.Count == 0) return;

            float maxVal = 0f;
            foreach (var v in data)
                if (v > maxVal) maxVal = v;
            if (maxVal <= 0f) maxVal = 1f;

            int barCount = data.Count;
            float barSpacing = 2f;
            float barWidth = (w - barSpacing * (barCount - 1)) / Mathf.Max(1, barCount);
            if (barWidth < 1f) barWidth = 1f;

            Vector2 origin = new Vector2(rect.xMin + margin, rect.yMin + margin);

            // Border rectangle.
            AddRect(vh, origin, new Vector2(w, h), borderColor, hollow: true);

            for (int i = 0; i < barCount; i++)
            {
                float v = data[i];
                float ratio = Mathf.Clamp01(v / maxVal);
                float barH = h * ratio;
                float x = origin.x + i * (barWidth + barSpacing);
                float y = origin.y + (h - barH);
                AddRect(vh, new Vector2(x, y), new Vector2(barWidth, barH), barColor, hollow: false);
            }
        }

        private void AddRect(VertexHelper vh, Vector2 bottomLeft, Vector2 size, Color color, bool hollow)
        {
            if (hollow)
            {
                float thickness = 1.5f;
                // Top
                AddQuad(vh, new Vector2(bottomLeft.x, bottomLeft.y + size.y - thickness),
                    new Vector2(size.x, thickness), color);
                // Bottom
                AddQuad(vh, new Vector2(bottomLeft.x, bottomLeft.y),
                    new Vector2(size.x, thickness), color);
                // Left
                AddQuad(vh, new Vector2(bottomLeft.x, bottomLeft.y),
                    new Vector2(thickness, size.y), color);
                // Right
                AddQuad(vh, new Vector2(bottomLeft.x + size.x - thickness, bottomLeft.y),
                    new Vector2(thickness, size.y), color);
            }
            else
            {
                AddQuad(vh, bottomLeft, size, color);
            }
        }

        private void AddQuad(VertexHelper vh, Vector2 bottomLeft, Vector2 size, Color color)
        {
            int start = vh.currentVertCount;
            var v0 = new Vector3(bottomLeft.x, bottomLeft.y);
            var v1 = new Vector3(bottomLeft.x, bottomLeft.y + size.y);
            var v2 = new Vector3(bottomLeft.x + size.x, bottomLeft.y + size.y);
            var v3 = new Vector3(bottomLeft.x + size.x, bottomLeft.y);

            vh.AddVert(v0, color, Vector2.zero);
            vh.AddVert(v1, color, Vector2.zero);
            vh.AddVert(v2, color, Vector2.zero);
            vh.AddVert(v3, color, Vector2.zero);
            vh.AddTriangle(start + 0, start + 1, start + 2);
            vh.AddTriangle(start + 0, start + 2, start + 3);
        }
    }
}
