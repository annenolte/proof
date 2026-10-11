//
//  Layout.swift
//  Tremor — Design System / Space, Shape, Elevation, Motion
//
//  Zip and Lyft agree on more than they disagree, and this file leans on the
//  agreement:
//
//    • Both are on a 4pt base with an 8pt primary rhythm.
//    • Both put 16–24pt on cards and 20–24pt on the top corners of sheets.
//    • Both use very soft, low-contrast shadows — Lyft's are a 1px ambient
//      hairline plus a small directional key; Zip's are the brand aubergine at
//      10% alpha. Tremor uses Lyft's *geometry* with Zip's *purple tint*.
//    • Both run their standard transitions at 250–300ms.
//
//  The one place they disagree is button shape: Zip's buttons are 8pt
//  rectangles, Lyft's are full pills. The brief resolves it — Tremor takes Lyft's
//  pill, because pills are also what carry Lyft's friendly, buttony silhouette,
//  which is the structure Tremor is copying.
//

import SwiftUI

// MARK: - Spacing

/// The spacing scale.
///
/// Lyft's observed scale is 2 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64.
/// Zip's token-derived scale is 4 / 8 / 12 / 16 / 24 / 32 / 36 / 40 / 48 / 64 / 80.
/// The intersection is used verbatim; nothing here is invented.
enum TremorSpacing {
    /// 2pt — Lyft `space-1`. Icon nudges, badge insets, title↔subtitle in dense rows.
    static let hair: CGFloat = 2
    /// 4pt — Lyft `space-2`, Zip `--svg-offset: 0.25rem`. Title↔subtitle gap.
    static let xxs: CGFloat = 4
    /// 8pt — Lyft `space-3`, Zip `--gap: 0.5rem`. Icon↔label, chip inner gap,
    /// vertical gap between stacked cards.
    static let xs: CGFloat = 8
    /// 12pt — Lyft `space-4`, Zip `--field-padding` / `--local-button-gap: 0.75rem`.
    /// Dense card padding, row vertical padding.
    static let sm: CGFloat = 12
    /// 16pt — Lyft `space-5`, Zip `--gap: 1rem`. Card padding, list-row inset.
    /// The single most-used value in Lyft's system.
    static let md: CGFloat = 16
    /// 20pt — Lyft `space-6`. Horizontal padding on large sheets.
    static let lg: CGFloat = 20
    /// 24pt — Lyft `space-7`, Zip `--gap`/`--curtains`/`--local-padding: 1.5rem`.
    /// Section spacing, card padding, sheet top padding below the grabber.
    static let xl: CGFloat = 24
    /// 32pt — Lyft `space-8`, Zip `--local-rhythm: 2rem`. Major section break.
    static let xxl: CGFloat = 32
    /// 40pt — Lyft `space-9`, Zip `--local-rhythm`/`--top-offset: 2.5rem`.
    /// Empty-state and above-CTA breathing room.
    static let xxxl: CGFloat = 40
    /// 48pt — Lyft `space-10`, Zip `--rhythm: 3rem`. Hero blocks, mobile section rhythm.
    static let section: CGFloat = 48
    /// 64pt — Lyft `space-11`, Zip `--rhythm: 4rem`. Marketing / onboarding blocks.
    static let hero: CGFloat = 64

    // ── Layout constants ────────────────────────────────────────────────

    /// **24pt.** The standard horizontal page inset applied by `.tremorScreen()`.
    /// Zip's mobile `--curtains` is 24pt; Lyft uses 16pt for dense map screens
    /// and 24pt on its onboarding/marketing screens. Tremor is a card-and-sheet
    /// consumer app with no map, so it takes the roomier 24pt everywhere and
    /// lets `listInset` handle dense rows.
    static let pageInset: CGFloat = 24

    /// **16pt.** Lyft's list-row content inset, leading and trailing. Used
    /// *inside* cards, where the card itself already supplies the page inset.
    static let listInset: CGFloat = 16

