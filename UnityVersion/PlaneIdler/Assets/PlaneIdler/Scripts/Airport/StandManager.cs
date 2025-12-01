using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports stand_manager.gd. Tracks stand occupancy and allocation.
    /// </summary>
    public class StandManager : MonoBehaviour
    {
        [SerializeField] private Stand[] stands;

        private void Awake()
        {
            if (stands == null || stands.Length == 0)
                stands = GetComponentsInChildren<Stand>();
        }

        public void RegisterStands(Stand[] list) => stands = list;

        public Stand FindFree(string standClass)
        {
            if (stands == null) return null;
            foreach (var s in stands)
            {
                if (!s.IsOccupied && s.StandClass == standClass)
                    return s;
            }
            return null;
        }

        public (int total, int free) StatsForClass(string standClass)
        {
            int total = 0, free = 0;
            if (stands == null) return (0, 0);
            foreach (var s in stands)
            {
                if (s.StandClass != standClass) continue;
                total++;
                if (!s.IsOccupied) free++;
            }
            return (total, free);
        }
    }
}
