//
//  Components+Controls.swift
//  Tremor — Design System / Controls
//
//  Buttons, icon buttons, chips, segmented selectors, text fields, steppers,
//  sliders and toggles. Everything a Tremor screen can tap, type into or drag.
//
//  ─────────────────────────────────────────────────────────────────────────
//  RULES THIS FILE OBEYS
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. **No raw values.** Every colour comes from `TremorColor`, every type style
//     from `TremorType` via `.tremorType(_:)`, every gap from `TremorSpacing`,
//     every radius from `TremorRadius`, every height from `TremorSize`, every
//     curve from `TremorMotion`. The handful of component-anatomy numbers the
//     three foundation files do not carry (switch track, segmented thumb,
//     slider geometry, glyph sizes) live in exactly one place —
//     `TremorControlMetrics` — each with its research citation. Nothing is
//     inlined into a view body.
//
//  2. **Shape.** All buttons, chips, segmented thumbs and toggles are full
//     pills (`Capsule`). Lyft §4: "the single most identifying rule". Inputs
//     take `TremorRadius.input`.
//
//  3. **Press.** Every interactive component darkens *and* scales to
//     `TremorMotion.pressScale` (0.97 / 100ms, Lyft §6.1). Press is never
//     communicated by colour alone.
//
//  4. **Colour is never the only channel.** Selected chips gain a checkmark,
//     the risk-band slider bubble prints the band's *name*, error fields print
//     the message with a symbol, the toggle's thumb position carries state.
//
//  5. **Reduce Motion.** Every animation in this file is routed through
//     `TremorMotion.resolved(_:reduceMotion:)`, which returns `nil` — i.e. an
//     instant change — when the user has asked for reduced motion.
//
//  6. **No reach-out.** These components hold no state that isn't theirs, talk
//     to no network, own no singleton, and mutate no model. Data in via
//     `let`/`Binding`, intent out via closures.
//
//  ─────────────────────────────────────────────────────────────────────────
//  A NOTE ON THE BUTTON LABEL FACE
//  ─────────────────────────────────────────────────────────────────────────
//  The brief asks for an Instrument Sans SemiBold button label. The sanctioned
//  ramp in `Typography.swift` exposes Instrument Sans SemiBold only at ≥24pt
//  (`title2`, `title1`, `displayM`) — far too large for a 56pt pill — and its
//  one Instrument Sans style at button scale is `title3` (20/26, Medium). So
//  large and medium buttons are set in `.title3`: the display face, at the
//  largest weight the ramp offers below 24pt. That is deliberately bigger and
//  more confident than Lyft's 17/500 button label, which is the Zip half of
//  the synthesis showing through. Small buttons drop to `.subheadline` (Inter
//  Medium 15) because 20pt display type in a 36pt pill has no room to breathe.
//

import SwiftUI
import UIKit

// MARK: - Component metrics

/// Component-anatomy constants that the foundation files do not carry.
///
/// Every value here is traced to a line in the research. This enum exists so
/// that no view body in this file ever contains a bare number — if you need a
/// new dimension, add it here with its provenance rather than inlining it.
public enum TremorControlMetrics {

    // ── Interaction overlays ────────────────────────────────────────────

    /// Lyft §1.6: disabled is a **62% white veil over the component**, not a
    /// grey colour swap. Copying this keeps disabled states legible on tinted
    /// fills and means every variant disables identically.
    public static let disabledVeil: Double = 0.62

    /// Lyft §1.6 interaction states: pressed = ink @ 10% over the base fill.
    /// Applied to every filled variant except `.primary`, which has its own
    /// darkened token (`TremorColor.primaryPressed`).
    public static let pressTint: Double = 0.10

    /// Zip §7.1 tertiary/ghost button: `active: rgba(101,66,190,0.08)` — the
    /// press is a wash of the interactive purple, not of ink.
    public static let ghostPressTint: Double = 0.08

    // ── Glyphs ──────────────────────────────────────────────────────────

    /// 24pt — Lyft §6.3/§6.6 list and nav-bar icons.
    public static let glyphLarge: CGFloat = 24
    /// 20pt — Zip §7.1 medium/large button svg size.
    public static let glyphMedium: CGFloat = 20
    /// 16pt — Zip §7.1 small button svg size; Lyft chevrons.
    public static let glyphSmall: CGFloat = 16

    // ── Segmented control (Lyft §6.7) ───────────────────────────────────

    /// Track height 40, radius full, `surface-secondary` fill.
    public static let segmentTrackHeight: CGFloat = 40
    /// 3pt internal padding, giving a 34pt thumb.
    public static let segmentPadding: CGFloat = 3

    // ── Switch (Lyft §6.8) ──────────────────────────────────────────────

    /// Track 51 × 31, thumb 27 at a 2pt inset, travel 20pt over 200ms.
    public static let switchTrackWidth: CGFloat = 51
    public static let switchTrackHeight: CGFloat = 31
    public static let switchThumbDiameter: CGFloat = 27
    public static let switchThumbInset: CGFloat = 2

    // ── Stepper (Lyft §6.8) ─────────────────────────────────────────────

    /// 40pt circular −/+ buttons with the value between them.
    public static let stepperButtonDiameter: CGFloat = 40

    // ── Slider ──────────────────────────────────────────────────────────
    //
    //  Not specified by either reference — Lyft ships a 4pt progress *bar*
    //  (§6.9) but no draggable slider, and Zip has none at all. Tremor's
    //  intensity slider is the one control the user drags for several seconds
    //  at a time, so the track is deliberately heavier than a progress bar
    //  (10pt, so the four-band gradient is actually readable as a ramp) and
    //  the thumb is a 28pt disc inside a 44pt tap row (Lyft §6.1 minimum).

    /// 10pt — thick enough for the four-band gradient to read as a ramp.
    public static let sliderTrackHeight: CGFloat = 10
    /// 28pt visible disc, white with `TremorShadow.raised`, inside a 44pt row.
    public static let sliderThumbDiameter: CGFloat = 28
    /// Minimum width of the value bubble; also the clamp width used to keep the
    /// bubble inside the track's bounds at either end.
    public static let sliderBubbleMinWidth: CGFloat = 104

    // ── Focus ring (Zip §7.2) ───────────────────────────────────────────

    /// `--focus-ring: 0 0 0 4px rgba(131,100,191,0.15)`.
    public static let focusRingWidth: CGFloat = 4
}

// MARK: - Motion helper

extension TremorMotion {
    /// The animation to use, or `nil` (an instant change) when the user has
    /// asked for reduced motion.
    ///
    /// Every animated property in this file goes through here. Reduce Motion
    /// removes the *movement*, never the state change: a pressed button still
    /// darkens, a segmented thumb still lands under the new segment, it just
    /// gets there in one frame.
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Haptics

/// The Tremor haptic vocabulary.
///
/// A namespace of stateless functions, not a singleton — nothing is retained
/// between calls, so components stay free of shared mutable state. Components
/// that fire haptics in a tight loop (the slider) own a prepared generator in
/// their own `@State` instead.
public enum TremorHaptic {
    /// Discrete value change: a detent, a segment, a chip.
    case selection
    /// Light tap: secondary/tertiary buttons, chips, steppers.
    case light
    /// Medium tap: primary and accent CTAs — the ones that commit.
    case medium
    /// Positive outcome.
    case success
    /// Destructive or boundary-hit.
    case warning
    /// Failure.
    case error

