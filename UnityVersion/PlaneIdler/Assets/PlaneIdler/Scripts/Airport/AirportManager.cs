using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports airport_manager.gd. Coordinates runways, stands, fueling, tower interactions.
    /// </summary>
    public class AirportManager : MonoBehaviour
    {
        [SerializeField] private StandManager standManager;

        public void OnAircraftArrive(string aircraftId)
        {
            // TODO: request stand, manage taxi flow, hand off to tower.
        }

        public void OnAircraftDepart(string aircraftId)
        {
            // TODO: release stand, update stats.
        }
    }
}