    /// **16pt.** Lyft: safe-area bottom + 16pt below the primary CTA.
    static let ctaBottomInset: CGFloat = 16

    /// **0.125s.** Zip's stagger delay between items in a list-entry animation.
    static let staggerDelay: Double = 0.125
}

// MARK: - Radii

/// Corner radii.
///
/// Lyft (post-2025 rebrand) is markedly rounder than Zip and is the structural
/// reference here; Zip agrees on cards (16–24) and on capsule chips.
enum TremorRadius {
    /// 4pt — Lyft `radius-xs`, Zip `--rounded-2`. Tags, progress-bar caps.
    static let xs: CGFloat = 4
    /// 8pt — Zip `--rounded-3` (their single most-used radius), Lyft `radius-sm`.
    /// Inline images, small thumbnails.
    static let sm: CGFloat = 8
    /// 12pt — Lyft `radius-md`. Thumbnails, ride-option rows, map overlay chips.
    static let thumbnail: CGFloat = 12
    /// 12pt — Lyft text field: height 56, radius 12.
    static let input: CGFloat = 12
    /// 16pt — Lyft `radius-lg`, Zip `--rounded-5`. **The card radius.**
    static let card: CGFloat = 16
    /// 24pt — Lyft bottom-sheet top corners, Zip `--rounded-6`. Top corners only.
    static let sheet: CGFloat = 24
    /// 20pt — Lyft modal/dialog radius.
    static let modal: CGFloat = 20
    /// 28pt — Lyft `radius-2xl`. Full-screen cards, illustration containers.
    static let xxl: CGFloat = 28
    /// Pill. **All buttons are full pills** — `cornerRadius = height / 2`. Lyft
    /// §4: "the single most identifying rule". Use with `Capsule()`, or this
    /// value with `RoundedRectangle`, which clamps to half the height.
    static let button: CGFloat = 999
    /// Pill. Chips, filter pills, badges, avatars, segmented thumbs. Zip and
    /// Lyft agree: true capsules (Zip measures r/h = 0.98 on its amount badge).
    static let chip: CGFloat = 999
}

// MARK: - Sizes

/// Component heights both systems specify explicitly.
enum TremorSize {
    /// 56pt — Lyft primary large CTA ("Confirm"). Zip's `mobileNative` button is
    /// 50pt; Lyft's 56 wins because Tremor's CTAs are docked in a sheet footer.
    static let buttonLarge: CGFloat = 56
    /// 48pt — Lyft primary medium.
    static let buttonMedium: CGFloat = 48
    /// 36pt — Lyft primary small / filter chip height. Zip's small button is
    /// also 36pt.
    static let buttonSmall: CGFloat = 36
    /// 56pt — Lyft text field height.
    static let field: CGFloat = 56
    /// 56pt — Lyft single-line list row.
    static let row: CGFloat = 56
    /// 72pt — Lyft two-line list row.
    static let rowTwoLine: CGFloat = 72
    /// 88pt — Lyft rich row with a 56pt thumbnail.
    static let rowRich: CGFloat = 88
    /// 56pt — Lyft top bar content height (+ safe area). Zip `--header-height`
    /// is also 56pt. Full agreement.
    static let topBar: CGFloat = 56
    /// 44 × 44pt — minimum tap target (Lyft §6.1, and Apple HIG).
    static let minimumTapTarget: CGFloat = 44
    /// 36 × 4pt, radius 2 — Lyft sheet grabber, ink @ 20%, 8pt from sheet top.
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 4
    /// 1pt — Zip `--divider-width`. Hairlines are 1pt; emphasised strokes 1.5pt.
    static let hairline: CGFloat = 1
    /// 1.5pt — Lyft selected-card border and focused-field border.
    static let strokeEmphasis: CGFloat = 1.5
}

// MARK: - Elevation

