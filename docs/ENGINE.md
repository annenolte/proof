# How the engine works

Every star, line and climbing path in proof comes from a few measured numbers per object (heights and horizontal distances in metres) compared against per-stage limits. This document explains exactly how, with real numbers from the kitchen.

Source code: `proof/Core/Safety/` — `SafetyModel.swift`, `SafetyParameters.swift`, `ConceptCatalog.swift`, `SafetyEngine.swift`. Tests: `Tests/EngineTests.swift`.

---

## 1. What a star is

Each star is one `SceneObject` from `proof/Resources/kitchen.scene.json` (56 objects). Each object stores:

| Field | Example (Counter stool 1) | Where it comes from |
|---|---|---|
| `aabb` (min/max, metres) | min (1.48, 0.00, 2.12), max (1.96, 1.01, 2.67) | World-space axis-aligned bounding box of the 3D mesh |
| `surfaces` | [0.20, 0.676] | Heights a child can stand on (footrail, seat) |
| `concept` | "bar stool" | The SAM 3 noun phrase |
| `role` | `both` | hazard / climbable / both / neutral |
| `hazards` | [tipOver, falls] | Categories from `concepts/kitchen.yaml` |

Coordinates are metres, with y pointing up and the floor at y = 0.

### Two sources of measurement

1. **The bounding box** comes from RealityKit: `entity.visualBounds(relativeTo: nil)` on each object in the 3D kitchen, measured after the physics settle so objects sit where they actually rest. In the full pipeline, these boxes come from SAM 3 masks lifted to 3D. The model is in metres.
2. **Standable surfaces** come from the model's authored dimensions, not the box. A chair's box tops out at the backrest (0.85 m), but a child stands on the seat (0.452 m), and a box can't tell you that. So each climbable concept has explicit surface heights:
   - stool: footrail 0.20 m, seat 0.676 m
   - chair: 0.452 m
   - dining table: 0.74 m
   - counter and island: 0.92 m
   - ladder shelf: boards at 0.30, 0.77, 1.24, 1.71 and 2.18 m

### Values derived from the box

- **lowest point** = `aabb.min.y`. Used for reach.
- **top** = `aabb.max.y`. Used for corners, and as the surface height for climbables without explicit surfaces (e.g. the pouf).
- **footprint** = the box's x/z rectangle. Used for horizontal gaps.
- **star position** on screen = (box centre x, top + 0.04 m, box centre z).

---

## 2. The parameters (per age stage)

| | Crawling | Walking | Climbing |
|---|---|---|---|
| Reach above the surface stood on | 0.55 m | 0.90 m | 1.05 m |
| Horizontal reach | 0.30 m | 0.40 m | 0.50 m |
| Largest step up | 0.20 m | 0.30 m | 0.50 m |
| Largest gap crossed between surfaces | 0.10 m | 0.20 m | 0.30 m |

All of these are placeholders until sourced (`SafetyParameters.swift`, `docs/HAZARDS.md`). The app labels each one "Assumption".

---

## 3. The geometric tests

### Horizontal gap between two footprints (`AABB.footprintGap`)

```
dx  = max(0, B.min.x − A.max.x, A.min.x − B.max.x)
dz  = max(0, B.min.z − A.max.z, A.min.z − B.max.z)
gap = √(dx² + dz²)          // 0 if the rectangles overlap
```

### Climb step, from surface A (height hA) to surface B (height hB)

```
rise = hB − hA
valid if  0.02 < rise ≤ stepMax
      and gap(A, B) ≤ gapMax          // gap = 0 from the floor, or between surfaces of the same object
```

### Reach, from a surface at height h to a hazard H

```
valid if  H.lowest − h ≤ reachHeight
      and H.top ≥ h                   // some of it is above where the child stands
      and gap(surface object, H) ≤ horizontalReach   // from the floor: no horizontal limit
```

---

## 4. Building the climbing paths (`SafetyEngine.analyze`)

1. **Nodes:** the floor (height 0) plus one node per standable surface of every climbable object. A stool contributes two nodes; the ladder shelf contributes five.
2. **Edges:** every pair of nodes that passes the climb-step test. Only upward steps count.
3. **Breadth-first search from the floor,** which gives each surface its fewest number of steps. Ties go to the lower surface, then by id, so results are deterministic.
4. **For each hazard:**
   - If it's reachable from the floor, it's flagged **"within reach from the floor."** No path is needed.
   - Otherwise, the engine checks every surface the search reached and keeps those the hazard is reachable from. It picks the one with the fewest steps and walks back through the search to the floor. That route is a **climbing path**.
   - If no surface reaches it, it's flagged **"not reachable at this stage."**

---

## 5. Worked example: the wine-glass path (Walking stage)

