//
//  Typography.swift
//  Tremor — Design System / Type
//
//  TWO FACES, SPLIT OPTICALLY — this is the whole idea.
//
//  Lyft's Rebel Sans ships as two opticals with deliberately opposite
//  proportions: Text is *wide* (H advance 0.788 em) and Display is *narrow*
//  (0.667 em), with a much tighter vertical box on Display so headlines can run
//  at ~1.02 line-height without collision. Zip does the same trick with Sharp
//  Grotesk's width axis — 20 for UI, the wider 25 for display. Neither brand
//  uses one face at every size.
//
//  Tremor reproduces that split with the two bundled OFL faces the research
//  names as the best free substitutes:
//
//      • Instrument Sans  → display sizes (≥20pt). Narrow, flat-sided grotesk;
//        the research's #1 substitute for Rebel Sans Display.
//      • Inter            → text sizes (≤17pt). Closest x-height (0.546 em) and
//        a near-identical humanist-grotesque skeleton to Rebel Sans Text.
//
//  TRACKING CORRECTIONS (both taken verbatim from the research):
//
//      • Instrument Sans needs `letter-spacing: −0.015em` at ≥28pt
//        (design-lyft.md §2.2). Applied, tapering to −0.010em at 24pt and to 0
//        at 20pt where the face is no longer running "display large".
//      • Inter is narrower than Rebel Sans Text, so body sizes want
//        `+0.008em` (design-lyft.md §2.2). Zip independently arrives at the
//        same place from the other direction: it tracks small text *positively*
//        (+0.3 to +0.5pt at 10–15pt) and display text to *zero*
//        (design-zip.md §3.3). The two agree, so Tremor tracks out below 17pt
//        and tracks in above 20pt.
//
//  SIZE RAMP — where each step comes from:
//
//      displayXL  48  Lyft `display-w1` (48/49)
//      displayL   40  Zip `--native-title-1` (40/46)
//      displayM   32  Zip `--native-title-2` (32/40)
//      title1     28  Lyft `headline-w1` (28/37) = Zip `--native-title-3`
//      title2     24  Lyft `headline-w2` (24/30)
//      title3     20  Lyft `headline-w3` (20/26) = Zip `--native-heading-1`
//      headline   17  Lyft `title-w1` (17/24), weight 500→SemiBold
//      body       17  Lyft `body-w1` / `subtitle-w1` (17/24)
//      bodyEmph   17  Lyft `title-w1` at Medium — same size, weight is the
//                     hierarchy. This is Lyft's central typographic discipline.
//      callout    15  Lyft `subtitle-w2` (15/21)
//      subheadline 15 Lyft `title-w2` (15/21), weight 500
//      footnote   13  Lyft `subtitle-w3` / `body-w3` (13/18)
//      caption    11  Zip `--native-body-3` (11/16)
//      captionEmph 11 same size, Medium
//      overline   10  Zip `--native-caption` (10/16), set all-caps and tracked
//                     to +0.12em — the small letterspaced label Zip puts above
//                     section headers.
//
//  Only three "workhorse" sizes exist — 17 / 15 / 13 — exactly as Lyft's ramp
//  does. Everything above is display; everything below is fine print.
//
//  USAGE — `.tremorType(_:)` IS THE ONLY SANCTIONED WAY TO SET TYPE.
//  SwiftUI does not derive line height or tracking from a `Font`, so calling
//  `.font(...)` directly silently drops two thirds of the spec. Always:
//
//      Text("Bookcase").tremorType(.title2)
//      Text("8.4").tremorType(.displayL, numeric: true)
//

import SwiftUI
import UIKit

// MARK: - Faces

/// The seven PostScript names bundled and registered in `project.yml`
/// under `UIAppFonts`. These strings must match exactly — a typo falls back to
/// the system font silently and destroys the design.
enum TremorFontFace: String, CaseIterable, Sendable {
    // Instrument Sans — display
    case displayMedium = "InstrumentSans-Medium"
    case displaySemibold = "InstrumentSans-SemiBold"
    case displayBold = "InstrumentSans-Bold"
    // Inter — text
    case textRegular = "Inter-Regular"
    case textMedium = "Inter-Medium"
    case textSemibold = "Inter-SemiBold"
    case textBold = "Inter-Bold"

    var postScriptName: String { rawValue }
}

// MARK: - Spec

