# Decisions

| Decision | What was done |
|---|---|
| Platform | **Native iOS (SwiftUI + RealityKit).** The 3D view is an `ARView` in non-AR mode, which gives a per-frame callback for projecting stars onto the screen. |
| Analysis | **Deterministic geometry, not a language model.** Reach, climb steps and climbing paths are computed from measured heights and distances and unit tested. |
| Physics | **Not used to decide flags.** The pull test is a separate, illustrative simulation and never changes a flag. |
| Pull model | A hand at the stage's reach height: up to 120 N, no faster than 0.6 m/s, over at most 40 cm. A fixed force launched light objects. Results vary slightly run to run. |
| Default age stage | **Walking.** At the placeholder Crawling thresholds the kitchen has no climbing paths; at Walking it has four. |
| Parameters | All placeholders, labelled "Assumption" in the UI. See `HAZARDS.md`. **Open: needs sources.** |
| Language model | Not wired in yet. SAM 3 prompts come from the concept list; fix plans come from a deterministic template (`FixPlanWriter`). No API key in the client. |
| Small hazards (outlets, cords) | A keyframe vision pass is planned, not built. The UI says small things may be missing. |
| Scores | **None.** Progress is "X of Y flags marked done". The app never says a room is safe. |