    @MainActor
    public func play() {
        switch self {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - TremorButton

/// Visual weight of a `TremorButton`.
public enum TremorButtonVariant: String, CaseIterable, Sendable {
    /// Solid interactive purple. One per screen, ideally docked.
    case primary
    /// Lavender fill, purple label. Zip §7.1 secondary, verbatim.
    case secondary
    /// Text only. Zip's ghost button — transparent, but the same hue, so the
    /// press wash animates cleanly out of nothing.
    case tertiary
    /// Solid danger. Delete, discard, stop the simulation.
    case destructive
    /// The yuzu lime. Zip uses it on **2–5% of a screen** — one moment per
    /// screen, never two.
    case accent

    /// Resting fill.
    var fill: Color {
        switch self {
        case .primary: return TremorColor.primary
        case .secondary: return TremorColor.primarySoft
        case .tertiary: return .clear
        case .destructive: return TremorColor.danger
        case .accent: return TremorColor.accent
        }
    }

    /// Pressed fill. `.primary` swaps to its own darkened token rather than
    /// taking an overlay — Zip's press *lightens* (alpha reduction) which reads
    /// wrong on a warm canvas, so Tremor darkens toward the aubergine instead.
    var pressedFill: Color {
        switch self {
        case .primary: return TremorColor.primaryPressed
        default: return fill
        }
    }

    /// Ink laid over the fill on press, on top of `pressedFill`.
    var pressOverlay: Color {
        switch self {
        case .primary: return .clear
        case .tertiary: return TremorColor.primary.opacity(TremorControlMetrics.ghostPressTint)
        default: return TremorColor.ink.opacity(TremorControlMetrics.pressTint)
        }
    }

    /// Label and glyph colour.
    var foreground: Color {
        switch self {
        case .primary: return TremorColor.onPrimary
        case .secondary: return TremorColor.primary
        case .tertiary: return TremorColor.primary
        case .destructive: return TremorColor.inkInverse
        case .accent: return TremorColor.ink
        }
    }

    /// Haptic fired on tap. Committing actions get more weight.
    var haptic: TremorHaptic {
        switch self {
        case .primary, .accent: return .medium
        case .destructive: return .warning
        case .secondary, .tertiary: return .light
        }
    }
}

/// Height class of a `TremorButton`.
public enum TremorButtonSize: String, CaseIterable, Sendable {
    /// 56pt — the docked CTA. Lyft §6.1 primary large.
    case large
    /// 48pt — in-flow actions. Lyft §6.1 primary medium.
    case medium
    /// 36pt — inline actions and toolbars. Lyft/Zip both land on 36.
    case small

    var minHeight: CGFloat {
        switch self {
        case .large: return TremorSize.buttonLarge
        case .medium: return TremorSize.buttonMedium
        case .small: return TremorSize.buttonSmall
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .large: return TremorSpacing.xl
        case .medium: return TremorSpacing.lg
        case .small: return TremorSpacing.md
        }
    }

    /// See the file header for why large/medium use the display face.
    var labelStyle: TremorType {
        switch self {
        case .large, .medium: return .title3
        case .small: return .subheadline
        }
    }

    var glyphSize: CGFloat {
        switch self {
        case .large, .medium: return TremorControlMetrics.glyphMedium
        case .small: return TremorControlMetrics.glyphSmall
        }
    }

    /// Zip §7.1: 8pt icon↔label gap at medium/large, 4pt at small.
    var iconGap: CGFloat {
        switch self {
        case .large, .medium: return TremorSpacing.xs
        case .small: return TremorSpacing.xxs
        }
    }
}

/// The primary action control.
///
/// ```swift
/// TremorButton("Run the earthquake") { start() }
/// TremorButton("Rescan", variant: .secondary, size: .medium, leadingIcon: "arrow.clockwise") { rescan() }
/// TremorButton("Saving…", isLoading: true) { }
/// ```
///
/// - Loading keeps the button's width stable: the label stays laid out and is
///   simply made invisible while a spinner is overlaid on top of it, so a
///   docked CTA never jumps as it changes state.
/// - Disabled is a 62% white veil (Lyft), applied over the finished button, so
///   fills, borders and labels all fade together.
/// - Use `.disabled(_:)` as normal; the style reads `\.isEnabled`.
public struct TremorButton: View {
    private let title: String
    private let variant: TremorButtonVariant
    private let size: TremorButtonSize
    private let leadingIcon: String?
    private let trailingIcon: String?
    private let isLoading: Bool
    private let fillsWidth: Bool
    private let hint: String?
    private let action: () -> Void

    /// - Parameters:
    ///   - title: the label. Wraps to two lines before it truncates.
    ///   - variant: visual weight. Defaults to `.primary`.
    ///   - size: height class. Defaults to `.large`.
    ///   - leadingIcon: SF Symbol name shown before the label.
    ///   - trailingIcon: SF Symbol name shown after the label.
    ///   - isLoading: shows an inline spinner and blocks taps without
    ///     disabling (so the button does not also take the disabled veil).
    ///   - fillsWidth: stretch to the container width. Defaults to `true`,
    ///     which is what a docked CTA wants; pass `false` for inline actions.
    ///   - hint: VoiceOver hint, for actions whose outcome is not obvious from
    ///     the label alone.
    ///   - action: fired on tap, after the variant's haptic.
    public init(_ title: String,
                variant: TremorButtonVariant = .primary,
                size: TremorButtonSize = .large,
                leadingIcon: String? = nil,
                trailingIcon: String? = nil,
                isLoading: Bool = false,
                fillsWidth: Bool = true,
                hint: String? = nil,
                action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.size = size
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.isLoading = isLoading
        self.fillsWidth = fillsWidth
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        Button {
            variant.haptic.play()
            action()
        } label: {
            HStack(spacing: size.iconGap) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: size.glyphSize, weight: .semibold))
                }
                Text(title)
                    .tremorType(size.labelStyle)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: size.glyphSize, weight: .semibold))
                }
            }
        }
        .buttonStyle(TremorButtonPillStyle(variant: variant,
                                          size: size,
                                          isLoading: isLoading,
                                          fillsWidth: fillsWidth))
        // Taps are swallowed while loading rather than disabled, so the button
        // keeps its full-strength appearance instead of taking the 62% veil.
        .allowsHitTesting(!isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text("In progress") : Text(""))
        .accessibilityHint(hint.map(Text.init) ?? Text(""))
    }
}

/// The pill treatment. Split out so `@Environment(\.isEnabled)` and
/// `@Environment(\.accessibilityReduceMotion)` can be read — a `ButtonStyle`
/// is not a `View`, so it cannot read the environment itself.
private struct TremorButtonPillStyle: ButtonStyle {
    let variant: TremorButtonVariant
    let size: TremorButtonSize
    let isLoading: Bool
    let fillsWidth: Bool

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration,
             variant: variant,
             size: size,
             isLoading: isLoading,
             fillsWidth: fillsWidth)
    }

    fileprivate struct Inner: View {
        let configuration: Configuration
        let variant: TremorButtonVariant
        let size: TremorButtonSize
        let isLoading: Bool
        let fillsWidth: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed

            configuration.label
                .foregroundStyle(variant.foreground)
                // Label stays laid out while loading so the width never moves.
                .opacity(isLoading ? 0 : 1)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, TremorSpacing.xs)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.minHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(pressed ? variant.pressedFill : variant.fill)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(pressed ? variant.pressOverlay : .clear)
                        }
                }
                .overlay {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(variant.foreground)
                    }
                }
                .clipShape(Capsule(style: .continuous))
                .overlay {
                    // Lyft's disabled treatment: a white veil over the finished
                    // component, so fill and label fade as one material.
                    if !isEnabled {
                        Capsule(style: .continuous)
                            .fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
                    }
                }
                .scaleEffect(pressed ? TremorMotion.pressScale : 1)
                .animation(TremorMotion.resolved(pressed ? TremorMotion.tap : TremorMotion.release,
                                                reduceMotion: reduceMotion),
                           value: pressed)
                .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                           value: isLoading)
                .contentShape(Capsule(style: .continuous))
        }
    }
}

// MARK: - TremorIconButton

/// Treatment of a `TremorIconButton`.
public enum TremorIconButtonStyleVariant: String, CaseIterable, Sendable {
    /// White disc with `TremorShadow.raised`. Lyft's floating map control.
    case surface
    /// Translucent material. **For sitting on top of the 3D viewport**, where
    /// the content behind is arbitrary and a flat fill would either vanish or
    /// punch a hole.
    case material
    /// Solid interactive purple. A circular commit action.
    case primary
    /// No chrome at all — glyph only. Nav bars over the canvas.
    case ghost

    var foreground: Color {
        switch self {
        case .primary: return TremorColor.onPrimary
        case .surface, .material, .ghost: return TremorColor.ink
        }
    }

    var shadow: TremorShadow? {
        switch self {
        case .surface, .material: return .raised
        case .primary: return .hairline
        case .ghost: return nil
        }
    }
}

/// Diameter class of a `TremorIconButton`.
public enum TremorIconButtonSize: String, CaseIterable, Sendable {
    /// 48pt — Lyft's floating map control.
    case large
    /// 44pt — the minimum tap target; nav bars.
    case medium
    /// 36pt — dense toolbars and overlay clusters.
    case small

    var diameter: CGFloat {
        switch self {
        case .large: return TremorSize.buttonMedium
        case .medium: return TremorSize.minimumTapTarget
        case .small: return TremorSize.buttonSmall
        }
    }

    var glyphSize: CGFloat {
        switch self {
        case .large: return TremorControlMetrics.glyphLarge
        case .medium: return TremorControlMetrics.glyphMedium
        case .small: return TremorControlMetrics.glyphSmall
        }
    }
}