/// The elevation set.
///
/// Geometry is Lyft's Core UI ramp, converted from CSS to SwiftUI by halving the
/// blur (CSS blur radius ≈ 2 × SwiftUI shadow radius). Colour is Zip's — every
/// shadow in the system is the brand aubergine `#1A0826` at low alpha, never
/// black, which is what stops shadows reading as dirty grey on the warm canvas.
///
/// Both layers of Lyft's two-part shadow are preserved: a 1px ambient hairline
/// that defines the edge, plus a soft directional key that gives lift. These are
/// deliberately soft and low-contrast — do not reach for a heavy drop shadow.
enum TremorShadow: String, CaseIterable, Sendable {
    /// Lyft L1 — `0 0 1px rgba(.12), 0 1px 1px 1px rgba(.08)`.
    /// Dividers-as-cards, segmented-control thumbs, switch thumbs.
    case hairline
    /// Lyft L2 — `0 0 1px rgba(.12), 0 2px 3px rgba(.16)`. **The card shadow.**
    case card
    /// Lyft L4 — `0 0 1px rgba(.12), 0 3px 6px rgba(.16)`. Floating buttons.
    case raised
    /// Lyft L5 — `0 0 1px rgba(.12), 0 4px 8px rgba(.16)`. Sticky CTA bars.
    case lifted
    /// Lyft `panel` — `0 0 1px rgba(.12), 0 0 14px rgba(.16)`. **Omnidirectional
    /// glow, not a drop shadow.** This is the bottom-sheet shadow and it is a
    /// specific, copyable detail: the sheet floats in all directions rather than
    /// casting downward.
    case panel
    /// Lyft L8 — `0 6px 18px rgba(.12), 0 14px 20px rgba(.16)`. Full modals.
    case modal

    /// (colour, blur radius, x, y) layers, applied outermost-last.
    var layers: [(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)] {
        // Zip `--border-surface-1: rgba(26,8,38,0.1)`; Lyft's alphas .12 / .16
        // read heavier on a tinted colour than on black, so they are used as-is
        // for the ambient layer and dialled to .12 for the key layer.
        let ambient = Color(hex: 0x1A0826, opacity: 0.12)
        switch self {
        case .hairline:
            return [(ambient, 0.5, 0, 0),
                    (Color(hex: 0x1A0826, opacity: 0.08), 1, 0, 1)]
        case .card:
            return [(ambient, 0.5, 0, 0),
                    (Color(hex: 0x1A0826, opacity: 0.12), 1.5, 0, 1)]
        case .raised:
            return [(ambient, 0.5, 0, 0),
                    (Color(hex: 0x1A0826, opacity: 0.12), 3, 0, 2)]
        case .lifted:
            return [(ambient, 0.5, 0, 0),
                    (Color(hex: 0x1A0826, opacity: 0.12), 4, 0, 3)]
        case .panel:
            return [(ambient, 0.5, 0, 0),
                    (Color(hex: 0x1A0826, opacity: 0.14), 7, 0, 0)]
        case .modal:
            return [(Color(hex: 0x1A0826, opacity: 0.10), 9, 0, 3),
                    (Color(hex: 0x1A0826, opacity: 0.14), 10, 0, 7)]
        }
    }
}

extension View {
    /// Apply a Tremor elevation. Two-layer, purple-tinted, deliberately soft.
    func tremorShadow(_ level: TremorShadow) -> some View {
        level.layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y))
        }
    }
}

// MARK: - Motion

