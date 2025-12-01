using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports fuel_station.gd. Handles refueling interactions and timing.
    /// </summary>
    public class FuelStation : MonoBehaviour
    {
        [SerializeField] private float refuelSeconds = 5f;

        public float GetRefuelTime(string aircraftId)
        {
            // TODO: derive from aircraft type / upgrade levels.
            return refuelSeconds;
        }
    }
}