/// A circular icon button for nav bars, overlays and 3D content.
///
/// ```swift
/// TremorIconButton(systemImage: "xmark", label: "Close") { dismiss() }
/// TremorIconButton(systemImage: "camera.rotate", style: .material, label: "Flip camera") { flip() }
/// ```
///
/// `label` is required, not optional: an icon-only control has no visible text,
/// so without it VoiceOver reads the SF Symbol name.
public struct TremorIconButton: View {
    private let systemImage: String
    private let style: TremorIconButtonStyleVariant
    private let size: TremorIconButtonSize
    private let label: String
    private let hint: String?
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - systemImage: SF Symbol name.
    ///   - style: chrome treatment. `.material` for anything over 3D content.
    ///   - size: diameter class. Defaults to `.medium` (44pt).
    ///   - label: **required** VoiceOver label.
    ///   - hint: optional VoiceOver hint.
    ///   - isSelected: renders the selected (filled) state and reports
    ///     `.isSelected` to VoiceOver.
    ///   - action: fired on tap, after a light haptic.
    public init(systemImage: String,
                style: TremorIconButtonStyleVariant = .surface,
                size: TremorIconButtonSize = .medium,
                label: String,
                hint: String? = nil,
                isSelected: Bool = false,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.label = label
        self.hint = hint
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            TremorHaptic.light.play()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size.glyphSize, weight: .semibold))
        }
        .buttonStyle(TremorIconButtonDiscStyle(style: style, size: size, isSelected: isSelected))
        .accessibilityLabel(Text(label))
        .accessibilityHint(hint.map(Text.init) ?? Text(""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TremorIconButtonDiscStyle: ButtonStyle {
    let style: TremorIconButtonStyleVariant
    let size: TremorIconButtonSize
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, style: style, size: size, isSelected: isSelected)
    }

    fileprivate struct Inner: View {
        let configuration: Configuration
        let style: TremorIconButtonStyleVariant
        let size: TremorIconButtonSize
        let isSelected: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed

            configuration.label
                .foregroundStyle(isSelected ? TremorColor.onPrimary : style.foreground)
                .frame(width: size.diameter, height: size.diameter)
                .background { disc(pressed: pressed) }
                .clipShape(Circle())
                .modifier(OptionalShadow(level: style.shadow))
                .overlay {
                    if !isEnabled {
                        Circle().fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
                    }
                }
                .scaleEffect(pressed ? TremorMotion.pressScale : 1)
                .animation(TremorMotion.resolved(pressed ? TremorMotion.tap : TremorMotion.release,
                                                reduceMotion: reduceMotion),
                           value: pressed)
                .contentShape(Circle())
        }

        @ViewBuilder
        private func disc(pressed: Bool) -> some View {
            ZStack {
                if isSelected {
                    Circle().fill(TremorColor.primary)
                } else {
                    switch style {
                    case .surface:
                        Circle().fill(TremorColor.surface)
                    case .material:
                        // Light-appearance-locked, so `.regularMaterial` always
                        // resolves light: the disc reads as frosted glass over
                        // the 3D scene rather than as a hole punched in it.
                        Circle().fill(.regularMaterial)
                    case .primary:
                        Circle().fill(TremorColor.primary)
                    case .ghost:
                        Circle().fill(.clear)
                    }
                }
                if pressed {
                    Circle().fill(TremorColor.ink.opacity(TremorControlMetrics.pressTint))
                }
            }
        }
    }
}

/// Applies a `TremorShadow` only when there is one — `tremorShadow(_:)` takes a
/// non-optional level, and `if let` inside a modifier chain would change the
/// view's type.
private struct OptionalShadow: ViewModifier {
    let level: TremorShadow?

    func body(content: Content) -> some View {
        if let level {
            content.tremorShadow(level)
        } else {
            content
        }
    }
}

// MARK: - TremorChip

/// A pill filter / selector chip.
///
/// Selection is expressed with **ink, not colour** (Lyft §9: "selection is
/// expressed with ink … reserving the magenta family for actions"), and a
/// checkmark appears alongside so the state survives greyscale, glare and
/// colour-vision deficiency.
///
/// ```swift
/// TremorChip("Bookcases", isSelected: filter == .bookcases) { filter = .bookcases }
/// TremorChip("Severe", systemImage: "exclamationmark.triangle.fill", count: 3, isSelected: false) { … }
/// ```
public struct TremorChip: View {
    private let title: String
    private let systemImage: String?
    private let count: Int?
    private let isSelected: Bool
    private let showsSelectionCheck: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    /// - Parameters:
    ///   - title: chip label.
    ///   - systemImage: optional leading SF Symbol.
    ///   - count: optional trailing count badge (e.g. how many objects match).
    ///   - isSelected: selected state.
    ///   - showsSelectionCheck: draws a checkmark when selected so selection is
    ///     not carried by fill colour alone. Defaults to `true`; turn it off
    ///     only in a single-select row where the fill is unambiguous **and**
    ///     something else already names the selection.
    ///   - action: fired on tap, after a selection haptic.
    public init(_ title: String,
                systemImage: String? = nil,
                count: Int? = nil,
                isSelected: Bool = false,
                showsSelectionCheck: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.isSelected = isSelected
        self.showsSelectionCheck = showsSelectionCheck
        self.action = action
    }

    private var foreground: Color { isSelected ? TremorColor.inkInverse : TremorColor.ink }

    public var body: some View {
        Button {
            TremorHaptic.selection.play()
            action()
        } label: {
            HStack(spacing: TremorSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                }
                Text(title)
                    .tremorType(.subheadline)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .tremorType(.captionEmphasis, numeric: true)
                        .padding(.horizontal, TremorSpacing.xs)
                        .padding(.vertical, TremorSpacing.hair)
                        .background {
                            Capsule().fill(isSelected
                                           ? TremorColor.inkInverse.opacity(TremorControlMetrics.disabledVeil / 2)
                                           : TremorColor.surfaceSunken)
                        }
                }
                if isSelected && showsSelectionCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .bold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.xs)
            .frame(minHeight: TremorSize.buttonSmall)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(isSelected ? TremorColor.ink : TremorColor.surface)
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .clear : TremorColor.stroke,
                                      lineWidth: TremorSize.hairline)
                    if isPressed {
                        Capsule(style: .continuous)
                            .fill(isSelected
                                  ? TremorColor.surface.opacity(TremorControlMetrics.pressTint)
                                  : TremorColor.ink.opacity(TremorControlMetrics.pressTint))
                    }
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                if !isEnabled {
                    Capsule(style: .continuous)
                        .fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
                }
            }
            .scaleEffect(isPressed ? TremorMotion.pressScale : 1)
        }
        .buttonStyle(TremorPressReporter(isPressed: $isPressed))
        .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                   value: isSelected)
        .animation(TremorMotion.resolved(isPressed ? TremorMotion.tap : TremorMotion.release,
                                        reduceMotion: reduceMotion),
                   value: isPressed)
        .accessibilityLabel(Text(count.map { "\(title), \($0)" } ?? title))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(Text(isSelected ? "Double tap to remove this filter"
                                           : "Double tap to apply this filter"))
    }
}

/// A `ButtonStyle` that only reports the press back to the owning view, leaving
/// all rendering to the label. Used where the pressed treatment is easier to
/// express in the label than in a style (chips, rows).
private struct TremorPressReporter: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule(style: .continuous))
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - TremorSegmentedControl