- **Counter stool 1** box: x 1.48–1.96, z 2.12–2.67. Footrail at 0.20 m, seat at 0.676 m.
- **Wine glass 1** box: x 2.18–2.26, z 2.96–3.04, lowest point 0.92 m.

| Check | Calculation | Result |
|---|---|---|
| Glass from the floor | 0.92 − 0 = 0.92 > 0.90 | ✗ just out of reach |
| Floor → footrail | rise 0.20 ≤ 0.30 | ✓ |
| Footrail → seat | rise 0.476 > 0.30 | ✗ |
| Footrail → glass, vertical | 0.92 − 0.20 = 0.72 ≤ 0.90 | ✓ |
| Footrail → glass, horizontal | dx = 2.18 − 1.96 = 0.22, dz = 2.96 − 2.67 = 0.29, gap = √(0.22² + 0.29²) = 0.364 ≤ 0.40 | ✓ |

**Result:** floor → stool footrail → wine glass. The card shows "step up 0.20 m · reach 0.72 m up, 0.36 m across."

### Why the stage changes the answer

- **Crawling:** the footrail step works (0.20 ≤ 0.20), but the reach fails (0.72 > 0.55). No path.
- **Climbing:** the glass is reachable straight from the floor (0.92 ≤ 1.05). That makes it a floor-reachable flag, not a path.

Paths only appear when the measurements land in the specific range where climbing matters, which is why the stage switch makes them appear and disappear.

### Results on the whole kitchen

| Stage | Flags | Climbing paths |
|---|---|---|
| Crawling | 55 | 0 |
| Walking | 57 | 4 — counter stools 1 and 2 → place settings 1 and 2 and wine glasses 1 and 2 |
| Climbing | 57 | 4 — up the ladder shelf boards to the items on its upper shelves |

Printed by `Tests/KitchenReportTests.swift`.

---

## 6. What every line is (constellation view)

| Line | Meaning | Rule |
|---|---|---|
| Lavender solid | Climb step | Every graph edge between two object surfaces (e.g. chair seat 0.452 → table 0.74: rise 0.29, gap ≈ 0). Floor edges aren't drawn because the floor has no star. |
| Lime dashed | Reach | Only the reach step that completes each climbing path |
| Faint white | Nearby hazards | Two hazards whose box centres are within 0.60 m (3D distance) |
| White dashed | Your link | Drawn by hand, no measurement |
| Bright line + name | Fix plan | Your plan's stars joined in the order you added them |

The kitchen has 60 of these lines at the Walking stage.

In the climbing-paths view, the same data is filtered: only hazards at the end of a path glow lime, only climbables on a path glow lavender, other reachable flags are small white dots, and lines appear only for the lit path or the selected star.

---

## 7. Other flags that use dimensions

- **Tip-over (heuristic):** flagged when height ÷ the narrower footprint side ≥ 3.0 and height ≥ 0.60 m.
  - floor lamp: 1.58 / 0.40 = 3.95 → flagged
  - ladder shelf: 2.32 / 0.46 = 5.0 → flagged
  - stool: 1.01 / 0.48 = 2.1 → not flagged
- **Corners (heuristic):** table tops between 0.30 m and the stage's upper limit (0.60 / 0.80 / 0.95 m), meaning edges at a child's head height. At Walking: coffee table 0.35, dining table 0.74 and console 0.80 are flagged.
- **Falls:** every climbable, with its highest standable surface.
- **Category flags** (heat, breakable, chemicals and so on) come from the concept map, with reachability from the search above.

---

## 8. How it gets on screen

Every rendered frame, `ARView.project(_:)` converts each star's 3D position into a screen point (`ConstellationModel.project(in:)`). A SwiftUI `Canvas` (`StarOverlay.swift`) draws the stars and lines there, with invisible 30-pt buttons on top for tapping. Stars are drawn over the 3D view, so they show even when furniture is in front of them. Positions are only rewritten when a point moves by more than half a point, so a still camera doesn't redraw the overlay.

The engine re-runs on every edit (stage change, removed or added star, new link). It processes about 56 objects, so this is instant.

---

## 9. Approximations to know about

- **Axis-aligned boxes.** Boxes don't rotate with objects, so an angled object, like the dining chairs set around the round table, gets a box larger than the object. Its gaps come out smaller than reality, which leans toward flagging. Oriented boxes would fix this.
- **The horizontal reach test uses the object's whole footprint,** not the specific surface. For the stool, it measures from the stool's outer edge, not from the footrail ring.
- **Surface heights are hand-assigned per concept.** In a real splat pipeline they would need to be estimated, e.g. by fitting horizontal planes to the Gaussians inside each SAM 3 mask.
- **Scale.** A splat from video has arbitrary scale and needs calibration against a physically measured object.
- **No physics decides a flag.** The pull test is a separate, illustrative simulation; it never changes the engine's output.
