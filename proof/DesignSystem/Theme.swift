//
//  Theme.swift
//  Tremor — Design System / Colour
//
//  The Tremor palette is a synthesis of two shipped design languages:
//
//    • Zip (zip.co) — "Confidence" near-black aubergine #1A0826, the "Fearless"
//      purple ramp (#EDE6FF … #6542BE), and the "Yuzu" lime accent #E6FE72.
//      Zip's core move is that *no neutral is ever a true grey* — every black,
//      every grey and every shadow is tinted toward purple.
//
//    • Lyft (Core UI / LPL) — the warm off-white canvas #F1F0EC, the discipline
//      of building secondary/tertiary text as *alpha over the primary ink*
//      rather than as separate greys, and the restraint of using the loud brand
//      colour almost nowhere.
//
//  Tremor's three anchors:
//      ink     #1A0826  (Zip Confidence)
//      canvas  #F1F0EC  (Lyft off-white)
//      primary #6542BE  (Zip Fearless dark — the interactive purple)
//
//  Everything else is derived from, or harmonised against, those three.
//
//  App is light-appearance-locked (UIUserInterfaceStyle: Light in project.yml),
//  so there are deliberately no dark-mode variants here.
//

import SwiftUI

// MARK: - Hex helper

extension Color {
    /// Build a colour from a 24-bit RGB hex literal, e.g. `Color(hex: 0x6542BE)`.
    ///
    /// Always resolves in the sRGB colour space so tokens are device-independent
    /// and match the hex values quoted in the research documents exactly.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Colour tokens

/// The complete Tremor colour token set.
///
/// Every value is declared with an explicit sRGB initialiser (never a named
/// asset, never a system colour) so that the shipped pixels match the research
/// hexes exactly and so the values are testable.
enum TremorColor {

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Ink (the text ramp on light)
    // ─────────────────────────────────────────────────────────────────────

    /// `#1A0826` — Zip `--brand-confidence-base`. hsl(281°, 65%, 9%): a purple
    /// at 9% lightness, *not* a grey. This is the single highest-leverage token
    /// in the system; never substitute `#000` or a neutral grey for it.
    /// Contrast: 16.64:1 on `canvas`, 18.98:1 on `surface`. AAA everywhere.
    static let ink = Color(.sRGB, red: 26 / 255, green: 8 / 255, blue: 38 / 255, opacity: 1)

    /// `#1A0826` @ 72%. Lyft builds `text-secondary` as alpha over the primary
    /// ink (they use 70%) rather than as a separate grey — that is why Lyft text
    /// sits so cleanly on tinted cards. 72% is the smallest step that keeps AA
    /// on the warm canvas.
    /// Flattens to `#56495D` on `canvas` → 7.35:1. AA for body text.
    static let inkSecondary = Color(.sRGB, red: 26 / 255, green: 8 / 255, blue: 38 / 255, opacity: 0.72)

    /// `#1A0826` @ 62%. Lyft `text-tertiary` is ink @ 60%; nudged to 62% so it
    /// still clears AA against Tremor's warmer, slightly darker canvas.
    /// Flattens to `#6C6071` on `canvas` → 5.19:1. AA for body text.
    static let inkTertiary = Color(.sRGB, red: 26 / 255, green: 8 / 255, blue: 38 / 255, opacity: 0.62)

    /// `#FFFFFA` — Zip `--background` / `--text-primary` (dark theme). A warm
    /// off-white, never pure `#FFFFFF`, used for type on saturated fills.
    /// Contrast: 6.81:1 on `primary`. AA for all sizes.
    static let inkInverse = Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 250 / 255, opacity: 1)

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Surfaces
    // ─────────────────────────────────────────────────────────────────────

    /// `#F1F0EC` — Lyft `background-secondary` / brand "Off-white". Warm paper.
    /// The page background for every Tremor screen.
    static let canvas = Color(.sRGB, red: 241 / 255, green: 240 / 255, blue: 236 / 255, opacity: 1)