/// A full type spec: face, size, line height, tracking, casing and Dynamic Type
/// cap. SwiftUI needs all of these applied separately, which is exactly why
/// `.tremorType(_:)` exists.
struct TremorTypeSpec: Sendable {
    let face: TremorFontFace
    /// Base point size at Dynamic Type `.large` (the default).
    let size: CGFloat
    /// Total line box in points at the base size (CSS `line-height`, not leading).
    let lineHeight: CGFloat
    /// Letter spacing in points at the base size. Positive = looser.
    let tracking: CGFloat
    /// Whether the style renders all-caps (`overline` only).
    let uppercase: Bool
    /// Dynamic Type text style this scales against.
    let metricsStyle: UIFont.TextStyle
    /// Hard ceiling on growth, as a multiple of `size`. See `scaledSize(for:)`.
    let maxScale: CGFloat

    /// The Dynamic Type size cap, and why it exists.
    ///
    /// Tremor is a portrait-only app whose primary screens are a 3D viewport with
    /// a bottom sheet over it, plus a scored risk list. Both have hard vertical
    /// budgets: the sheet's detents are fractions of screen height, and a risk
    /// row must fit a mark, a title, a subtitle and a trailing score on one line
    /// pair. Uncapped Dynamic Type at `.accessibility5` scales a 17pt body to
    /// ~53pt (3.1×) and a 48pt display to ~106pt, which breaks both.
    ///
    /// So growth is capped, and the caps differ by role:
    ///
    ///   • **Text styles (≤17pt) cap at 1.45×.** A 17pt body reaches 24.7pt and
    ///     a 13pt footnote reaches 18.9pt — still a large, comfortable read, and
    ///     the point where a two-line risk row stops fitting its 88pt height.
    ///     Text roles are where accessibility actually matters, so they get the
    ///     larger cap.
    ///   • **Display styles (≥20pt) cap at 1.20×.** Display type is already
    ///     28–48pt; it is legible at accessibility sizes without growing, and
    ///     growing it is what actually overflows headlines onto four lines and
    ///     pushes the sheet's CTA off-screen. 48pt → 57.6pt max.
    ///
    /// Below the cap, scaling is fully proportional to the user's setting, so
    /// most users (xSmall … xxxLarge, which never exceeds ~1.35× for body text)
    /// are unaffected by the cap at all — it only engages in the five
    /// accessibility sizes.
    static let textCap: CGFloat = 1.45
    static let displayCap: CGFloat = 1.20

    /// Point size after Dynamic Type scaling, clamped by `maxScale`.
    func scaledSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        let scaled = UIFontMetrics(forTextStyle: metricsStyle).scaledValue(for: size, compatibleWith: traits)
        return min(scaled, size * maxScale)
    }

    /// Line height after Dynamic Type scaling. Scales with the type so the
    /// leading ratio is preserved rather than the absolute leading.
    func scaledLineHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        lineHeight * (scaledSize(for: dynamicTypeSize) / size)
    }

    /// Tracking after Dynamic Type scaling. Tracking is specified in points at
    /// the base size but is conceptually an em value, so it scales too.
    func scaledTracking(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        tracking * (scaledSize(for: dynamicTypeSize) / size)
    }

    /// The SwiftUI font for this spec at a given Dynamic Type size.
    ///
    /// Uses `fixedSize:` because the scaling and the cap are applied here, not
    /// by SwiftUI — passing `relativeTo:` as well would double-scale.
    func font(for dynamicTypeSize: DynamicTypeSize, numeric: Bool = false) -> Font {
        let font = Font.custom(face.postScriptName, fixedSize: scaledSize(for: dynamicTypeSize))
        return numeric ? font.monospacedDigit() : font
    }
}

// MARK: - The ramp

/// The Tremor type ramp. Declaration order is descending size and is asserted by
/// `DesignSystemTests.testTypeRampIsMonotonicInSize`.
enum TremorType: String, CaseIterable, Sendable {
    case displayXL
    case displayL
    case displayM
    case title1
    case title2
    case title3
    case headline
    case body
    case bodyEmphasis
    case callout
    case subheadline
    case footnote
    case caption
    case captionEmphasis
    case overline

