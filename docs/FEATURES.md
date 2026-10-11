# proof — every feature

proof turns a 3D scan of a room into a sky of child-safety flags. Every object a small child could get hurt by, or climb on, is a star. Every measured relationship between them is a line. The app finds the **climbing paths** a single photo can't show — a stool's footrail, then a glass on the counter — and the caregiver crafts the fixes into named constellations.

**Flags to check, not a safety guarantee.** proof never calls a room safe and never gives it a score.

---

## Contents

1. [The constellation, explained](#1-the-constellation-explained)
2. [Script for the constellation part of the demo](#2-script-for-the-constellation-part-of-the-demo)
3. [First run](#3-first-run)
4. [Rooms tab](#4-rooms-tab)
5. [Adding a room](#5-adding-a-room)
6. [The room: constellation view](#6-the-room-constellation-view)
7. [The room: climbing-paths view](#7-the-room-climbing-paths-view)
8. [Tapping a flag](#8-tapping-a-flag)
9. [Fix plans (crafting constellations)](#9-fix-plans-crafting-constellations)
10. ["What if a child pulls on it?"](#10-what-if-a-child-pulls-on-it)
11. [Checklist](#11-checklist)
12. [Settings and "How proof works"](#12-settings-and-how-proof-works)
13. [The engine](#13-the-engine)
14. [What is real and what is not](#14-what-is-real-and-what-is-not)
15. [For rehearsing](#15-for-rehearsing)
16. [The full demo script](#the-full-demo-script-about-3-minutes)

---

## 1. The constellation, explained

There are only three ideas.

| In the sky | What it means in the room |
|---|---|
| **A star** | A flag: something proof found that matters for a small child. Lime stars are hazards (a glass, a stove, a lamp cord). Lavender stars are things a child can climb (a stool, a chair, a shelf). |
| **A line** | A measurement between two of them. Either "a child standing here can reach that" or "a child can step from this up onto that". Faint white lines join hazards that sit close together. |
| **A constellation** | A group of stars the caregiver names and turns into a fix plan — for example "Up counter stool 1": the stool, and the glasses it puts within reach. |

The **climbing-paths view** is the same sky with everything switched off except the lines that matter most: the routes from the floor, up through things a child can climb, to something that would otherwise be out of reach.

Put simply: **the constellation is the map; the climbing paths are the directions.**

---

## 2. Script for the constellation part of the demo

About 75 seconds. Plain words; the screen does the explaining.

**Before you start:** the room should be open in the constellation view (the title capsule says *Constellation view*, and the pill in the top corner says **Paths**). Rehearse with `-proofResetCraft` so no old fix plans are showing.

---

**[The room opens. Stars fade in across the kitchen, then lines join them.]**

> "This is the kitchen from that video, rebuilt in 3D. Every star is something proof flagged. Lime stars are hazards — glasses, the stove, the lamp. Lavender stars are things a toddler can climb — stools, chairs, the shelf."

**[Point at the lines on the island.]**

> "The lines are measurements. Each one says either *a child standing here can reach that*, or *a child can step from this up onto that*. Together, that's the room as a constellation."

**[Pause for a beat. Then tap the lime **Paths** pill in the top corner.]**

> "A sky is a lot to take in, so here's the part that matters."

**[Everything quiets down. A lime line draws itself up from the floor, onto the stool, to the wine glass. The card reads the sentence.]**

> "A toddler could step onto this stool's footrail — twenty centimetres — and reach the wine glass on the breakfast bar. The glass is out of reach from the floor. The stool is harmless on its own. Together, they're a path. A photo of this kitchen can't show you that."

**[Tap **Crawling** in the stage picker. The paths disappear. Tap **Walking** again.]**

> "And it's calculated, not drawn on. For a crawling baby that step is too high, so the path is gone. For a toddler, it's back."

**[Tap **Fix plan** on the path card. Name it — "Push the stools in" — and tap **Create**. Then tap the **Sky** pill.]**

> "Now I turn that path into a fix plan. And back in the sky — there it is. My plan is now a named constellation in the room. That's the idea behind proof: the app finds the stars, and you craft the constellations."

---

**If a judge asks…**

- *"Why stars?"* — "Because the danger isn't in one object, it's in the relationships between them. Stars and lines are the clearest way we found to show relationships."
- *"Is the constellation just decoration?"* — "No. Every line is a measured height or distance from the 3D model. Switch the age stage and the lines change."
- *"How do you know a toddler can make that step?"* — "We don't, yet. The thresholds are placeholders, and the app labels them as assumptions. Getting them from paediatric safety sources is the next step."

---

## 3. First run

Design: an ink background, lime buttons, and Inter / Instrument Sans type.

- **Onboarding carousel — three pages**, each with an animated illustration:
  1. *Your kitchen. In stars.* — a kitchen draws itself in 3D and a star appears on each object.
  2. *See the path up.* — a side view: floor → stool footrail (0.20 m) → glass on the counter (0.72 m), drawing itself.
  3. *Craft the fix plan.* — an anchor bracket fits a shelf, and a card shows a **real result from the engine** run on a sample kitchen (the wine-glass path and its fixes).
- **Sign in** — Sign in with Apple, or continue without an account. Nothing needs an account.
- **Camera primer** — explains why the camera is needed before iOS asks, and offers a walkthrough video if the camera is off.

## 4. Rooms tab

- **Check a room** — the ink hero card. Goes straight to "What are you getting ready for?".
- **Progress card** — "X of Y flags marked done" and the number of fix plans. Progress, never a score.
- **Kitchen card** — flags, climbing paths, the current age stage and progress. Opens the room in 3D if it is already built.
- **How proof works** link.

## 5. Adding a room

The **Add Room** tab, one step at a time:

1. **Name it** — with suggestions (Kitchen, Living room, Nursery, Playroom).
2. **What are you getting ready for?** — Crawling, Walking or Climbing. Below it, **"What SAM 3 will look for"**: the caregiver's concern turned into the object prompts (stove, bar stool, chair…).
3. **Film the room** — the guided capture screen, with **Use a walkthrough video** to use a 10-second walkthrough video instead of the live camera.
4. **Building your room** — an animated reconstruction: reading frames → camera poses → Gaussian splats fill in → SAM 3 masks outline objects one by one → each object becomes a star → reach and climb measured.
5. **The room** — opens in the constellation view.

## 6. The room: constellation view

The opening view. The title capsule reads *Constellation view*.

- **Stars fade in** one by one across the room, then the **lines** join them, then your **fix plans** draw over the top.
- **Lime stars** = hazards. **Lavender stars** = things a child can climb.
- **Lines**: lavender = a climb step, lime dashes = a reach, faint white = hazards close together, white dashes = links you drew.
- **Your fix plans appear as named constellations**: their stars joined by a bright line, with the name (✓ when done).
- **Card**: "Every flag is a star. Every measured link is a line." with the counts (stars, links, fix plans), a small key, **Show paths** and **Checklist**.
- **Top corner**: the lime **Paths** pill switches views; **•••** holds camera modes (Orbit, Walk, Plan) and dimming the room.
- Drag to orbit, pinch to zoom, tap a star to open it.

## 7. The room: climbing-paths view

The calm view. The title capsule reads *Climbing paths*; the corner pill reads **Sky**.

- **Only what matters glows.** Bright lime = a hazard reachable only by climbing. Lavender = a step on one of those paths. Small white dots = other reachable flags. Out-of-reach objects are not drawn. A three-item legend explains it.
- **The first path plays by itself** the first time you open this view: a lime line draws up from the floor, and the card says it in one sentence — *"A toddler could step onto the counter stool's footrail and reach the wine glass on the quartz breakfast bar."* — with the measurements underneath.
- **Next path / Fix plan** on the path card. "Climbing path 1 of 4".
- **Age stage: Crawling, Walking, Climbing.** Switching re-runs the engine instantly; paths appear and disappear.
- **Show climbing paths · N** steps through every path; **Checklist · X of Y done**.
- The camera frames each path above its card.

## 8. Tapping a flag

A short card:

- **Name**, and one plain heading: *Reachable by climbing*, *Within reach from the floor*, *A step a child can climb*, or *Out of reach for a toddler*.
- **What kind of hazard** (up to two) and **one suggested fix**.
- **One main action**: *Show the climbing path* (if it is on one) and/or *What if a child pulls on it?* (for free-standing furniture).
- **Mark done** for all of that object's flags.
- **More**: new fix plan with this flag, add to an existing fix plan, link to another flag, *Not a hazard — remove*, and the SAM 3 concept that found it.
- **Tapping something that isn't flagged** (the fridge, a fruit bowl) offers **Flag it**, with a choice of hazard type. Removed flags can be put back.

## 9. Fix plans (crafting constellations)

- **Make one** from a climbing path (**Fix plan**), from a flag (**More → New fix plan**), or by keeping a **suggestion** in the checklist.
- **proof drafts the plan** from the measured data only: each object, why it matters, and generic fixes ("Consider: move climbable furniture away; push chairs in"). No brands, no product links. It ends with "These are flags to check, not a safety guarantee."
- **Rename, mark done, show in the room, or delete** from the checklist.
- **Every fix plan appears in the sky** as a named constellation.
- **Hand-drawn links**: link one flag to another for something the engine can't measure; linked flags join a new plan together.
- Everything you do is **saved on the phone** and survives a relaunch.

## 10. "What if a child pulls on it?"

An illustrative physics moment on free-standing furniture (shelf, TV, floor lamp, stools, chairs).

- A child's **hand pulls** at the stage's reach height — up to 120 N, no faster than 0.6 m/s, over at most 40 cm — and the real-time physics engine runs.
- The **ladder shelf tips** onto the dining area; glass and ceramics **shatter** with sound. The card reports what happened: "Ladder shelving tipped over · 8 things came down · 5 broke."
- **Anchor it** reruns the same pull with the object held fixed: "Anchored, it stayed put." Only offered after something tips.
- **Reset** puts every object, shard and broken piece back.
- Labelled **"Illustrative, not a prediction"** with every assumption on the card. It never changes a flag.

## 11. Checklist

- **Banner**: *Flags to check, not a safety guarantee*, with what proof can't see.
- **Progress bar**: "X of Y flags marked done".
- **Fix plans**: your constellations, with the drafted plan, done toggle and a menu (rename, show in the room, delete). **Suggested from the climbing paths** below, each with **Keep as a fix plan**.
- **Climbing paths**: each as its sentence and measured steps; tap to see it in the room.
- **All flags**, grouped by category (Heat and burns, Sharp items, Cabinets and chemicals, Small objects, Cords and outlets, Tip-over, Falls, Water, Glass and breakables, Corners and edges), each with a done checkbox, its measured detail and badges (*Heuristic*, *By climbing*, *Out of reach*). Tap a flag to see it in the room.
- **Removed by you**, with *Put back*.
- **What proof can't see** — anchoring, latches, small things like outlets and cords, drawers pulled out, anything moved since filming.
- **Parameters**, each marked *Assumption*.
- **Export checklist** as Markdown, with the disclaimer at the top.
- **Reset my edits**.

## 12. Settings and "How proof works"

- **Settings**: your profile, the age stage, *Reset my edits*, the method, privacy and licences.
- **How proof works**: from video to flags, the engine, where the language model fits (and where it doesn't), what proof can't see, and the parameters.

## 13. The engine

Deterministic geometry, unit tested. No language model decides what is connected.

- **Scene package** — 56 objects measured from the 3D kitchen (`proof/Resources/kitchen.scene.json`), each with its SAM 3 concept, role (hazard / climbable / both) and real surface heights from the model (a stool's footrail at 0.20 m and seat at 0.68 m, not its backrest).
- **Concept map** — `concepts/kitchen.yaml`: noun phrase → hazard role and categories.
- **Reach** — a hazard is reachable from a surface if its lowest point is within the stage's reach height above it and within horizontal reach.
- **Climb** — a child can step from one surface to another if the rise and the gap are small enough for the stage.
- **Climbing paths** — the fewest steps from the floor to a surface where something out of reach from the floor comes within reach.
- **Flags** — by category from the concept map; tip-over by height ÷ base (heuristic); corners at head height (heuristic); falls for climbables; small objects and cords where the concept says so.
- **Nearby hazards** — hazards within 0.6 m of each other.
- **Results on the kitchen** (placeholder thresholds): Crawling — 0 paths. Walking — 4 paths (counter stools → place settings and wine glasses). Climbing — 4 paths (up the ladder shelf).

| Parameter | Crawling | Walking | Climbing |
|---|---|---|---|
| Reach above standing surface | 0.55 m | 0.90 m | 1.05 m |
| Horizontal reach | 0.30 m | 0.40 m | 0.50 m |
| Largest climb step | 0.20 m | 0.30 m | 0.50 m |
| Largest gap crossed | 0.10 m | 0.20 m | 0.30 m |

All are **assumptions** until sourced — see `docs/HAZARDS.md`.

## 14. Current limits

- Thresholds have no cited sources yet and are labelled *Assumption* in the app (`docs/HAZARDS.md`).
- The pull test uses assumed masses and an assumed pull; results vary slightly from run to run.
- No language-model call is wired in; fix plans come from a template.
- Accuracy has not been evaluated (`docs/EVAL.md`).

## 15. For rehearsing

### Build and run

```bash
./scripts/build.sh      # xcodegen + build for the iPhone 17 Pro simulator
./scripts/test.sh       # engine unit tests
```

Requires Xcode (set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `xcode-select` points at the Command Line Tools) and `xcodegen`. Never edit `proof.xcodeproj`; it is generated from `project.yml`.

### Shortcuts

```bash
./scripts/build.sh && ./scripts/test.sh     # build, and run the 13 tests

# Straight into the room (constellation view), clean slate:
xcrun simctl launch booted com.annenolte.proof -proofScreen addRoom -proofAddRoomStep exploring -proofResetCraft

# Straight into the climbing-paths view, first path playing:
xcrun simctl launch booted com.annenolte.proof -proofScreen addRoom -proofAddRoomStep exploring -proofPaths

# The shelf pull (add -proofAnchored for the anchored rerun):
xcrun simctl launch booted com.annenolte.proof -proofScreen addRoom -proofAddRoomStep exploring -proofPull living.ladderShelf

# Onboarding from the start, on page 2:
xcrun simctl launch booted com.annenolte.proof -proofResetState 1 -proofOnboardingPage 1
```

---

## The full demo script (about 3 minutes)

1. **The problem (20 s).** Onboarding page 2: "A photo can tell you a stove is hot. It can't tell you a stool, a counter and a glass form a path."
2. **The scan (40 s).** Rooms → **Check a room** → **Walking** → **Film the room** → **Use a walkthrough video** → Next. The reconstruction screen shows splatting, then SAM 3, then flags.
3. **The constellation (20 s).** The room opens as a sky: stars fade in on every flag, then the measured links join them. "Every flag is a star, every measured link is a line."
4. **The insight (30 s).** Tap the lime **Paths** pill in the top corner. The first climbing path plays by itself: "A toddler could step onto the counter stool's footrail and reach the wine glass on the breakfast bar." Point out the measured numbers.
5. **Proof it's computed (20 s).** Close the card, tap **Crawling**: the paths disappear, because a crawling baby can't make that step. Tap **Walking** again.
6. **The craft (30 s).** Show the path again → **Fix plan** → name it → tap **Sky**: your plan is now a named constellation in the room. Then **Checklist** → mark it done. "Progress, not a score."
7. **The closer (30 s).** Tap the ladder shelf → **What if a child pulls on it?** → it tips and things break → **Anchor it** → it stays. "Illustrative, not a prediction — the fix is a wall strap."