/// A pill-in-pill segmented selector over any `CaseIterable & Identifiable`
/// type, with a thumb that slides between segments.
///
/// ```swift
/// enum Mode: String, CaseIterable, Identifiable { case before, after; var id: Self { self } }
/// TremorSegmentedControl(selection: $mode) { $0.rawValue.capitalized }
/// ```
///
/// The thumb is one view, not one per segment: each segment publishes an
/// invisible source frame through `matchedGeometryEffect`, and the single thumb
/// follows whichever frame matches the current selection. That is what makes it
/// *slide* rather than crossfade, and it means the animation is driven purely by
/// the selection binding.
public struct TremorSegmentedControl<Item: CaseIterable & Identifiable & Hashable>: View {
    @Binding private var selection: Item
    private let items: [Item]
    private let title: (Item) -> String
    private let icon: (Item) -> String?
    private let accessibilityTitle: String

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameters:
    ///   - selection: the currently selected case.
    ///   - items: the segments. Defaults to every case, in declaration order.
    ///   - label: VoiceOver label for the control as a whole.
    ///   - icon: optional SF Symbol per segment.
    ///   - title: the visible text for each segment.
    public init(selection: Binding<Item>,
                items: [Item] = Array(Item.allCases),
                label: String = "Selection",
                icon: @escaping (Item) -> String? = { _ in nil },
                title: @escaping (Item) -> String) {
        self._selection = selection
        self.items = items
        self.accessibilityTitle = label
        self.icon = icon
        self.title = title
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // The one and only thumb. `isSource: false` makes it a follower of
            // whichever segment currently owns the id.
            Capsule(style: .continuous)
                .fill(TremorColor.surface)
                .tremorShadow(.hairline)
                .matchedGeometryEffect(id: selection, in: thumb, isSource: false)

            HStack(spacing: 0) {
                ForEach(items) { item in
                    segment(item)
                }
            }
        }
        .padding(TremorControlMetrics.segmentPadding)
        .background {
            Capsule(style: .continuous).fill(TremorColor.surfaceSunken)
        }
        .clipShape(Capsule(style: .continuous))
        .overlay {
            if !isEnabled {
                Capsule(style: .continuous)
                    .fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
            }
        }
        .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                   value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityTitle))
    }

    @ViewBuilder
    private func segment(_ item: Item) -> some View {
        let isSelected = item == selection

        Button {
            guard item != selection else { return }
            TremorHaptic.selection.play()
            selection = item
        } label: {
            HStack(spacing: TremorSpacing.xxs) {
                if let name = icon(item) {
                    Image(systemName: name)
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                }
                Text(title(item))
                    .tremorType(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? TremorColor.ink : TremorColor.inkTertiary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: TremorControlMetrics.segmentTrackHeight
                   - TremorControlMetrics.segmentPadding * 2)
            .contentShape(Rectangle())
            // Invisible source frame the thumb tracks.
            .background {
                Color.clear.matchedGeometryEffect(id: item, in: thumb, isSource: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title(item)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - TremorTextField

/// A labelled text input with a focus ring, an error state and a secure
/// variant.
///
/// ```swift
/// TremorTextField("Room name", text: $name, placeholder: "Living room")
/// TremorTextField("Passcode", text: $code, isSecure: true, errorMessage: wrong ? "That code didn't work" : nil)
/// ```
///
/// Focus is a **1.5pt purple border plus a 4pt purple halo** — Zip's
/// `--focus-ring: 0 0 0 4px rgba(131,100,191,0.15)` combined with Lyft's 1.5pt
/// `stroke-interactive`. Error swaps the border to `danger` and prints the
/// message beneath with a warning symbol, so the failure is never colour-only.
public struct TremorTextField: View {
    private let label: String
    @Binding private var text: String
    private let placeholder: String
    private let isSecure: Bool
    private let errorMessage: String?
    private let helpText: String?
    private let leadingIcon: String?
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    private let submitLabel: SubmitLabel
    private let autocapitalization: TextInputAutocapitalization
    private let onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var isRevealed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - label: the field's visible label, above the input.
    ///   - text: the bound value.
    ///   - placeholder: shown when empty. Never the only label — a placeholder
    ///     disappears the moment the user types, so `label` always shows too.
    ///   - isSecure: renders a secure entry field with a reveal toggle.
    ///   - errorMessage: non-nil switches the field to its error state and
    ///     prints the message beneath.
    ///   - helpText: shown beneath when there is no error.
    ///   - leadingIcon: optional SF Symbol in the leading well.
    ///   - keyboardType: keyboard to present.
    ///   - textContentType: autofill semantics.
    ///   - submitLabel: return-key label.
    ///   - autocapitalization: defaults to `.sentences`.
    ///   - onSubmit: fired when the return key is pressed.
    public init(_ label: String,
                text: Binding<String>,
                placeholder: String = "",
                isSecure: Bool = false,
                errorMessage: String? = nil,
                helpText: String? = nil,
                leadingIcon: String? = nil,
                keyboardType: UIKeyboardType = .default,
                textContentType: UITextContentType? = nil,
                submitLabel: SubmitLabel = .done,
                autocapitalization: TextInputAutocapitalization = .sentences,
                onSubmit: (() -> Void)? = nil) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.errorMessage = errorMessage
        self.helpText = helpText
        self.leadingIcon = leadingIcon
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.submitLabel = submitLabel
        self.autocapitalization = autocapitalization
        self.onSubmit = onSubmit
    }

    private var hasError: Bool { errorMessage != nil }

    private var borderColor: Color {
        if hasError { return TremorColor.danger }
        if isFocused { return TremorColor.primary }
        return TremorColor.stroke
    }

    private var borderWidth: CGFloat {
        (hasError || isFocused) ? TremorSize.strokeEmphasis : TremorSize.hairline
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text(label)
                .tremorType(.subheadline)
                .foregroundStyle(TremorColor.inkSecondary)

            field
                .frame(minHeight: TremorSize.field)
                .background {
                    RoundedRectangle(cornerRadius: TremorRadius.input, style: .continuous)
                        .fill(TremorColor.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TremorRadius.input, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
                .overlay {
                    // Zip's 4pt focus halo, drawn outside the border.
                    if isFocused {
                        RoundedRectangle(cornerRadius: TremorRadius.input + TremorSpacing.xxs,
                                         style: .continuous)
                            .strokeBorder(TremorColor.focusRing,
                                          lineWidth: TremorControlMetrics.focusRingWidth)
                            .padding(-TremorSpacing.xxs)
                    }
                }
                .overlay {
                    if !isEnabled {
                        RoundedRectangle(cornerRadius: TremorRadius.input, style: .continuous)
                            .fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
                    }
                }

            footer
        }
        .animation(TremorMotion.resolved(TremorMotion.colorShift, reduceMotion: reduceMotion),
                   value: isFocused)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: hasError)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var field: some View {
        HStack(spacing: TremorSpacing.sm) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: TremorControlMetrics.glyphMedium, weight: .regular))
                    .foregroundStyle(TremorColor.inkTertiary)
            }

            ZStack(alignment: .leading) {
                // Own placeholder, so its colour is a Tremor token rather than
                // SwiftUI's system grey.
                if text.isEmpty {
                    Text(placeholder)
                        .tremorType(.body)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .allowsHitTesting(false)
                }
                entry
            }

            if isSecure {
                Button {
                    TremorHaptic.light.play()
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: TremorControlMetrics.glyphMedium, weight: .regular))
                        .foregroundStyle(TremorColor.inkTertiary)
                        .frame(width: TremorSize.minimumTapTarget,
                               height: TremorSize.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isRevealed ? "Hide \(label)" : "Show \(label)"))
            } else if !text.isEmpty && isFocused {
                Button {
                    text = ""
                    TremorHaptic.light.play()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: TremorControlMetrics.glyphMedium))
                        .foregroundStyle(TremorColor.inkTertiary)
                        .frame(width: TremorSize.minimumTapTarget,
                               height: TremorSize.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear \(label)"))
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.vertical, TremorSpacing.xs)
    }

    @ViewBuilder
    private var entry: some View {
        Group {
            if isSecure && !isRevealed {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .tremorType(.body)
        .foregroundStyle(TremorColor.ink)
        .tint(TremorColor.primary)
        .focused($isFocused)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .textInputAutocapitalization(autocapitalization)
        .submitLabel(submitLabel)
        .onSubmit { onSubmit?() }
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(errorMessage ?? helpText ?? ""))
    }

    @ViewBuilder
    private var footer: some View {
        if let errorMessage {
            // Symbol + text, so the error is legible without colour.
            Label {
                Text(errorMessage).tremorType(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: TremorControlMetrics.glyphSmall))
            }
            .foregroundStyle(TremorColor.danger)
            .accessibilityLabel(Text("Error: \(errorMessage)"))
        } else if let helpText {
            Text(helpText)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
        }
    }
}

// MARK: - TremorStepper

/// A −/+ quantity stepper with the value between the two buttons.
///
/// ```swift
/// TremorStepper("Shelves", value: $shelves, in: 1...8)
/// ```
///
/// Lyft §6.8: 40pt circular buttons, `surface-secondary` fill, value at
/// `title-w1` between them. Hitting either bound plays a warning haptic rather
/// than silently doing nothing.
public struct TremorStepper: View {
    private let label: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let format: (Int) -> String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - label: visible leading label, also the VoiceOver label.
    ///   - value: bound integer.
    ///   - range: inclusive bounds. Defaults to `0...99`.
    ///   - step: increment. Defaults to 1.
    ///   - format: renders the value (units, "×", "None" at zero…). Defaults to
    ///     the plain number.
    public init(_ label: String,
                value: Binding<Int>,
                in range: ClosedRange<Int> = 0...99,
                step: Int = 1,
                format: @escaping (Int) -> String = { "\($0)" }) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    private var canDecrement: Bool { value - step >= range.lowerBound }
    private var canIncrement: Bool { value + step <= range.upperBound }