/// Animation curves and durations.
///
/// Lyft ships its motion tokens verbatim:
///
///     durations: { quick: 100, short: 200, shortExit: 200, medium: 300,
///                  mediumExit: 250, long: 350, longExit: 300 }
///     curves:    { enter:  cubic-bezier(0, 0, 0.15, 1),
///                  exit:   cubic-bezier(0.45, 0, 1, 1),
///                  change: cubic-bezier(0.45, 0, 0.15, 1) }
///
/// The design idea: `enter` starts instantly and decelerates hard, so arriving
/// content has zero lead-in latency; `exit` accelerates away with no settle; and
/// **exits are always shorter than enters**, so arrivals feel considered and
/// dismissals feel snappy.
///
/// Zip's numbers land in the same place (default 250ms, sheets 300ms, press
/// scale 0.95 at ~150ms) with one addition worth keeping: Zip animates
/// **colour changes linearly** — 41 occurrences of `linear` in their bundle,
/// their single most common timing function. They deliberately do not ease
/// colour. Tremor copies that as `.colorShift`.
enum TremorMotion {

    // ── Durations (seconds) ─────────────────────────────────────────────
    static let quick: Double = 0.10
    static let short: Double = 0.20
    static let medium: Double = 0.30
    static let mediumExit: Double = 0.25
    static let long: Double = 0.35
    static let longExit: Double = 0.30

    // ── Named animations ────────────────────────────────────────────────

    /// Press feedback — scale 1.0 → 0.97 over 100ms on the `change` curve.
    /// (Zip uses 0.95; Lyft's 0.97 is the subtler and more current of the two.)
    static let tap = Animation.timingCurve(0.45, 0, 0.15, 1, duration: quick)

    /// Release from a press. 200ms `change`.
    static let release = Animation.timingCurve(0.45, 0, 0.15, 1, duration: short)

    /// Content appearing: crossfade + 8pt rise, chip select, checkbox check.
    /// 300ms `enter` — instant start, hard deceleration.
    static let reveal = Animation.timingCurve(0, 0, 0.15, 1, duration: medium)

    /// Content leaving. 250ms `exit` — accelerates away, no settle.
    static let dismiss = Animation.timingCurve(0.45, 0, 1, 1, duration: mediumExit)

    /// Bottom sheet presenting from off-screen. 350ms `enter`.
    static let sheet = Animation.timingCurve(0, 0, 0.15, 1, duration: long)

    /// Bottom sheet dismissing off-screen. 300ms `exit`.
    static let sheetExit = Animation.timingCurve(0.45, 0, 1, 1, duration: longExit)

    /// Anything already on screen that moves or resizes: sheet detent snap,
    /// segmented thumb, layout reflow. 300ms `change` (symmetric ease).
    static let change = Animation.timingCurve(0.45, 0, 0.15, 1, duration: medium)

    /// Colour-only transitions. 250ms **linear** — Zip does not ease colour.
    static let colorShift = Animation.linear(duration: 0.25)

    /// The one place Tremor departs from both references. Earthquake results
    /// land with physical weight — a score counter settling, a risk chip
    /// dropping in — and a bezier cannot express that. Tuned to overshoot
    /// slightly then settle in roughly one `medium` beat.
    static let springy = Animation.spring(response: 0.34, dampingFraction: 0.78)

    /// Delay between items in a staggered list entry. Zip: 125ms.
    static let staggerDelay: Double = TremorSpacing.staggerDelay

    /// Press scale factor. Lyft §6.1.
    static let pressScale: CGFloat = 0.97
}

// MARK: - Screen

private struct TremorScreenModifier: ViewModifier {
    let inset: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TremorColor.canvas.ignoresSafeArea())
    }
}

extension View {
    /// Standard Tremor page chrome: the warm off-white canvas edge to edge, and
    /// the standard 24pt horizontal page inset on the content.
    ///
    /// Apply to the root of every screen. For content that must bleed to the
    /// screen edge (a full-width 3D viewport, an edge-to-edge carousel), pass
    /// `inset: 0` and apply `TremorSpacing.pageInset` to the inner text blocks
    /// instead.
    func tremorScreen(inset: CGFloat = TremorSpacing.pageInset) -> some View {
        modifier(TremorScreenModifier(inset: inset))
    }
}