    /// `#FFFFFF` — Lyft `surface-primary`. The card fill. Cards read as generous
    /// white plates floating on the warm canvas; that contrast *is* the Lyft
    /// structure and it is what gives Tremor its air.
    static let surface = Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 255 / 255, opacity: 1)

    /// `#FFFFFA` — Zip `--background`. Very slightly warm; used for surfaces
    /// that float *above* a card (sheets over cards, popovers) so the stack
    /// separates by temperature as well as by shadow.
    static let surfaceRaised = Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 250 / 255, opacity: 1)

    /// `#E9E7E3` — derived: Lyft `surface-secondary` (`#362201` @ 7–11%, a
    /// *brown*-tinted alpha, not grey) flattened onto white at 11%. Used for
    /// recessed wells: progress tracks, segmented-control tracks, input fills.
    static let surfaceSunken = Color(.sRGB, red: 233 / 255, green: 231 / 255, blue: 227 / 255, opacity: 1)

    /// `#1A0826` @ 30% — Lyft `background-scrim` (ink @ 30%), re-tinted to
    /// Tremor's aubergine ink. Behind expanded sheets and modals.
    static let scrim = Color(.sRGB, red: 26 / 255, green: 8 / 255, blue: 38 / 255, opacity: 0.30)

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Interactive
    // ─────────────────────────────────────────────────────────────────────

    /// `#6542BE` — Zip `--brand-fearless-dark`. Tremor's primary interactive
    /// colour: button fills, links, focus rings, selection.
    /// Contrast: 5.99:1 on `canvas`, 5.64:1 on `primarySoft`. AA for text.
    static let primary = Color(.sRGB, red: 101 / 255, green: 66 / 255, blue: 190 / 255, opacity: 1)

    /// `#5737A3` — derived: `primary` mixed 18% toward `ink`. Zip's own pressed
    /// state is an *alpha* reduction of the fill, which lightens on light
    /// backgrounds; on Tremor's warm canvas a press must read as "pushed in", so
    /// we darken toward the aubergine instead.
    /// Contrast: 8.44:1 against `onPrimary`. AA for all sizes.
    static let primaryPressed = Color(.sRGB, red: 87 / 255, green: 55 / 255, blue: 163 / 255, opacity: 1)

    /// `#EDE6FF` — Zip `--brand-fearless-lightest` / `--surface-primary`. The
    /// workhorse lavender fill: secondary buttons, selected rows, info panels.
    static let primarySoft = Color(.sRGB, red: 237 / 255, green: 230 / 255, blue: 255 / 255, opacity: 1)

    /// `#FFFFFA` — Zip's primary-button label colour. Warm white on purple.
    /// Contrast: 6.81:1 on `primary`. AA for all sizes.
    static let onPrimary = Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 250 / 255, opacity: 1)

    /// `#E6FE72` — Zip `--brand-yuzu-light`. The acid lime "surprise" surface.
    /// Zip uses it across roughly **2–5% of any given screen** and never as
    /// text on white (1.12:1 — it fails badly). Only ever a *fill*, with `ink`
    /// on top (16.97:1).
    static let accent = Color(.sRGB, red: 230 / 255, green: 254 / 255, blue: 114 / 255, opacity: 1)

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Lines
    // ─────────────────────────────────────────────────────────────────────

    /// `#D7D3CC` — derived: Lyft `stroke-tertiary` (`#362201` @ 20%) flattened
    /// on white. Card outlines and unselected chip borders. 1pt.
    static let stroke = Color(.sRGB, red: 215 / 255, green: 211 / 255, blue: 204 / 255, opacity: 1)

    /// `#B9B2B4` — Lyft `gray30`. The warm, plum-tinted mid grey. Used for
    /// emphasised borders and disabled control outlines. 1.5pt.
    static let strokeStrong = Color(.sRGB, red: 185 / 255, green: 178 / 255, blue: 180 / 255, opacity: 1)

    /// `#E7E5E1` — derived: Lyft `stroke-tertiary` at 12% on white. Hairline
    /// rules inside cards. Lyft prefers whitespace and tinted fills over rules,
    /// so use this sparingly.
    static let divider = Color(.sRGB, red: 231 / 255, green: 229 / 255, blue: 225 / 255, opacity: 1)

    /// `#6542BE` @ 15% — Zip `--focus-ring: 0 0 0 4px rgba(131,100,191,0.15)`.
    static let focusRing = Color(.sRGB, red: 101 / 255, green: 66 / 255, blue: 190 / 255, opacity: 0.15)

    /// `#1A0826` @ 10% — Zip `--border-surface-1`. Every shadow in the system is
    /// the brand aubergine at low alpha, never black. See `TremorShadow`.
    static let shadowTint = Color(.sRGB, red: 26 / 255, green: 8 / 255, blue: 38 / 255, opacity: 0.10)

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Risk bands — the most important semantic colours in the app
    // ─────────────────────────────────────────────────────────────────────
    //
    //  DESIGN RATIONALE
    //
    //  The user reads the band before they read anything else, and a large
    //  fraction of them will read it under stress. So the ramp must survive
    //  (a) colour-vision deficiency, (b) glare, and (c) a half-second glance.
    //
    //  Red-vs-green carries no information for a deuteranope or protanope, so
    //  the ramp encodes severity **three times over**:
    //
    //   1. HUE, on the blue↔yellow axis that dichromats retain:
    //        teal-cyan 192° → amber 40° → vermilion 14° → crimson-plum 338°.
    //      Cool→warm, and the two "loud" bands sit next to the brand's own
    //      purple on the wheel so the palette stays coherent.
    //
    //   2. RELATIVE LUMINANCE of the mark, strictly monotonically *decreasing*
    //      as severity rises — severity literally gets heavier:
    //        Low 0.1368 → Moderate 0.0923 → High 0.0600 → Severe 0.0329
    //      Every adjacent pair differs by ≥ 0.027 absolute luminance and
    //      ≥ 1.29:1 contrast with each other. Enforced in DesignSystemTests.
    //
    //   3. LUMINANCE OF THE SURFACE, also monotonically decreasing
    //        0.835 → 0.814 → 0.701 → 0.590
    //      so the filled chip darkens and saturates as risk rises, which is
    //      legible even in greyscale.
    //
    //  Each band ships as a saturated `mark` (icon, rule, numeral, label) and a
    //  soft `surface` (chip fill, card tint). All eight are opaque sRGB values.
    //
    //  CONTRAST (measured, sRGB relative luminance, WCAG 2.1 formula):
    //
    //   Band      mark    on its surface   on canvas   on white   ink on surface
    //   ───────────────────────────────────────────────────────────────────────
    //   Low       #0A7189      4.83:1        4.93:1     5.62:1        16.31:1
    //   Moderate  #754E00      6.07:1        6.47:1     7.38:1        15.61:1
    //   High      #80260A      6.83:1        8.37:1     9.55:1        13.57:1
    //   Severe    #6B0029      7.72:1       11.11:1    12.67:1        11.56:1
    //
    //  Every mark clears **4.5:1 on its own surface**, i.e. AA for body text —
    //  not merely the 3:1 UI-component floor — so band labels can be set at
    //  caption size inside a tinted chip without exception.
    //

    /// `#0A7189` — Low. Teal-cyan, hue 192°. Derived from Lyft's `teal`/`cyan`
    /// ramps (`#13766C`, `#1572A1`), darkened to hit 4.5:1 on its own surface.
    /// The calm, cool end of the ramp and the only cool band.
    static let riskLowMark = Color(.sRGB, red: 10 / 255, green: 113 / 255, blue: 137 / 255, opacity: 1)

    /// `#DFF1F6` — Low surface. Pale cyan wash, in the family of Lyft `cyan10`
    /// `#CCE9FF` but warmed and desaturated to sit on the `#F1F0EC` canvas.
    static let riskLowSurface = Color(.sRGB, red: 223 / 255, green: 241 / 255, blue: 246 / 255, opacity: 1)

    /// `#754E00` — Moderate. Deep amber/bronze, hue 40°. Between Lyft `amber70`
    /// `#803F00` and `yellow60` `#976300`, tuned to the luminance ladder.
    static let riskModerateMark = Color(.sRGB, red: 117 / 255, green: 78 / 255, blue: 0 / 255, opacity: 1)

    /// `#FBE7BE` — Moderate surface. Between Lyft `yellow10` `#FFE1B0` and
    /// Zip's sand `--surface-quaternary` `#FAE2B9`.
    static let riskModerateSurface = Color(.sRGB, red: 251 / 255, green: 231 / 255, blue: 190 / 255, opacity: 1)

    /// `#80260A` — High. Dark vermilion/rust, hue 14°. Derived from Lyft
    /// `orange70` `#922800` / `sunset70` `#9C0205`, darkened one more step so
    /// it separates from Moderate by luminance as well as hue.
    static let riskHighMark = Color(.sRGB, red: 128 / 255, green: 38 / 255, blue: 10 / 255, opacity: 1)

    /// `#FBD1C4` — High surface. Lyft `orange10` `#FFDED5` pulled darker and
    /// warmer so the chip visibly weighs more than Moderate's.
    static let riskHighSurface = Color(.sRGB, red: 251 / 255, green: 209 / 255, blue: 196 / 255, opacity: 1)

    /// `#6B0029` — Severe. Crimson-plum, hue 338°. Between Lyft `pink90`
    /// `#6F004A` and `rose70` `#9F0045`; deliberately the closest band to the
    /// brand aubergine `#1A0826` so the loudest state still reads as Tremor.
    static let riskSevereMark = Color(.sRGB, red: 107 / 255, green: 0 / 255, blue: 41 / 255, opacity: 1)

    /// `#F9B8D0` — Severe surface. Lyft `pink15` `#FFCAEA` warmed and deepened.
    /// The only band surface with real chroma — it is meant to be alarming.
    static let riskSevereSurface = Color(.sRGB, red: 249 / 255, green: 184 / 255, blue: 208 / 255, opacity: 1)

    // ─────────────────────────────────────────────────────────────────────
    // MARK: Semantic states
    // ─────────────────────────────────────────────────────────────────────

    /// `#0F7A4F` — derived from Lyft `mint70` `#015E36` / `green60` `#2C7B30`.
    /// Zip defines no success colour at all (its own research flags the gap), so
    /// this comes from Lyft. Contrast 5.36:1 on white, 4.70:1 on canvas.
    /// Note: success is *not* a risk band — the Low band is teal, not green,
    /// precisely so "safe" is never carried by green alone.
    static let success = Color(.sRGB, red: 15 / 255, green: 122 / 255, blue: 79 / 255, opacity: 1)

    /// `#8A5300` — derived from Lyft `amber60` `#AA5801`, darkened for AA.
    /// Contrast 6.33:1 on white, 5.55:1 on canvas.
    static let warning = Color(.sRGB, red: 138 / 255, green: 83 / 255, blue: 0 / 255, opacity: 1)

    /// `#B3172F` — Lyft `red60` `#C81534` darkened slightly. Preferred over
    /// Zip's `--error: #B00020`, which is stock Material red taken as-is and
    /// sits badly next to the warm neutrals.
    /// Contrast 6.82:1 on white, 5.98:1 on canvas.
    static let danger = Color(.sRGB, red: 179 / 255, green: 23 / 255, blue: 47 / 255, opacity: 1)

    /// `#2160BE` — Lyft `blue60` `#276AD0` darkened for AA on the warm canvas.
    /// Contrast 6.03:1 on white, 5.29:1 on canvas.
    static let info = Color(.sRGB, red: 33 / 255, green: 96 / 255, blue: 190 / 255, opacity: 1)
}

// MARK: - Risk band

/// The four-step safety ramp Tremor reports after a simulation.
///
/// Declaration order is the severity order and is load-bearing: the colour
/// ladder in `TremorColor` is monotonic in this order and the design-system
/// tests assert that.
enum TremorRiskBand: String, CaseIterable, Hashable, Sendable {
    case low
    case moderate
    case high
    case severe

    /// Saturated colour for icons, numerals, rules and labels.
    var mark: Color {
        switch self {
        case .low: return TremorColor.riskLowMark
        case .moderate: return TremorColor.riskModerateMark
        case .high: return TremorColor.riskHighMark
        case .severe: return TremorColor.riskSevereMark
        }
    }

    /// Soft tinted fill for chips, cards and band backgrounds.
    var surface: Color {
        switch self {
        case .low: return TremorColor.riskLowSurface
        case .moderate: return TremorColor.riskModerateSurface
        case .high: return TremorColor.riskHighSurface
        case .severe: return TremorColor.riskSevereSurface
        }
    }

    /// User-facing name. Always shown alongside the colour — colour is never
    /// the sole carrier of the band.
    var title: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .severe: return "Severe"
        }
    }
}
