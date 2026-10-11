# Hazards and parameters

**Status: no parameter has a cited source yet.** Every value below is a placeholder and is shown in the app with an "Assumption" badge (CLAUDE.md §3 rule 2). Do not quote any of them as guidance.

Source of truth: `proof/Core/Safety/SafetyParameters.swift`. To source a value, add the citation here and change its provenance to `.sourced(citation:)`.

| Parameter | Crawling | Walking | Climbing | Source |
|---|---|---|---|---|
| Reach above standing surface | 0.55 m | 0.90 m | 1.05 m | TODO |
| Horizontal reach | 0.30 m | 0.40 m | 0.50 m | TODO |
| Largest climb step | 0.20 m | 0.30 m | 0.50 m | TODO |
| Largest gap crossed | 0.10 m | 0.20 m | 0.30 m | TODO |
| Tip-over height ÷ base | 3.0× | 3.0× | 3.0× | TODO |
| Tip-over minimum height | 0.60 m | 0.60 m | 0.60 m | TODO |
| Cluster distance | 0.60 m | 0.60 m | 0.60 m | TODO |
| Corner flag band | 0.30–0.60 m | 0.30–0.80 m | 0.30–0.95 m | TODO |

## Pull test (illustrative physics only)

The pull is modelled as a hand, not a fixed force: force is applied only while the held point is slower than the hand speed and has moved less than the hand travel, up to the cap. A fixed force threw light objects (a 6 kg chair) across the room.

| Assumption | Value | Source |
|---|---|---|
| Pull force (cap) | 120 N | TODO — placeholder |
| Hand speed (max) | 0.6 m/s | TODO — placeholder |
| Hand travel (max) | 0.40 m | TODO — placeholder |
| Pull duration (max) | 1.0 s | TODO — placeholder |
| Pull height | the stage's reach height, capped at 90 % of the object | as above |
| Object masses | the 3D model's estimates | not measured |

## Categories

Heat and burns · Sharp items · Cabinets and chemicals · Small objects · Cords and outlets · Tip-over · Falls · Water · Glass and breakables · Corners and edges. Fix types are generic (no brands). Wording lives in `HazardKind` in `SafetyModel.swift`.

## Stage 4 to-do

Find authoritative child-safety guidance (pediatric or consumer-safety organisations) for each category and any usable reach, climb or tip-over numbers. Where none exists, keep the value as a labelled assumption.