    public var body: some View {
        HStack(spacing: TremorSpacing.md) {
            Text(label)
                .tremorType(.bodyEmphasis)
                .foregroundStyle(TremorColor.ink)

            Spacer(minLength: TremorSpacing.md)

            HStack(spacing: TremorSpacing.md) {
                button(symbol: "minus", enabled: canDecrement, label: "Decrease \(label)") {
                    adjust(by: -step)
                }

                Text(format(value))
                    .tremorType(.title3, numeric: true)
                    .foregroundStyle(TremorColor.ink)
                    .frame(minWidth: TremorControlMetrics.stepperButtonDiameter)
                    .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                               value: value)

                button(symbol: "plus", enabled: canIncrement, label: "Increase \(label)") {
                    adjust(by: step)
                }
            }
        }
        .opacity(isEnabled ? 1 : 1 - TremorControlMetrics.disabledVeil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(format(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: step)
            case .decrement: adjust(by: -step)
            @unknown default: break
            }
        }
    }

    private func adjust(by delta: Int) {
        let next = value + delta
        guard range.contains(next) else {
            TremorHaptic.warning.play()
            return
        }
        value = next
        TremorHaptic.light.play()
    }

    @ViewBuilder
    private func button(symbol: String,
                        enabled: Bool,
                        label: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: TremorControlMetrics.glyphSmall, weight: .bold))
        }
        .buttonStyle(TremorStepperButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        .accessibilityHidden(true) // The stepper as a whole is the a11y element.
    }
}

private struct TremorStepperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration)
    }

    fileprivate struct Inner: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .foregroundStyle(isEnabled ? TremorColor.ink : TremorColor.inkTertiary)
                .frame(width: TremorControlMetrics.stepperButtonDiameter,
                       height: TremorControlMetrics.stepperButtonDiameter)
                .background {
                    ZStack {
                        Circle().fill(TremorColor.surfaceSunken)
                        if pressed {
                            Circle().fill(TremorColor.ink.opacity(TremorControlMetrics.pressTint))
                        }
                    }
                }
                .opacity(isEnabled ? 1 : 1 - TremorControlMetrics.disabledVeil)
                .scaleEffect(pressed ? TremorMotion.pressScale : 1)
                .animation(TremorMotion.resolved(pressed ? TremorMotion.tap : TremorMotion.release,
                                                reduceMotion: reduceMotion),
                           value: pressed)
                .contentShape(Circle())
        }
    }
}

// MARK: - TremorSlider