    var spec: TremorTypeSpec {
        switch self {

        // ── Display: Instrument Sans, negative tracking ──────────────────
        // Lyft display-w1 48/49. Instrument Sans wants −0.015em ⇒ −0.72pt.
        case .displayXL:
            return TremorTypeSpec(face: .displayBold, size: 48, lineHeight: 52, tracking: -0.72,
                                 uppercase: false, metricsStyle: .largeTitle, maxScale: TremorTypeSpec.displayCap)

        // Zip --native-title-1 40/46. −0.015em ⇒ −0.60pt.
        case .displayL:
            return TremorTypeSpec(face: .displayBold, size: 40, lineHeight: 46, tracking: -0.60,
                                 uppercase: false, metricsStyle: .largeTitle, maxScale: TremorTypeSpec.displayCap)

        // Zip --native-title-2 32/40. −0.015em ⇒ −0.48pt.
        case .displayM:
            return TremorTypeSpec(face: .displaySemibold, size: 32, lineHeight: 40, tracking: -0.48,
                                 uppercase: false, metricsStyle: .title1, maxScale: TremorTypeSpec.displayCap)

        // Lyft headline-w1 28/37 (Zip --native-title-3 28/36). −0.015em ⇒ −0.42pt.
        case .title1:
            return TremorTypeSpec(face: .displaySemibold, size: 28, lineHeight: 36, tracking: -0.42,
                                 uppercase: false, metricsStyle: .title1, maxScale: TremorTypeSpec.displayCap)

        // Lyft headline-w2 24/30. Below the −0.015em threshold; taper to −0.010em.
        case .title2:
            return TremorTypeSpec(face: .displaySemibold, size: 24, lineHeight: 30, tracking: -0.24,
                                 uppercase: false, metricsStyle: .title2, maxScale: TremorTypeSpec.displayCap)

        // Lyft headline-w3 20/26 (Zip --native-heading-1 20/28). Zip tracks this
        // +0.3pt; Instrument Sans is narrow enough that 0 is the right landing.
        case .title3:
            return TremorTypeSpec(face: .displayMedium, size: 20, lineHeight: 26, tracking: 0,
                                 uppercase: false, metricsStyle: .title3, maxScale: TremorTypeSpec.displayCap)

        // ── Text: Inter, positive tracking ───────────────────────────────
        // Lyft title-w1 17/24 weight 500. Inter +0.008em ⇒ +0.14pt.
        case .headline:
            return TremorTypeSpec(face: .textSemibold, size: 17, lineHeight: 24, tracking: 0.14,
                                 uppercase: false, metricsStyle: .headline, maxScale: TremorTypeSpec.textCap)

        // Lyft body-w1 / subtitle-w1 17/24 weight 400.
        case .body:
            return TremorTypeSpec(face: .textRegular, size: 17, lineHeight: 24, tracking: 0.14,
                                 uppercase: false, metricsStyle: .body, maxScale: TremorTypeSpec.textCap)

        // Lyft title-w1 at weight 500 — same size as body, weight is the
        // hierarchy. Copying this is what keeps Tremor's lists calm.
        case .bodyEmphasis:
            return TremorTypeSpec(face: .textMedium, size: 17, lineHeight: 24, tracking: 0.14,
                                 uppercase: false, metricsStyle: .body, maxScale: TremorTypeSpec.textCap)

        // Lyft subtitle-w2 / body-w2 15/21 weight 400. Inter +0.008em ⇒ +0.12pt.
        case .callout:
            return TremorTypeSpec(face: .textRegular, size: 15, lineHeight: 21, tracking: 0.12,
                                 uppercase: false, metricsStyle: .callout, maxScale: TremorTypeSpec.textCap)

        // Lyft title-w2 / label-w1-heavy 15/21 weight 500.
        case .subheadline:
            return TremorTypeSpec(face: .textMedium, size: 15, lineHeight: 21, tracking: 0.12,
                                 uppercase: false, metricsStyle: .subheadline, maxScale: TremorTypeSpec.textCap)

        // Lyft subtitle-w3 / body-w3 13/18. Zip tracks 13–15pt at +0.4/+0.5pt;
        // Inter at 13pt takes +0.30pt cleanly.
        case .footnote:
            return TremorTypeSpec(face: .textRegular, size: 13, lineHeight: 18, tracking: 0.30,
                                 uppercase: false, metricsStyle: .footnote, maxScale: TremorTypeSpec.textCap)

        // Zip --native-body-3 11/16, tracked +0.4pt per Zip's small-text rule.
        case .caption:
            return TremorTypeSpec(face: .textRegular, size: 11, lineHeight: 16, tracking: 0.40,
                                 uppercase: false, metricsStyle: .caption1, maxScale: TremorTypeSpec.textCap)

        case .captionEmphasis:
            return TremorTypeSpec(face: .textMedium, size: 11, lineHeight: 16, tracking: 0.40,
                                 uppercase: false, metricsStyle: .caption1, maxScale: TremorTypeSpec.textCap)

        // Zip --native-caption 10/16, set all-caps at +0.12em (1.20pt) — the
        // letterspaced micro-label Zip sets above section headers.
        case .overline:
            return TremorTypeSpec(face: .textSemibold, size: 10, lineHeight: 14, tracking: 1.20,
                                 uppercase: true, metricsStyle: .caption2, maxScale: TremorTypeSpec.textCap)
        }
    }
}

