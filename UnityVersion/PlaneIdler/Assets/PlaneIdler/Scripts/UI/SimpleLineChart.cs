using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace PlaneIdler.UI
{
    /// <summary>
    /// Lightweight line chart rendered via UGUI VertexHelper.
    /// </summary>
    [RequireComponent(typeof(RectTransform))]
    public class SimpleLineChart : MaskableGraphic
    {
        public Color lineColor = Color.green;
        public float lineThickness = 2f;
        public int maxPoints = 120;

        private readonly List<float> _points = new();

        public void AddPoint(float value)
        {
            _points.Add(value);
            if (_points.Count > maxPoints) _points.RemoveAt(0);
            SetVerticesDirty();
        }

        public void SetSeries(System.Collections.Generic.IEnumerable<float> values)
        {
            _points.Clear();
            if (values != null)
                _points.AddRange(values);
            if (_points.Count > maxPoints)
                _points.RemoveRange(0, _points.Count - maxPoints);
            SetVerticesDirty();
        }

        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear();
            if (_points.Count < 2) return;

            float width = rectTransform.rect.width;
            float height = rectTransform.rect.height;
            float maxY = 1f;
            for (int i = 0; i < _points.Count; i++)
                maxY = Mathf.Max(maxY, _points[i]);

            for (int i = 0; i < _points.Count - 1; i++)
            {
                float x0 = width * i / Mathf.Max(1, _points.Count - 1);
                float x1 = width * (i + 1) / Mathf.Max(1, _points.Count - 1);
                float y0 = height * _points[i] / maxY;
                float y1 = height * _points[i + 1] / maxY;
                AddLine(vh, new Vector2(x0, y0), new Vector2(x1, y1));
            }
        }

        private void AddLine(VertexHelper vh, Vector2 p0, Vector2 p1)
        {
            var dir = (p1 - p0).normalized;
            var normal = new Vector2(-dir.y, dir.x) * (lineThickness * 0.5f);

            var v0 = p0 - normal;
            var v1 = p0 + normal;
            var v2 = p1 + normal;
            var v3 = p1 - normal;

            int idx = vh.currentVertCount;
            AddVert(vh, v0);
            AddVert(vh, v1);
            AddVert(vh, v2);
            AddVert(vh, v3);
            vh.AddTriangle(idx + 0, idx + 1, idx + 2);
            vh.AddTriangle(idx + 0, idx + 2, idx + 3);
        }

        private void AddVert(VertexHelper vh, Vector2 pos)
        {
            UIVertex vert = UIVertex.simpleVert;
            vert.position = pos;
            vert.color = lineColor;
            vh.AddVert(vert);
        }
    }
}