/// The intensity slider — the control the user drags to choose how hard the
/// earthquake shakes.
///
/// This is the most important control in the app, so it gets more than a
/// generic slider does:
///
/// - **A four-band gradient track.** The track runs Low → Moderate → High →
///   Severe through `TremorRiskBand.mark`, at low opacity ahead of the thumb and
///   full strength behind it, so the user can see the consequence of dragging
///   further before they commit to it.
/// - **A value bubble** above the thumb carrying the number *and the band's
///   name* — the band is never communicated by hue alone.
/// - **Haptic detents.** Every integer step fires a selection tick from a
///   prepared generator, so dragging feels like a physical notched dial. The
///   two ends fire a heavier tap.
/// - **A 44pt tap row** around a 28pt thumb (Lyft's minimum target), and the
///   whole row is draggable, not just the thumb.
///
/// ```swift
/// TremorSlider(value: $magnitude, in: 4...9, step: 0.5, label: "Magnitude")
/// ```
///
/// - Note: this is the one control in the family declared `internal` rather
///   than `public`. Its API surfaces `TremorRiskBand`, which `Theme.swift`
///   declares internal, and Swift will not let a public signature mention an
///   internal type. Tremor ships as a single module, so inside the app the two
///   access levels are indistinguishable.
struct TremorSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let label: String
    private let valueLabel: (Double) -> String
    private let band: (Double) -> TremorRiskBand
    private let minimumLabel: String?
    private let maximumLabel: String?

    @State private var ticker = UISelectionFeedbackGenerator()
    @State private var isDragging = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: bound value, snapped to `step`.
    ///   - range: inclusive bounds. Defaults to `1...10` (a shake-intensity
    ///     scale).
    ///   - step: detent size. Every landed detent fires a haptic tick.
    ///   - label: visible label above the track, also the VoiceOver label.
    ///   - minimumLabel: caption under the leading end (e.g. "Barely felt").
    ///   - maximumLabel: caption under the trailing end (e.g. "Destructive").
    ///   - valueLabel: renders the value into the bubble and the right-hand
    ///     readout. Defaults to a trimmed number.
    ///   - band: maps a value to a risk band. Defaults to even quartiles of
    ///     `range`. Pass your own to match a real intensity scale.
    init(value: Binding<Double>,
                in range: ClosedRange<Double> = 1...10,
                step: Double = 1,
                label: String = "Intensity",
                minimumLabel: String? = nil,
                maximumLabel: String? = nil,
                valueLabel: @escaping (Double) -> String = TremorSlider.defaultValueLabel,
                band: ((Double) -> TremorRiskBand)? = nil) {
        self._value = value
        self.range = range
        self.step = max(step, .leastNonzeroMagnitude)
        self.label = label
        self.minimumLabel = minimumLabel
        self.maximumLabel = maximumLabel
        self.valueLabel = valueLabel
        let bounds = range
        self.band = band ?? { TremorSlider.defaultBand(for: $0, in: bounds) }
    }

    /// Plain number, with the decimal point dropped when it is a whole value.
    static func defaultValueLabel(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    /// Even quartiles of the range, in `TremorRiskBand`'s declaration order.
    static func defaultBand(for value: Double, in range: ClosedRange<Double>) -> TremorRiskBand {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return .low }
        let t = (value - range.lowerBound) / span
        switch t {
        case ..<0.25: return .low
        case ..<0.5: return .moderate
        case ..<0.75: return .high
        default: return .severe
        }
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var currentBand: TremorRiskBand { band(value) }

    private var trackGradient: LinearGradient {
        LinearGradient(colors: TremorRiskBand.allCases.map(\.mark),
                       startPoint: .leading,
                       endPoint: .trailing)
    }

    private var rowHeight: CGFloat {
        TremorSize.minimumTapTarget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            header

            GeometryReader { geo in
                track(in: geo.size.width)
                    .frame(width: geo.size.width, height: rowHeight)
                    .contentShape(Rectangle())
                    .gesture(drag(width: geo.size.width))
            }
            .frame(height: rowHeight)

            if minimumLabel != nil || maximumLabel != nil {
                HStack {
                    Text(minimumLabel ?? "")
                    Spacer(minLength: TremorSpacing.md)
                    Text(maximumLabel ?? "")
                }
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
            }
        }
        .opacity(isEnabled ? 1 : 1 - TremorControlMetrics.disabledVeil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(valueLabel(value)), \(currentBand.title) risk"))
        .accessibilityHint(Text("Swipe up or down to change the shake intensity"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(by: step)
            case .decrement: nudge(by: -step)
            @unknown default: break
            }
        }
        .onAppear { ticker.prepare() }
    }

    // ── Pieces ──────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .tremorType(.subheadline)
                .foregroundStyle(TremorColor.inkSecondary)

            Spacer(minLength: TremorSpacing.xs)

            // Textual readout: the band's name always appears in words, so the
            // gradient is decoration rather than the sole carrier of meaning.
            Text(currentBand.title)
                .tremorType(.captionEmphasis)
                .foregroundStyle(currentBand.mark)
                .padding(.horizontal, TremorSpacing.xs)
                .padding(.vertical, TremorSpacing.hair)
                .background { Capsule().fill(currentBand.surface) }

            Text(valueLabel(value))
                .tremorType(.headline, numeric: true)
                .foregroundStyle(TremorColor.ink)
        }
    }

    @ViewBuilder
    private func track(in width: CGFloat) -> some View {
        let thumbSize = TremorControlMetrics.sliderThumbDiameter
        let usable = max(width - thumbSize, 0)
        let thumbX = thumbSize / 2 + usable * fraction

        ZStack(alignment: .leading) {
            // Recessed well.
            Capsule()
                .fill(TremorColor.surfaceSunken)
                .frame(height: TremorControlMetrics.sliderTrackHeight)

            // The whole ramp, dimmed — you can see where you are going.
            Capsule()
                .fill(trackGradient)
                .frame(height: TremorControlMetrics.sliderTrackHeight)
                .opacity(0.28)

            // The travelled portion, at full strength.
            Capsule()
                .fill(trackGradient)
                .frame(width: max(thumbX, TremorControlMetrics.sliderTrackHeight),
                       height: TremorControlMetrics.sliderTrackHeight)
                .mask(alignment: .leading) {
                    Capsule().frame(width: max(thumbX, TremorControlMetrics.sliderTrackHeight))
                }

            // Detent pips, so the notches are visible as well as felt.
            detents(usable: usable, thumbSize: thumbSize)

            // Thumb.
            Circle()
                .fill(TremorColor.surface)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Circle().strokeBorder(currentBand.mark, lineWidth: TremorSize.strokeEmphasis)
                }
                .tremorShadow(.raised)
                .scaleEffect(isDragging ? 1 / TremorMotion.pressScale : 1)
                .offset(x: thumbX - thumbSize / 2)
                .overlay(alignment: .leading) {
                    bubble
                        .offset(x: thumbX - TremorControlMetrics.sliderBubbleMinWidth / 2,
                                y: -(rowHeight / 2 + TremorSpacing.md))
                        .opacity(isDragging ? 1 : 0)
                        .allowsHitTesting(false)
                }
        }
        .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                   value: value)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: isDragging)
    }

    @ViewBuilder
    private func detents(usable: CGFloat, thumbSize: CGFloat) -> some View {
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded())
        // Only draw pips when they will not turn the track into a solid line.
        if count > 1 && count <= 12 {
            ZStack(alignment: .leading) {
                ForEach(0...count, id: \.self) { index in
                    let t = Double(index) / Double(count)
                    Circle()
                        .fill(TremorColor.ink.opacity(TremorControlMetrics.ghostPressTint * 2))
                        .frame(width: TremorSpacing.xxs, height: TremorSpacing.xxs)
                        .offset(x: thumbSize / 2 + usable * t - TremorSpacing.hair)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var bubble: some View {
        VStack(spacing: 0) {
            Text(valueLabel(value))
                .tremorType(.bodyEmphasis, numeric: true)
            Text(currentBand.title)
                .tremorType(.caption)
        }
        .foregroundStyle(currentBand.mark)
        .padding(.horizontal, TremorSpacing.sm)
        .padding(.vertical, TremorSpacing.xs)
        .frame(minWidth: TremorControlMetrics.sliderBubbleMinWidth)
        .background {
            Capsule(style: .continuous).fill(currentBand.surface)
        }
        .tremorShadow(.raised)
    }

    // ── Interaction ─────────────────────────────────────────────────────

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging { isDragging = true }
                let thumbSize = TremorControlMetrics.sliderThumbDiameter
                let usable = max(width - thumbSize, 1)
                let raw = (gesture.location.x - thumbSize / 2) / usable
                let clamped = min(max(Double(raw), 0), 1)
                let unsnapped = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                commit(snap(unsnapped))
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func nudge(by delta: Double) {
        let next = snap(value + delta)
        guard next != value else {
            TremorHaptic.warning.play()
            return
        }
        commit(next)
    }

    private func snap(_ raw: Double) -> Double {
        let steps = ((raw - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + steps * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    private func commit(_ next: Double) {
        guard next != value else { return }
        let wasBand = currentBand
        value = next
        // A tick at every detent; a heavier tap when a new risk band is entered
        // or an end of the scale is reached, so the important moments are
        // distinguishable with the phone in your pocket.
        if band(next) != wasBand || next == range.lowerBound || next == range.upperBound {
            TremorHaptic.medium.play()
            ticker.prepare()
        } else {
            ticker.selectionChanged()
            ticker.prepare()
        }
    }
}

// MARK: - TremorToggle

/// A labelled switch row.
///
/// ```swift
/// TremorToggle("Haptics during the quake", isOn: $haptics)
/// TremorToggle("Slow motion", subtitle: "Play the simulation at quarter speed", isOn: $slowMo)
/// ```
///
/// Built on SwiftUI's `Toggle` so it inherits the correct VoiceOver traits and
/// the "on/off" value for free; only the switch itself is redrawn. Track 51×31
/// with a 27pt thumb (Lyft §6.8), off state `strokeStrong`, on state `primary`.
/// The thumb's *position* carries the state, so colour is not the only channel.
public struct TremorToggle: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    @Binding private var isOn: Bool

    /// - Parameters:
    ///   - title: the row's label.
    ///   - subtitle: optional explanatory line beneath.
    ///   - systemImage: optional leading SF Symbol.
    ///   - isOn: bound state.
    public init(_ title: String,
                subtitle: String? = nil,
                systemImage: String? = nil,
                isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: TremorSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: TremorControlMetrics.glyphMedium, weight: .regular))
                        .foregroundStyle(TremorColor.primary)
                        .frame(width: TremorControlMetrics.glyphLarge)
                }
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(title)
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    if let subtitle {
                        Text(subtitle)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(TremorSwitchToggleStyle())
        .frame(minHeight: TremorSize.row)
        .accessibilityHint(Text(subtitle ?? ""))
    }
}

/// The Tremor switch. Usable on its own `Toggle` if you need a bare switch:
/// `Toggle("", isOn: $x).toggleStyle(TremorSwitchToggleStyle()).labelsHidden()`.
public struct TremorSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration)
    }

    /// Public only because `ToggleStyle.makeBody` is public and this is its
    /// return type; it is not meant to be constructed directly.
    public struct Inner: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public var body: some View {
            HStack(spacing: TremorSpacing.md) {
                configuration.label
                Spacer(minLength: TremorSpacing.xs)
                switchTrack
            }
            .contentShape(Rectangle())
            .onTapGesture {
                TremorHaptic.light.play()
                configuration.isOn.toggle()
            }
            .opacity(isEnabled ? 1 : 1 - TremorControlMetrics.disabledVeil)
        }

        private var switchTrack: some View {
            let travel = TremorControlMetrics.switchTrackWidth
                - TremorControlMetrics.switchThumbDiameter
                - TremorControlMetrics.switchThumbInset * 2

            return ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? TremorColor.primary : TremorColor.strokeStrong)
                Circle()
                    .fill(TremorColor.surface)
                    .frame(width: TremorControlMetrics.switchThumbDiameter,
                           height: TremorControlMetrics.switchThumbDiameter)
                    .tremorShadow(.hairline)
                    .padding(TremorControlMetrics.switchThumbInset)
            }
            .frame(width: TremorControlMetrics.switchTrackWidth,
                   height: TremorControlMetrics.switchTrackHeight)
            .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                       value: configuration.isOn)
            .accessibilityHidden(true) // The Toggle itself is the a11y element.
            .frame(minWidth: travel) // Keeps the layout honest if the track ever changes.
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Previews
// ─────────────────────────────────────────────────────────────────────────
//
//  These are the review surface for the control family. Each block labels
//  every case it shows, including the ugly ones — long text, disabled,
//  loading, error, both ends of a range — because that is where a component
//  actually fails.
//

/// A tiny holder so previews can be stateful without `@Previewable`, which
/// would tie this file to a newer toolchain than the project targets.
private struct PreviewState<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}

private struct PreviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text(title)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Preview fixtures

private enum PreviewViewMode: String, CaseIterable, Identifiable {
    case before, during, after
    var id: Self { self }
    var title: String {
        switch self {
        case .before: return "Before"
        case .during: return "During"
        case .after: return "After"
        }
    }
    var symbol: String {
        switch self {
        case .before: return "house"
        case .during: return "waveform.path"
        case .after: return "checkmark.seal"
        }
    }
}

private enum PreviewLongMode: String, CaseIterable, Identifiable {
    case recommended, everything
    var id: Self { self }
    var title: String {
        switch self {
        case .recommended: return "Recommended fixes"
        case .everything: return "Everything we found"
        }
    }
}

// MARK: TremorButton previews

