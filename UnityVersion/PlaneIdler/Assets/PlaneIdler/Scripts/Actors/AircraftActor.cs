using UnityEngine;

namespace PlaneIdler.Actors
{
    /// <summary>
    /// Ports aircraft_actor.gd. Controls aircraft movement/state machine.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class AircraftActor : MonoBehaviour
    {
        private CharacterController _controller;
        private Vector3[] _path;
        private int _pathIndex;
        private System.Action _onComplete;
        private Transform _body;
        private Renderer _renderer;

        [Header("Movement")]
        public float taxiSpeed = 5f;
        public float takeoffSpeed = 20f;

        private void Awake()
        {
            _controller = GetComponent<CharacterController>();

            // Ensure a simple visible mesh exists so aircraft are
            // rendered even when using placeholder prefabs.
            var existingRenderer = GetComponentInChildren<Renderer>();
            if (existingRenderer == null)
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.name = "Body";
                go.transform.SetParent(transform, false);
                // Roughly match Godot proxy size (6x3x12) in meters.
                go.transform.localScale = new Vector3(6f, 3f, 12f);
                _renderer = go.GetComponent<Renderer>();
                if (_renderer != null)
                {
                    var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
                    if (shader != null)
                    {
                        var mat = new Material(shader);
                        mat.color = new Color(1f, 1f, 0.3f);
                        _renderer.sharedMaterial = mat;
                    }
                }
                // We don't need the collider from CreatePrimitive; CharacterController handles collisions.
                var box = go.GetComponent<Collider>();
                if (box != null) Destroy(box);
                _body = go.transform;
            }
            else
            {
                _renderer = existingRenderer;
                _body = _renderer.transform;
            }
        }

        public void SetCategoryColor(string category)
        {
            if (_renderer == null) return;

            // Small: green-ish, Medium: red-ish, Large: blue-ish.
            float hue;
            switch (category)
            {
                case "small":
                    hue = Random.Range(0.25f, 0.38f); // green band
                    break;
                case "medium":
                    hue = Random.Range(0.0f, 0.05f);  // red band
                    break;
                case "large":
                    hue = Random.Range(0.55f, 0.68f); // blue band
                    break;
                default:
                    hue = Random.value;
                    break;
            }
            float sat = Random.Range(0.6f, 0.9f);
            float val = Random.Range(0.7f, 1.0f);
            var c = Color.HSVToRGB(hue, sat, val);

            var mat = _renderer.sharedMaterial;
            if (mat == null)
            {
                var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
                if (shader == null) return;
                mat = new Material(shader);
                _renderer.sharedMaterial = mat;
            }
            mat.color = c;
        }

        public void SetVisualProfile(string category, string widthClass)
        {
            if (_body == null) return;

            // Base sizes roughly scaled to category; width class tweaks lateral span.
            float length = 12f;
            float width = 6f;
            float height = 3f;

            switch (category)
            {
                case "medium":
                    length = 18f;
                    width = 8f;
                    height = 3.5f;
                    break;
                case "large":
                    length = 26f;
                    width = 12f;
                    height = 4f;
                    break;
            }

            switch (widthClass)
            {
                case "wide":
                    width *= 1.25f;
                    length *= 1.15f;
                    break;
                case "standard":
                    width *= 1.05f;
                    length *= 1.05f;
                    break;
            }

            _body.localScale = new Vector3(width, height, length);
        }

        public void StartPath(Vector3[] points, System.Action onComplete)
        {
            if (points == null || points.Length == 0) return;
            _path = points;
            _pathIndex = 0;
            _onComplete = onComplete;
        }

        private void Update()
        {
            if (_path == null || _pathIndex >= _path.Length) return;

            var target = _path[_pathIndex];
            var to = target - transform.position;
            var speed = (_pathIndex <= 1 ? takeoffSpeed : taxiSpeed);
            var step = speed * Time.deltaTime;

            if (to.magnitude <= step)
            {
                transform.position = target;
                _pathIndex++;
                if (_pathIndex >= _path.Length)
                {
                    _path = null;
                    _onComplete?.Invoke();
                }
            }
            else
            {
                var dir = to.normalized;
                transform.forward = Vector3.Lerp(transform.forward, dir, 10f * Time.deltaTime);
                _controller.SimpleMove(dir * speed);
            }
        }
    }
}
