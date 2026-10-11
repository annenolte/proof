# proof

## Inspiration

Existing baby-proofing apps analyze a single photo and return a list of hazards. A single photo cannot capture relationships between objects in 3D space. Many real hazards depend on those relationships: a stool placed next to a counter makes an object on the counter reachable, even though neither the stool nor the object is flagged as dangerous on its own. We wanted a tool that measures these relationships from a 3D reconstruction of the room.

## What it does

proof is an iOS app that flags child-safety hazards in a 3D model of a room, based on measured geometry. It is designed to take a walkthrough video as input: the room is reconstructed with Gaussian splatting and segmented into objects with SAM 3.

- **Object flags.** Each detected object is assigned a role (hazard, climbable, or both) and one or more hazard categories: heat, sharp items, cabinets and chemicals, small objects, cords and outlets, tip-over, falls, water, glass and breakables, corners and edges.
- **Age stage.** The user selects Crawling, Walking, or Climbing. Each stage has its own reach and climbing thresholds.
- **Reach analysis.** A hazard is reachable from a surface if its lowest point is within the stage's reach height above that surface and within the stage's horizontal reach of the surface's footprint.
- **Climbing paths.** The engine builds a graph of standable surfaces (floor, stool footrail, stool seat, chair seat, tabletop, shelf boards). An edge exists when the height difference and horizontal gap between two surfaces are within the stage's limits. A breadth-first search finds the shortest path from the floor to a surface from which an otherwise out-of-reach hazard becomes reachable.
- **Two views.** The constellation view shows every flagged object as a point and every measured relationship as a line. The climbing-paths view shows only the paths, one at a time, each with a one-sentence description and its measurements.
- **Fix plans.** The user groups flags into named fix plans. proof generates the plan text from the measured data using a fixed template with generic fix types (no product names). Saved plans are drawn in the 3D view as connected, labeled groups.
- **Checklist.** All flags are listed by category with a done/open state. Progress is shown as "X of Y flags marked done". The app does not compute a safety score. The checklist can be exported as Markdown.
- **Pull test.** For free-standing furniture, the user can run a physics simulation of a child pulling on the object, then rerun it with the object fixed in place to show the effect of anchoring. This is labeled as illustrative, not predictive.

## How we built it

- **Platform:** native iOS 18, Swift 5, SwiftUI, RealityKit. The 3D view is an `ARView` in non-AR mode, which provides a per-frame callback used to project 3D object positions to screen coordinates for the overlay.
- **3D scene:** a metric 3D model of a kitchen in RealityKit, with rigid-body physics and a breakage system for glass and ceramics.
- **Scene package:** an export test builds the 3D scene, measures every object in the 3D kitchen and writes `kitchen.scene.json` (56 objects): world-space bounding boxes in meters, concept label, role, hazard categories, and standable surface heights taken from the model's authored dimensions (for example, stool footrail 0.20 m and seat 0.676 m, not the top of the backrest).
- **Concept map:** `concepts/kitchen.yaml` maps each SAM 3 noun phrase to a role and hazard categories.
- **Analysis engine:** pure Swift with no RealityKit dependency. It runs on every user edit and is covered by 13 XCTest unit tests using synthetic scenes with known answers.
- **Physics:** RealityKit rigid bodies (PhysX). The pull is modeled as a speed- and distance-limited hand: force up to 120 N, applied only while the held point moves slower than 0.6 m/s and has moved less than 0.40 m.
- **Persistence:** user edits (removed or added flags, links, fix plans, done states) are stored as JSON in `UserDefaults`.
- **Build:** the Xcode project is generated from `project.yml` with XcodeGen.

## Challenges we ran into

- **3D reconstruction from short handheld video.** Structure-from-motion (COLMAP) registered only 2 of 122 extracted frames from a 10-second handheld clip because of motion blur and limited parallax. Without camera poses, a Gaussian splat cannot be trained, so the analysis runs on a metric 3D model of the kitchen.
- **Bounding boxes are not standing surfaces.** A chair's bounding box tops out at its backrest, not its seat. We added explicit surface heights per object type from the model's dimensions, so climbing steps use real seat and shelf heights.
- **Physics scaling with mass.** A fixed 120 N pull for 0.6 s barely moved a 26 kg shelf but launched a 6 kg chair at about 12 m/s. Replacing the fixed force with a hand limited by speed and travel fixed this: the chair now moves 0.25 m and leans 9°, while the shelf still tips (74°).
- **Visual clarity.** Showing all 54 points and every line at once was hard to read. We split the display into a full view and a simplified climbing-paths view that opens with one path and a plain-language sentence.
- **Unsourced thresholds.** Child reach and step heights need citations from pediatric or consumer-safety sources. All thresholds are currently placeholders and are labeled "Assumption" in the UI.

## Accomplishments that we're proud of

- A deterministic analysis engine that identifies hazards reachable only by climbing, with every result traceable to measured heights and distances.
- On the kitchen at the Walking stage, the engine finds 4 climbing paths (counter stool footrail → place settings and wine glasses on the breakfast bar). At the Crawling stage it finds 0. Switching stages updates the results immediately.
- Generated text uses only the structured data. No language model decides which objects are connected.
- The pull-and-anchor comparison shows the effect of anchoring furniture using the same physics run on the same scene.
- Consistent wording throughout: the app never states that a room is safe and never shows a score.

## What we learned

- Reconstruction quality depends heavily on capture: short, fast, handheld video does not produce enough well-conditioned views for structure-from-motion.
- Geometric reasoning on a graph of surfaces is simpler to test and explain than full physics simulation for determining reachability.
- Physics demonstrations need constraints based on human limits (speed, reach), not fixed forces, to produce plausible results across objects of different mass.
- Separating the analysis engine from the renderer made it possible to unit test the core logic on synthetic scenes.

## What's next for Proof

- Replace placeholder thresholds with values from cited pediatric and consumer-safety sources, recorded in `docs/HAZARDS.md`.
- Run the full pipeline on new captures: camera pose recovery, Gaussian splatting (gsplat), SAM 3 segmentation, and lifting 2D masks to 3D bounding boxes on a cloud GPU.
- Calibrate metric scale against physically measured objects and report the error.
- Add a keyframe vision pass for small hazards (outlets, cords, small objects) that the 3D reconstruction misses.
- Add a server-side, cached language-model step for translating the user's concern into SAM 3 prompts and drafting fix-plan text, with the template as a fallback.
- Evaluate accuracy by reviewing each flag and path against the real room, and record the results in `docs/EVAL.md`.