#Preview("TremorButton — variants") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Primary") {
                TremorButton("Run the earthquake") {}
            }
            PreviewSection(title: "Secondary — lavender fill, purple label") {
                TremorButton("Scan another room", variant: .secondary) {}
            }
            PreviewSection(title: "Tertiary — text only") {
                TremorButton("Not now", variant: .tertiary) {}
            }
            PreviewSection(title: "Destructive") {
                TremorButton("Delete this scan", variant: .destructive) {}
            }
            PreviewSection(title: "Accent — the yuzu moment, once per screen") {
                TremorButton("See what you can fix", variant: .accent) {}
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

#Preview("TremorButton — sizes & icons") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Large 56 · Medium 48 · Small 36") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Large", size: .large) {}
                    TremorButton("Medium", size: .medium) {}
                    TremorButton("Small", size: .small) {}
                }
            }
            PreviewSection(title: "Leading icon") {
                TremorButton("Rescan the room", variant: .secondary, leadingIcon: "arrow.clockwise") {}
            }
            PreviewSection(title: "Trailing icon") {
                TremorButton("Continue", trailingIcon: "arrow.right") {}
            }
            PreviewSection(title: "Both icons, small, hugging") {
                HStack {
                    TremorButton("Filter",
                                variant: .secondary,
                                size: .small,
                                leadingIcon: "line.3.horizontal.decrease",
                                trailingIcon: "chevron.down",
                                fillsWidth: false) {}
                    Spacer()
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

#Preview("TremorButton — states & edge cases") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Disabled — 62% white veil, every variant") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Primary disabled") {}.disabled(true)
                    TremorButton("Secondary disabled", variant: .secondary) {}.disabled(true)
                    TremorButton("Tertiary disabled", variant: .tertiary) {}.disabled(true)
                    TremorButton("Destructive disabled", variant: .destructive) {}.disabled(true)
                    TremorButton("Accent disabled", variant: .accent) {}.disabled(true)
                }
            }
            PreviewSection(title: "Loading — width is unchanged from the resting label") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Simulating") {}
                    TremorButton("Simulating", isLoading: true) {}
                    TremorButton("Simulating", variant: .secondary, isLoading: true) {}
                }
            }
            PreviewSection(title: "Long label — wraps to two lines, pill keeps its shape") {
                TremorButton("Save this report and share it with everyone in the building") {}
            }
            PreviewSection(title: "Very long label, small size") {
                TremorButton("Show me every single object we identified in this room",
                            variant: .secondary,
                            size: .small) {}
            }
            PreviewSection(title: "Two buttons stacked — Lyft's dialog order") {
                VStack(spacing: TremorSpacing.xs) {
                    TremorButton("Delete scan", variant: .destructive, size: .medium) {}
                    TremorButton("Keep it", variant: .tertiary, size: .medium) {}
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

#Preview("TremorButton — accessibility sizes") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Default") {
                TremorButton("Run the earthquake", trailingIcon: "arrow.right") {}
            }
            PreviewSection(title: "xxxLarge") {
                TremorButton("Run the earthquake", trailingIcon: "arrow.right") {}
                    .environment(\.dynamicTypeSize, .xxxLarge)
            }
            PreviewSection(title: "accessibility5 — capped at 1.20× for display roles") {
                TremorButton("Run the earthquake", trailingIcon: "arrow.right") {}
                    .environment(\.dynamicTypeSize, .accessibility5)
            }
            PreviewSection(title: "Reduce Motion — toggle it in Settings › Accessibility › Motion; the press lands instantly") {
                TremorButton("Press me", variant: .secondary) {}
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: TremorIconButton previews

#Preview("TremorIconButton") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Surface — 48 / 44 / 36") {
                HStack(spacing: TremorSpacing.md) {
                    TremorIconButton(systemImage: "xmark", size: .large, label: "Close") {}
                    TremorIconButton(systemImage: "xmark", size: .medium, label: "Close") {}
                    TremorIconButton(systemImage: "xmark", size: .small, label: "Close") {}
                }
            }
            PreviewSection(title: "Primary · Ghost · Selected") {
                HStack(spacing: TremorSpacing.md) {
                    TremorIconButton(systemImage: "play.fill", style: .primary, label: "Play") {}
                    TremorIconButton(systemImage: "ellipsis", style: .ghost, label: "More") {}
                    TremorIconButton(systemImage: "bookmark.fill",
                                    label: "Saved",
                                    isSelected: true) {}
                }
            }
            PreviewSection(title: "Disabled") {
                HStack(spacing: TremorSpacing.md) {
                    TremorIconButton(systemImage: "arrow.uturn.backward", label: "Undo") {}
                        .disabled(true)
                    TremorIconButton(systemImage: "play.fill", style: .primary, label: "Play") {}
                        .disabled(true)
                }
            }
            PreviewSection(title: "Material — over 3D content") {
                ZStack {
                    // Stand-in for the RoomPlan viewport.
                    LinearGradient(colors: [TremorColor.riskSevereMark, TremorColor.primary],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                    .frame(height: TremorSpacing.hero * 2)
                    .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))

                    HStack(spacing: TremorSpacing.md) {
                        TremorIconButton(systemImage: "chevron.left",
                                        style: .material,
                                        size: .large,
                                        label: "Back") {}
                        TremorIconButton(systemImage: "camera.rotate",
                                        style: .material,
                                        size: .large,
                                        label: "Flip camera") {}
                        TremorIconButton(systemImage: "questionmark",
                                        style: .material,
                                        size: .large,
                                        label: "Help",
                                        hint: "Explains what the colours mean") {}
                    }
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: TremorChip previews

#Preview("TremorChip") {
    PreviewState(Set<String>(["Bookcases"])) { selected in
        ScrollView {
            VStack(spacing: TremorSpacing.xl) {
                PreviewSection(title: "Interactive — tap to toggle") {
                    HStack(spacing: TremorSpacing.xs) {
                        ForEach(["Bookcases", "TVs", "Lamps"], id: \.self) { name in
                            TremorChip(name, isSelected: selected.wrappedValue.contains(name)) {
                                if selected.wrappedValue.contains(name) {
                                    selected.wrappedValue.remove(name)
                                } else {
                                    selected.wrappedValue.insert(name)
                                }
                            }
                        }
                        Spacer()
                    }
                }
                PreviewSection(title: "Unselected · Selected — ink fill plus a checkmark") {
                    HStack(spacing: TremorSpacing.xs) {
                        TremorChip("All objects") {}
                        TremorChip("All objects", isSelected: true) {}
                        Spacer()
                    }
                }
                PreviewSection(title: "With icon and count") {
                    HStack(spacing: TremorSpacing.xs) {
                        TremorChip("Severe",
                                  systemImage: "exclamationmark.triangle.fill",
                                  count: 3) {}
                        TremorChip("Low", systemImage: "checkmark.circle.fill", count: 12) {}
                        Spacer()
                    }
                }
                PreviewSection(title: "Long label — truncates rather than wrapping") {
                    TremorChip("Everything on a shelf above shoulder height", isSelected: true) {}
                }
                PreviewSection(title: "Disabled") {
                    HStack(spacing: TremorSpacing.xs) {
                        TremorChip("Unavailable") {}.disabled(true)
                        TremorChip("Unavailable", isSelected: true) {}.disabled(true)
                        Spacer()
                    }
                }
                PreviewSection(title: "Scrolling row — 8pt gaps, Lyft filter row") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TremorSpacing.xs) {
                            ForEach(["All", "Unsafe", "Bookcases", "TVs", "Lamps", "Mirrors", "Cabinets"],
                                    id: \.self) { name in
                                TremorChip(name, isSelected: name == "Unsafe") {}
                            }
                        }
                    }
                }
            }
            .padding(.vertical, TremorSpacing.xl)
        }
        .tremorScreen()
    }
}

// MARK: TremorSegmentedControl previews

