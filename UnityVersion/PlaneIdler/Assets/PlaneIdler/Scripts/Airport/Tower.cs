using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports tower.gd. Mediates runway clearances and traffic control.
    /// </summary>
    public class Tower : MonoBehaviour
    {
        public void GrantLanding(string aircraftId)
        {
            // TODO: integrate with Runway scheduling.
        }

        public void GrantTakeoff(string aircraftId)
        {
            // TODO: integrate with Runway scheduling.
        }
    }
}
