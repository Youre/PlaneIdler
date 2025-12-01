using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports stand.gd. Represents a parking stand with services.
    /// </summary>
    [RequireComponent(typeof(Renderer))]
    public class Stand : MonoBehaviour
    {
        public string StandClass = "ga_small";
        public string Label = "S1";
        public bool IsOccupied { get; private set; }

        private Renderer _renderer;
        private Material _availableMat;
        private Material _occupiedMat;

        private void Awake()
        {
            _renderer = GetComponent<Renderer>();
            var baseMat = BuildMaterialForClass(StandClass);
            _availableMat = baseMat;
            _occupiedMat = new Material(baseMat);
            _occupiedMat.color = Color.Lerp(baseMat.color, new Color(1f, 0.5f, 0.5f), 0.6f);
            ApplyMaterial();
        }

        public void Occupy()
        {
            IsOccupied = true;
            ApplyMaterial();
        }

        public void Vacate()
        {
            IsOccupied = false;
            ApplyMaterial();
        }

        private void ApplyMaterial()
        {
            if (_renderer == null) return;
            _renderer.sharedMaterial = IsOccupied ? _occupiedMat : _availableMat;
        }

        private Material BuildMaterialForClass(string c)
        {
            var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var mat = new Material(shader);
            mat.color = c switch
            {
                "ga_small" => new Color(0.1f, 0.6f, 1.0f),
                "ga_medium" => new Color(0.2f, 0.7f, 0.9f),
                "regional" => new Color(0.9f, 0.7f, 0.2f),
                "narrowbody" => new Color(0.9f, 0.4f, 0.3f),
                "widebody" => new Color(0.8f, 0.2f, 0.8f),
                _ => new Color(0.6f, 0.6f, 0.6f)
            };
            mat.SetFloat("_Smoothness", 0.2f);
            mat.SetFloat("_Metallic", 0f);
            return mat;
        }
    }
}