// MARK: - TremorFont

/// `SwiftUI.Font` values for the ramp.
///
/// These are provided for the rare case where a `Font` is genuinely required by
/// an API that takes one (e.g. `UIFont`-bridging, `Label` styles). They carry
/// **only** the face and size — no line height, no tracking, no casing. For
/// anything you render yourself, use `.tremorType(_:)`.
enum TremorFont {

    /// Font for a ramp step at the current Dynamic Type size.
    static func font(_ style: TremorType,
                     dynamicTypeSize: DynamicTypeSize = .large,
                     numeric: Bool = false) -> Font {
        style.spec.font(for: dynamicTypeSize, numeric: numeric)
    }

    /// Tabular-figure variant, for score readouts and any column of numbers
    /// that must not jitter as digits change.
    static func numeric(_ style: TremorType, dynamicTypeSize: DynamicTypeSize = .large) -> Font {
        style.spec.font(for: dynamicTypeSize, numeric: true)
    }

    static var displayXL: Font { font(.displayXL) }
    static var displayL: Font { font(.displayL) }
    static var displayM: Font { font(.displayM) }
    static var title1: Font { font(.title1) }
    static var title2: Font { font(.title2) }
    static var title3: Font { font(.title3) }
    static var headline: Font { font(.headline) }
    static var body: Font { font(.body) }
    static var bodyEmphasis: Font { font(.bodyEmphasis) }
    static var callout: Font { font(.callout) }
    static var subheadline: Font { font(.subheadline) }
    static var footnote: Font { font(.footnote) }
    static var caption: Font { font(.caption) }
    static var captionEmphasis: Font { font(.captionEmphasis) }
    static var overline: Font { font(.overline) }
}

// MARK: - The modifier

private struct TremorTypeModifier: ViewModifier {
    let style: TremorType
    let numeric: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let spec = style.spec
        let size = spec.scaledSize(for: dynamicTypeSize)
        // SwiftUI's `.lineSpacing` is *extra leading between lines*, not the
        // line box, so the CSS-style line height has to be converted by
        // subtracting the font's own natural line height.
        let naturalLineHeight = UIFont(name: spec.face.postScriptName, size: size)?.lineHeight ?? size * 1.2
        let extraLeading = max(0, spec.scaledLineHeight(for: dynamicTypeSize) - naturalLineHeight)

        return content
            .font(spec.font(for: dynamicTypeSize, numeric: numeric))
            .tracking(spec.scaledTracking(for: dynamicTypeSize))
            .lineSpacing(extraLeading)
            .textCase(spec.uppercase ? .uppercase : nil)
    }
}

extension View {
    /// Apply a Tremor type style: face, size, **line height**, **tracking** and
    /// casing, all at once, with Dynamic Type scaling and its cap already
    /// applied.
    ///
    /// This is the only sanctioned way to set type in Tremor. Do not call
    /// `.font(...)` directly — SwiftUI will not derive line height or tracking
    /// from a `Font`, and the result will silently be off-spec.
    ///
    /// - Parameters:
    ///   - style: the ramp step.
    ///   - numeric: enable tabular figures. Use for score readouts, currency,
    ///     countdowns and any column of numbers that must not jitter.
    func tremorType(_ style: TremorType, numeric: Bool = false) -> some View {
        modifier(TremorTypeModifier(style: style, numeric: numeric))
    }
}

// MARK: - Dynamic Type bridging

extension DynamicTypeSize {
    /// UIKit equivalent, so `UIFontMetrics` can do the scaling maths.
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
