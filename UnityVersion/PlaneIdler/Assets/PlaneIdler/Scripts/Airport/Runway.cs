using UnityEngine;

namespace PlaneIdler.Airport
{
    /// <summary>
    /// Ports runway.gd. Handles takeoff/landing slots and timing.
    /// </summary>
    public class Runway : MonoBehaviour
    {
        [Header("Geometry (meters)")]
        public float LengthMeters = 600f;
        public float WidthMeters = 30f;
        public string Surface = "grass"; // grass | asphalt | concrete
        public string Label = "09/27";

        public bool Supports(Systems.CatalogLoader.RunwayReq req)
        {
            if (req == null) return true;
            if (LengthMeters < req.minLengthMeters) return false;
            if (req.widthClass == "wide" && WidthMeters < 45f) return false;
            int Rank(string s) => s switch
            {
                "grass" => 0,
                "asphalt" => 1,
                "concrete" => 2,
                _ => -1
            };
            return Rank(Surface) >= Rank(req.surface);
        }
    }
}
