# Plane Idler — Design & Tech Plan

## 1) Vision & Goals
- Top-down idle/auto-management sim where a tiny grass strip grows into a multi-runway airport over ~6 real-time hours.
- Player is mostly spectator; an AI manager spends income on upgrades using configurable policies.
- Every run starts with a freshly generated airfield layout and seed; strong replayability via procedural variety.
- Built to swap placeholder primitives for real 3D assets later without changing core logic.

## 2) Core Game Loop
- Time flows continuously (no hard ticks), but simulation updates in fixed steps (e.g., 5–10 Hz) for determinism.
- Planes are spawned by traffic generator → approach → land (if runway supports type) → taxi → park → dwell → depart.
- Parking occupancy gates new arrivals; arrivals queue/hold if no compatible spot is free.
- Each arrival pays a landing/parking fee; larger classes pay more and require better infrastructure.
- AI manager evaluates bank + forecasted income vs upgrade costs/cooldowns → purchases upgrades → unlocks new capacity/types → raises income ceiling.
- Console feed logs arrivals, departures, upgrade decisions, and economy milestones.

## 3) Systems Breakdown
- **World/Tile System**: Sparse grid for runways, taxiways, stands, scenery; snap-to-grid builds keep pathing simple.
- **Runway System**: Attributes: length, surface (grass/asphalt/concrete), width class, ILS/lighting, active ops (arrival/departure), cooldown/occupancy.
- **Parking/Stands**: Stand type (GA small, GA medium, cargo ramp, regional gate, narrow-body, wide-body), jetway flag, size limits, count, occupancy timer.
- **Traffic Generator**: Weighted random aircraft types based on unlocked tiers and current time; spawn interval base (e.g., 180–300s) scaled by popularity/weather/events.
- **Aircraft Classes**: Tiered catalog with min runway length, surface requirement, stand requirement, fee schedule, dwell-time range, MTOW for realism.
- **Pathing**: Simple node graph along taxiway segments; deterministic routes per stand/runway pair; avoid collisions via reserved segments/time windows.
- **Economy**: Income from landing + parking; costs for upgrades; soft inflation curve to keep late-game spending meaningful; optional loans/bonds later.
- **Upgrades**: Add stands, extend runways, pave surfaces, add second runway, add taxiways/turnoffs, add nav aids/lighting (unlocks night ops), fuel farm (multiplier), cargo terminal (unlocks cargo tier).
- **Progression**: Tier gates (Grass → Paved → Regional → Narrow-body → Wide-body); each gate requires money + prerequisite structures.
- **AI Manager**: Policy-driven chooser (greedy ROI baseline; later: lookahead/Monte Carlo); can be swapped with human/manual for debugging.
- **Events/Weather (stretch)**: Fog/wind reducing capacity; emergencies causing stand blockage; seasonal boosts.
- **Save/Load**: Serialize seed, time, economy, structures, queues, AI policy state.

## 4) Procedural Generation
- Seeded RNG per run; store seed for replay.
- Layout recipe: choose base wind dir → place initial grass strip (length/heading) → scatter trees/roads as obstacles → choose stand cluster positions → generate taxi stubs; ensure at least one valid path per initial stand.
- Later: multi-biome styles (island, desert, alpine) affecting visuals and arrival mix.

## 5) Economy & Pacing Targets (initial draft)
- Goal: ~6h to reach large airport with reasonable engagement even when idle.
- Early game: arrivals every 3–5 min; dwell 1–4 min; income low; upgrades cheap and quick (30–90s build time).
- Mid game: arrivals 1.5–3 min; mix introduces turboprops/regionals; upgrade timers 2–5 min.
- Late game: arrivals 45–90s with multiple runways; wide-bodies rare but lucrative; major builds 5–10 min.
- Parking must bottleneck early; runway length/surface bottlenecks mid; runway count/taxi capacity bottlenecks late.
- Provide offline progress: simulate elapsed time on return (capped).