#Preview("TremorSegmentedControl") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Three segments — drag the thumb by tapping") {
                PreviewState(PreviewViewMode.before) { mode in
                    TremorSegmentedControl(selection: mode, label: "View mode") { $0.title }
                }
            }
            PreviewSection(title: "With icons") {
                PreviewState(PreviewViewMode.during) { mode in
                    TremorSegmentedControl(selection: mode,
                                          label: "View mode",
                                          icon: { $0.symbol }) { $0.title }
                }
            }
            PreviewSection(title: "Two segments, long labels — scale down, never wrap") {
                PreviewState(PreviewLongMode.recommended) { mode in
                    TremorSegmentedControl(selection: mode, label: "List mode") { $0.title }
                }
            }
            PreviewSection(title: "Explicit subset of cases") {
                PreviewState(PreviewViewMode.after) { mode in
                    TremorSegmentedControl(selection: mode,
                                          items: [.before, .after],
                                          label: "Comparison") { $0.title }
                }
            }
            PreviewSection(title: "Disabled") {
                PreviewState(PreviewViewMode.before) { mode in
                    TremorSegmentedControl(selection: mode, label: "View mode") { $0.title }
                        .disabled(true)
                }
            }
            PreviewSection(title: "Reduce Motion — toggle it in Settings; the thumb jumps instead of sliding") {
                PreviewState(PreviewViewMode.before) { mode in
                    TremorSegmentedControl(selection: mode, label: "View mode") { $0.title }
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: TremorTextField previews

#Preview("TremorTextField") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Empty with placeholder") {
                PreviewState("") { text in
                    TremorTextField("Room name", text: text, placeholder: "Living room")
                }
            }
            PreviewSection(title: "Filled — tap to see the focus ring") {
                PreviewState("Living room") { text in
                    TremorTextField("Room name", text: text, placeholder: "Living room")
                }
            }
            PreviewSection(title: "With help text and a leading icon") {
                PreviewState("") { text in
                    TremorTextField("Search objects",
                                   text: text,
                                   placeholder: "Bookcase, TV, lamp…",
                                   helpText: "We'll match anything we found in the scan.",
                                   leadingIcon: "magnifyingglass")
                }
            }
            PreviewSection(title: "Error state — colour plus symbol plus message") {
                PreviewState("!!") { text in
                    TremorTextField("Room name",
                                   text: text,
                                   placeholder: "Living room",
                                   errorMessage: "Use letters and numbers only.")
                }
            }
            PreviewSection(title: "Secure — reveal toggle in the trailing well") {
                PreviewState("hunter2") { text in
                    TremorTextField("Share passcode",
                                   text: text,
                                   placeholder: "6 digits",
                                   isSecure: true,
                                   helpText: "Anyone with this code can open your report.")
                }
            }
            PreviewSection(title: "Secure with an error") {
                PreviewState("123") { text in
                    TremorTextField("Share passcode",
                                   text: text,
                                   isSecure: true,
                                   errorMessage: "That passcode is too short.")
                }
            }
            PreviewSection(title: "Long value — scrolls inside the field") {
                PreviewState("The upstairs bedroom with the tall bookcase by the window") { text in
                    TremorTextField("Room name", text: text)
                }
            }
            PreviewSection(title: "Disabled") {
                PreviewState("Living room") { text in
                    TremorTextField("Room name", text: text).disabled(true)
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: TremorStepper previews

#Preview("TremorStepper") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            PreviewSection(title: "Default") {
                PreviewState(3) { value in
                    TremorStepper("Shelves", value: value, in: 1...8)
                }
            }
            PreviewSection(title: "At the lower bound — minus is disabled") {
                PreviewState(1) { value in
                    TremorStepper("Shelves", value: value, in: 1...8)
                }
            }
            PreviewSection(title: "At the upper bound — plus is disabled") {
                PreviewState(8) { value in
                    TremorStepper("Shelves", value: value, in: 1...8)
                }
            }
            PreviewSection(title: "Custom format and step") {
                PreviewState(30) { value in
                    TremorStepper("Shake length", value: value, in: 10...120, step: 10) { "\($0)s" }
                }
            }
            PreviewSection(title: "Long label") {
                PreviewState(2) { value in
                    TremorStepper("People sleeping in this room", value: value, in: 0...6)
                }
            }
            PreviewSection(title: "Disabled") {
                PreviewState(3) { value in
                    TremorStepper("Shelves", value: value, in: 1...8).disabled(true)
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: TremorSlider previews

#Preview("TremorSlider — intensity") {
    ScrollView {
        VStack(spacing: TremorSpacing.xxl) {
            PreviewSection(title: "Default 1–10, whole steps — drag it") {
                PreviewState(3.0) { value in
                    TremorSlider(value: value,
                                minimumLabel: "Barely felt",
                                maximumLabel: "Destructive")
                }
            }
            PreviewSection(title: "Lower bound") {
                PreviewState(1.0) { value in
                    TremorSlider(value: value, minimumLabel: "Barely felt", maximumLabel: "Destructive")
                }
            }
            PreviewSection(title: "Upper bound — Severe") {
                PreviewState(10.0) { value in
                    TremorSlider(value: value, minimumLabel: "Barely felt", maximumLabel: "Destructive")
                }
            }
            PreviewSection(title: "Magnitude 4.0–9.0 in half steps") {
                PreviewState(6.5) { value in
                    TremorSlider(value: value,
                                in: 4...9,
                                step: 0.5,
                                label: "Magnitude",
                                minimumLabel: "M4.0",
                                maximumLabel: "M9.0")
                }
            }
            PreviewSection(title: "Many detents — pips are dropped above 12 steps") {
                PreviewState(40.0) { value in
                    TremorSlider(value: value,
                                in: 0...100,
                                step: 5,
                                label: "Ground acceleration",
                                minimumLabel: "0 %g",
                                maximumLabel: "100 %g") { "\(Int($0)) %g" }
                }
            }
            PreviewSection(title: "No end captions") {
                PreviewState(5.0) { value in
                    TremorSlider(value: value)
                }
            }
            PreviewSection(title: "Disabled") {
                PreviewState(7.0) { value in
                    TremorSlider(value: value,
                                minimumLabel: "Barely felt",
                                maximumLabel: "Destructive")
                    .disabled(true)
                }
            }
            PreviewSection(title: "Reduce Motion — toggle it in Settings; the thumb tracks without easing") {
                PreviewState(4.0) { value in
                    TremorSlider(value: value)
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

#Preview("TremorSlider — every band") {
    VStack(alignment: .leading, spacing: TremorSpacing.xl) {
        ForEach(Array(TremorRiskBand.allCases.enumerated()), id: \.element) { index, band in
            PreviewSection(title: band.title) {
                PreviewState(Double(index) * 3 + 1) { value in
                    TremorSlider(value: value, label: "Intensity")
                }
            }
        }
    }
    .padding(.vertical, TremorSpacing.xl)
    .tremorScreen()
}

// MARK: TremorToggle previews

#Preview("TremorToggle") {
    ScrollView {
        VStack(spacing: TremorSpacing.md) {
            PreviewSection(title: "Off · On") {
                VStack(spacing: 0) {
                    PreviewState(false) { on in
                        TremorToggle("Haptics during the quake", isOn: on)
                    }
                    Divider().background(TremorColor.divider)
                    PreviewState(true) { on in
                        TremorToggle("Haptics during the quake", isOn: on)
                    }
                }
            }
            PreviewSection(title: "With subtitle") {
                PreviewState(true) { on in
                    TremorToggle("Slow motion",
                                subtitle: "Play the simulation at quarter speed so you can see what moves first.",
                                isOn: on)
                }
            }
            PreviewSection(title: "With leading icon") {
                PreviewState(true) { on in
                    TremorToggle("Sound", systemImage: "speaker.wave.2.fill", isOn: on)
                }
            }
            PreviewSection(title: "Long title, no subtitle") {
                PreviewState(false) { on in
                    TremorToggle("Include objects we are not confident about in the safety report",
                                isOn: on)
                }
            }
            PreviewSection(title: "Disabled off · disabled on") {
                VStack(spacing: 0) {
                    PreviewState(false) { on in
                        TremorToggle("Needs a LiDAR scan first", isOn: on).disabled(true)
                    }
                    PreviewState(true) { on in
                        TremorToggle("Needs a LiDAR scan first", isOn: on).disabled(true)
                    }
                }
            }
            PreviewSection(title: "Reduce Motion — toggle it in Settings; the switch snaps") {
                PreviewState(false) { on in
                    TremorToggle("Haptics during the quake", isOn: on)
                }
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// MARK: Everything together

#Preview("Control gallery — one screen") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            Text("Shake it")
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)

            PreviewState(6.0) { value in
                TremorSlider(value: value,
                            label: "Intensity",
                            minimumLabel: "Barely felt",
                            maximumLabel: "Destructive")
            }

            PreviewState(PreviewViewMode.during) { mode in
                TremorSegmentedControl(selection: mode, label: "View mode", icon: { $0.symbol }) {
                    $0.title
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TremorSpacing.xs) {
                    TremorChip("All", isSelected: true) {}
                    TremorChip("Unsafe", systemImage: "exclamationmark.triangle.fill", count: 4) {}
                    TremorChip("Bookcases") {}
                    TremorChip("TVs") {}
                }
            }

            PreviewState(true) { on in
                TremorToggle("Haptics during the quake", isOn: on)
            }

            PreviewState(3) { count in
                TremorStepper("Shelves", value: count, in: 1...8)
            }

            VStack(spacing: TremorSpacing.xs) {
                TremorButton("Run the earthquake", trailingIcon: "waveform.path") {}
                TremorButton("Scan another room", variant: .tertiary, size: .medium) {}
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}
