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

        [Header("Movement")]
        public float taxiSpeed = 5f;
        public float takeoffSpeed = 20f;

        private void Awake()
        {
            _controller = GetComponent<CharacterController>();
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
