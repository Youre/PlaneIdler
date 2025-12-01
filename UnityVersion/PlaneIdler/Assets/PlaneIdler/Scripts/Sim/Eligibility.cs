namespace PlaneIdler.Sim
{
    /// <summary>
    /// Mirrors eligibility.gd. Determines which aircraft/stand combinations are allowed.
    /// </summary>
    public class Eligibility
    {
        public bool CanUseStand(string standClass, Systems.CatalogLoader.AircraftDef aircraft)
        {
            if (aircraft == null) return false;
            return aircraft.standClass == standClass;
        }

        public bool RunwayOk(Airport.Runway runway, Systems.CatalogLoader.AircraftDef aircraft)
        {
            if (runway == null || aircraft == null || aircraft.runway == null) return false;
            var req = aircraft.runway;
            if (runway.LengthMeters < req.minLengthMeters) return false;
            if (!SurfaceSufficient(runway.Surface, req.surface)) return false;
            if (req.widthClass == "wide" && runway.WidthMeters < 45f) return false;
            return true;
        }

        public bool EligibleForFbo(Systems.CatalogLoader.AircraftDef aircraft, SimState state)
        {
            if (state.fboSlotsTotal <= 0) return false;
            if (state.fboSlotsUsed >= state.fboSlotsTotal) return false;
            if (aircraft == null) return false;
            var cls = aircraft.@class;
            var stand = aircraft.standClass;
            var isGa = stand.StartsWith("ga") || cls == "ga_small" || cls == "turboprop";
            return isGa; // simple rule per Godot implementation
        }

        private bool SurfaceSufficient(string have, string need)
        {
            int Rank(string s) => s switch
            {
                "grass" => 0,
                "asphalt" => 1,
                "concrete" => 2,
                _ => -1
            };
            return Rank(have) >= Rank(need);
        }
    }
}