## 6) AI Brain (LLM-guided)
- Input features: bank, recurring income rate, stand occupancy %, queue length, unlocked tiers, time-to-payback per upgrade, risk buffers.
- Action set: purchase specific upgrade, wait/hoard.
- Policy v0: deterministic heuristic (greedy ROI with safety buffer; bottleneck breaker between stands/runways).
- Policy v1: Local LLM call (Ollama on localhost) given a compact JSON state summary; prompt requests a single ranked upgrade choice plus rationale; fallback to heuristic if call fails or is rate-limited.
- Guardrails: clamp spend to bank minus safety buffer; enforce cooldowns/prereqs; sandbox prompt to avoid arbitrary actions.
- Explainability: console prints rationale from heuristic or LLM (e.g., Stand occupancy 92% -> buying GA stand).

## 7) Tech Stack (updated)
- Engine: Godot 4 (already initialized) using C# or GDScript; top-down 3D with placeholders; later swap to models.
- Data: JSON catalogs for aircraft and upgrades; deterministic RNG wrapper.
- AI/Logic: C# services; LLM calls via HTTP to local Ollama (localhost) with selectable models; local heuristic fallback when unavailable.
- UI: Godot UI with a polished, modern skin (coherent typography, spacing, color system); console + dashboards; later charts for flow rates.

## 8) Simulation Detail Targets
- Fixed update timestep (e.g., 0.1s) for movement/occupancy; render interpolation for smoothness.
- Runway occupancy modeled with safety buffers (roll + backtrack + exit).
- Taxi speed tiers; pushback optional for airliners later.
- Collision avoidance via segment reservations; fallback: hold short rules.

## 9) Data Structures (conceptual)
- `AirportState`: seed, time, bank, unlockedTiers, structures[], queues[], rngState.
- `Runway`: id, length, surface, heading, exits[], inUseUntil.
- `Stand`: id, class, position, status, occupiedUntil.
- `AircraftType`: id, class, fees, reqLength, reqSurface, standClass, dwellRange.
- `Arrival`: eta, typeId, assignedRunway, assignedStand.
- `Upgrade`: id, cost, buildTime, prereqs, effects.

## 10) Content Roadmap (tiers)
- Tier 0: Grass strip, 2–3 GA stands, single-prop traffic only.
- Tier 1: Paved extension, small taxiway loop, more GA stands, light twins.
- Tier 2: Concrete runway, regional turboprops/jets, small cargo ramp.
- Tier 3: Second runway + high-speed exit, narrow-body gates with jetways, fuel farm multiplier.
- Tier 4: Wide-body capable stand(s), longer runway, dedicated cargo apron, night ops/ILS.

## 11) UI & Feedback
- Top-down camera with simple orbit/zoom; toggle overlays for stands/runway status.
- Console log with filters (arrivals, departures, upgrades, AI decisions).
- HUD: bank, income rate, occupancy %, queue lengths, next arrivals forecast.
- Build/upgrade panel with costs, payback estimate, build timers.

## 12) Visuals & Audio (placeholder plan)
- Use primitive meshes for runway/taxi/stands; simple shaders; later swap to models.
- Particle hints for dust/heat; minimal lighting for readability.
- Audio cues for landings, cash register, construction.

## 13) Testing & Telemetry
- Deterministic sim with seed for reproducible tests.
- Unit tests for allocation (stand selection, runway eligibility), economy math, AI decision logic.
- Telemetry hooks: average occupancy, income rate, bottleneck flags; export to CSV for balancing.

## 14) Risks & Mitigations
- Pathing complexity → keep grid-snapped and segment reservations; avoid full navmesh early.
- Pacing drift → build live balance sheets + telemetry to tune spawn intervals and fees.
- AI feels random → print rationales; allow policy tuning sliders.
- Performance with many planes → cap concurrent aircraft; pool objects; simplify collision model.

## 15) MVP Scope (first playable)
- Single runway (grass → paved extension), GA + regional stands, 10–15 aircraft types, basic AI greedy policy, console log, offline progress.
- No weather/events; no multi-runway ops; basic camera/controls.
- Target: <4 weeks to first loop that runs unattended for 30+ minutes without deadlock.

## 16) Next Steps
- Engine locked to Godot 4; verify project settings (top-down camera, input map, placeholder materials). (in progress)
- Draft aircraft and upgrade catalogs with costs/requirements. (done; see data/aircraft.json and data/upgrades.json)
- Prototype traffic generator + stand allocation in isolation (headless).
- Implement console/log UI and deterministic RNG wrapper.
- Build first layout generator that ensures valid taxi path for initial stands.
