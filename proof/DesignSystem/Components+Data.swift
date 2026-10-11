//
//  Components+Data.swift
//  Tremor — Design System / Data display
//
//  The components that carry the app's actual meaning: the risk badge, the score
//  dial, the distribution bar, the factor breakdown, the intensity scale, the
//  stat tile, the object thumbnail and the playback scrubber.
//
//  RULES OBSERVED THROUGHOUT
//
//  • Tokens only. No literal hex, no literal font size, no literal spacing —
//    everything comes from `TremorColor`, `TremorType`, `TremorSpacing`,
//    `TremorRadius`, `TremorSize`, `TremorShadow`, `TremorMotion`. The few bare
//    numbers that remain are *ratios* (arc sweep, bar fractions, symbol optical
//    size) rather than design values.
//  • Colour is never the only carrier. Every band shows its SF Symbol and its
//    name; every meter shows its number.
//  • Data in, actions out. Nothing here touches the model, the network or a
//    singleton — the only outbound edges are the closures a caller passes in.
//  • `accessibilityReduceMotion` degrades every animation to instant.
//

import SwiftUI
import UIKit

// MARK: - Model → design-system bridging
//
// `RiskBand` (Core/Risk) is the model's band; `TremorRiskBand` (Theme) is the
// design system's colour ramp. They are deliberately separate types — the model
// must not import a palette — so this file bridges them.
//
// Declared `private` on purpose: sibling component files are being written
// concurrently and may bridge the same two types themselves. File scope makes
// that impossible to collide on.

private extension RiskBand {
    var tremorBand: TremorRiskBand {
        switch self {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .severe: return .severe
        }
    }

    /// Saturated colour: numerals, icons, bar fills, rules.
    var markColor: Color { tremorBand.mark }

    /// Soft tinted fill: chips, thumbnails, card washes.
    var surfaceColor: Color { tremorBand.surface }
}

// MARK: - Private helpers

/// Haptics. Private so a sibling file declaring its own feedback helper cannot
/// clash with this one.
private enum DataHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                       intensity: CGFloat = 1.0) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

/// The house press treatment: Lyft's 0.97 scale on the `change` curve, with a
/// touch of opacity so the press reads on tinted fills too.
///
/// The body is a nested `View` rather than inline modifiers because
/// `@Environment` is not populated inside a `ButtonStyle` itself — only inside a
/// real view in the hierarchy.
private struct DataPressStyle: ButtonStyle {
    var scale: CGFloat = TremorMotion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, scale: scale)
    }

    struct PressBody: View {
        let configuration: DataPressStyle.Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? scale : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : (configuration.isPressed ? TremorMotion.tap : TremorMotion.release),
                    value: configuration.isPressed
                )
        }
    }
}

/// A `Text` whose numeric value interpolates when its driver is animated.
/// SwiftUI will not tween a string, so the count-up in `RiskScoreDial` needs an
/// `Animatable` view rather than a plain `Text`.
private struct DataAnimatableNumber: View, Animatable {
    var value: Double
    var style: TremorType

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(Int(value.rounded())))
            .tremorType(style, numeric: true)
    }
}

/// PGA formatting. Intensity III is 0.005 g and intensity X is 1.57 g, so a
/// fixed decimal count is wrong at one end or the other.
private func dataFormatPGA(_ g: Double) -> String {
    g >= 0.1 ? String(format: "%.2f g", g) : String(format: "%.3f g", g)
}

/// Elapsed-time formatting for the scrubber: `0:12.4`.
private func dataFormatTime(_ seconds: Double) -> String {
    let clamped = max(0, seconds)
    let minutes = Int(clamped) / 60
    let remainder = clamped - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, remainder)
}

/// Labelled block used only by the `#Preview` blocks below.
private struct DataPreviewSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text(title)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RiskBadge
// ─────────────────────────────────────────────────────────────────────────────

/// Size variants for `RiskBadge`.
public enum RiskBadgeSize: Sendable {
    /// For list rows and dense metadata lines.
    case small
    /// For detail headers and sheet titles.
    case large
}

/// A pill stating a `RiskBand`.
///
/// Meaning is carried three ways — the band's SF Symbol, the band's name, and
/// the mark-on-surface colour pair — so the badge survives colour-vision
/// deficiency, greyscale and a half-second glance.
///
///     RiskBadge(.severe)
///     RiskBadge(.moderate, size: .large)
public struct RiskBadge: View {

    private let band: RiskBand
    private let size: RiskBadgeSize
    private let showsSymbol: Bool
    private let showsAction: Bool

    /// - Parameters:
    ///   - band: the band to state.
    ///   - size: `.small` for rows, `.large` for headers. Defaults to `.small`.
    ///   - showsSymbol: include the band's SF Symbol. Defaults to `true`; only
    ///     turn it off where the same symbol already appears alongside.
    ///   - showsAction: append the band's call to action ("Anchor this") after
    ///     the name. Only sensible at `.large`. Defaults to `false`.
    public init(_ band: RiskBand,
                size: RiskBadgeSize = .small,
                showsSymbol: Bool = true,
                showsAction: Bool = false) {
        self.band = band
        self.size = size
        self.showsSymbol = showsSymbol
        self.showsAction = showsAction
    }

    private var typeStyle: TremorType {
        size == .small ? .captionEmphasis : .subheadline
    }

    private var horizontalPadding: CGFloat {
        size == .small ? TremorSpacing.xs : TremorSpacing.sm
    }

    private var verticalPadding: CGFloat {
        size == .small ? TremorSpacing.xxs : TremorSpacing.xs
    }

    private var iconGap: CGFloat {
        size == .small ? TremorSpacing.xxs : TremorSpacing.xs
    }

    private var label: String {
        showsAction ? "\(band.displayName) · \(band.action)" : band.displayName
    }

    public var body: some View {
        HStack(spacing: iconGap) {
            if showsSymbol {
                Image(systemName: band.symbolName)
                    .font(TremorFont.font(typeStyle))
                    .imageScale(.small)
            }
            Text(label)
                .tremorType(typeStyle)
                .lineLimit(1)
        }
        .foregroundStyle(band.markColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(Capsule(style: .continuous).fill(band.surfaceColor))
        .overlay(
            // A hairline of the mark colour keeps the pill legible when it sits
            // on a card already tinted with the same band surface.
            Capsule(style: .continuous)
                .strokeBorder(band.markColor.opacity(0.14), lineWidth: TremorSize.hairline)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Risk")
        .accessibilityValue(showsAction ? "\(band.displayName). \(band.action)" : band.displayName)
    }
}

#Preview("RiskBadge") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            DataPreviewSection("Small — list rows") {
                HStack(spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { RiskBadge($0) }
                }
            }

            DataPreviewSection("Large — detail headers") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { RiskBadge($0, size: .large) }
                }
            }

            DataPreviewSection("Large with action — long text") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { RiskBadge($0, size: .large, showsAction: true) }
                }
            }

            DataPreviewSection("No symbol") {
                RiskBadge(.high, showsSymbol: false)
            }

            DataPreviewSection("On a matching band surface") {
                HStack(spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { RiskBadge($0) }
                }
                .padding(TremorSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                        .fill(RiskBand.severe.surfaceColor)
                )
            }

            DataPreviewSection("Greyscale — meaning must survive") {
                HStack(spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { RiskBadge($0) }
                }
                .grayscale(1)
            }

            DataPreviewSection("Accessibility text size") {
                HStack(spacing: TremorSpacing.xs) {
                    RiskBadge(.severe)
                    RiskBadge(.low, size: .large)
                }
                .environment(\.dynamicTypeSize, .accessibility3)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RiskScoreDial
// ─────────────────────────────────────────────────────────────────────────────

/// The hero readout for a room's overall score.
///
/// A 280° arc, 0–100, filled to the score and coloured by band, with the number
/// set in tabular figures and the band named underneath. Arc and numeral animate
/// together on appear with the standard reveal curve.
///
/// This is the screenshot the user sends to their partner, so it is deliberately
/// the least decorated component in the file: one arc, one number, one word.
///
///     RiskScoreDial(score: 72)
///     RiskScoreDial(assessment)
public struct RiskScoreDial: View {

    /// Fraction of a full turn the gauge sweeps: 280° of 360°, leaving an 80°
    /// notch at the bottom so the ends read as a gauge rather than a ring.
    private static let sweep: Double = 280.0 / 360.0
    /// Start angle in degrees from 3 o'clock. 130° + 280° = 410°, so the arc is
    /// symmetric about the top.
    private static let startAngle: Double = 130
    /// Default outer diameter. A component dimension, in the spirit of
    /// `TremorSize`, rather than a spacing value. Public so it can serve as the
    /// default argument of the public initialisers.
    public static let defaultDiameter: CGFloat = 220

    private let score: Double
    private let band: RiskBand
    private let caption: String?
    private let diameter: CGFloat
    private let animatesOnAppear: Bool

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - score: 0…100. Values outside the range are clamped.
    ///   - band: the band to colour and name. Defaults to the band the score
    ///     itself falls in, which is almost always what you want.
    ///   - caption: the line under the band name. Defaults to `"out of 100"`;
    ///     pass `nil` to remove it, or your own string.
    ///   - diameter: outer diameter of the dial.
    ///   - animatesOnAppear: run the reveal. Defaults to `true`.
    public init(score: Double,
                band: RiskBand? = nil,
                caption: String? = "out of 100",
                diameter: CGFloat = RiskScoreDial.defaultDiameter,
                animatesOnAppear: Bool = true) {
        let clamped = min(max(score, 0), 100)
        self.score = clamped
        self.band = band ?? RiskBand(score: clamped)
        self.caption = caption
        self.diameter = diameter
        self.animatesOnAppear = animatesOnAppear
    }

    /// The room's headline score and band, straight from an assessment.
    public init(_ assessment: RoomAssessment,
                caption: String? = "out of 100",
                diameter: CGFloat = RiskScoreDial.defaultDiameter,
                animatesOnAppear: Bool = true) {
        self.init(score: assessment.overallScore,
                  band: assessment.overallBand,
                  caption: caption,
                  diameter: diameter,
                  animatesOnAppear: animatesOnAppear)
    }

    private var lineWidth: CGFloat { diameter * 0.082 }

    private var accessibilityValueText: String {
        "\(Int(score.rounded())) out of 100. \(band.displayName) risk. \(band.action)."
    }

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(Self.sweep))
                .stroke(TremorColor.surfaceSunken,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(Self.startAngle))

            Circle()
                .trim(from: 0, to: CGFloat(Self.sweep * (score / 100) * progress))
                .stroke(band.markColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(Self.startAngle))

            VStack(spacing: TremorSpacing.hair) {
                DataAnimatableNumber(value: score * progress, style: .displayXL)
                    .foregroundStyle(TremorColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                HStack(spacing: TremorSpacing.xxs) {
                    Image(systemName: band.symbolName)
                        .font(TremorFont.title3)
                    Text(band.displayName)
                        .tremorType(.title3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(band.markColor)

                if let caption {
                    Text(caption)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, TremorSpacing.hair)
                }
            }
            .padding(.horizontal, lineWidth * 2)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            guard animatesOnAppear else {
                progress = 1
                return
            }
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(TremorMotion.reveal) { progress = 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room risk score")
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(.isSummaryElement)
    }
}

#Preview("RiskScoreDial") {
    ScrollView {
        VStack(spacing: TremorSpacing.xxl) {
            DataPreviewSection("Hero — severe, animates on appear") {
                RiskScoreDial(score: 87)
                    .frame(maxWidth: .infinity)
            }

            DataPreviewSection("Every band") {
                VStack(spacing: TremorSpacing.md) {
                    HStack(spacing: TremorSpacing.md) {
                        RiskScoreDial(score: 12, diameter: 150, animatesOnAppear: false)
                        RiskScoreDial(score: 38, diameter: 150, animatesOnAppear: false)
                    }
                    HStack(spacing: TremorSpacing.md) {
                        RiskScoreDial(score: 61, diameter: 150, animatesOnAppear: false)
                        RiskScoreDial(score: 94, diameter: 150, animatesOnAppear: false)
                    }
                }
            }

            DataPreviewSection("Edges — 0 and 100") {
                HStack(spacing: TremorSpacing.md) {
                    RiskScoreDial(score: 0, diameter: 150, animatesOnAppear: false)
                    RiskScoreDial(score: 100, diameter: 150, animatesOnAppear: false)
                }
            }

            DataPreviewSection("Long caption") {
                RiskScoreDial(score: 55,
                              caption: "14 objects surveyed at intensity VII, soft soil, third floor",
                              diameter: 200,
                              animatesOnAppear: false)
                    .frame(maxWidth: .infinity)
            }

            DataPreviewSection("No caption") {
                RiskScoreDial(score: 43, caption: nil, diameter: 150, animatesOnAppear: false)
            }

            DataPreviewSection("Greyscale") {
                RiskScoreDial(score: 87, diameter: 150, animatesOnAppear: false)
                    .grayscale(1)
            }

            DataPreviewSection("No reveal — the reduce-motion end state") {
                RiskScoreDial(score: 72, diameter: 150, animatesOnAppear: false)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RiskDistributionBar
// ─────────────────────────────────────────────────────────────────────────────

/// A stacked horizontal bar showing how many objects fall in each band.
///
/// Handles the two shapes that break naive stacked bars: a single band holding
/// every object, and zero objects — which gets an explicit message rather than a
/// misleading empty bar.
///
///     RiskDistributionBar(counts: assessment.counts)
///     RiskDistributionBar(assessment)
public struct RiskDistributionBar: View {

    /// Default bar thickness — `TremorSpacing.sm`. Public so it can serve as the
    /// default argument of the public initialisers.
    public static let defaultHeight: CGFloat = TremorSpacing.sm

    private let counts: [RiskBand: Int]
    private let showsLegend: Bool
    private let height: CGFloat
    private let emptyMessage: String

    /// - Parameters:
    ///   - counts: object count per band. Bands absent or zero are omitted.
    ///   - showsLegend: show the count legend under the bar. Defaults to `true`.
    ///   - height: bar thickness. Defaults to 12pt (`TremorSpacing.sm`).
    ///   - emptyMessage: shown when there are no objects at all.
    public init(counts: [RiskBand: Int],
                showsLegend: Bool = true,
                height: CGFloat = RiskDistributionBar.defaultHeight,
                emptyMessage: String = "Nothing scanned yet") {
        self.counts = counts
        self.showsLegend = showsLegend
        self.height = height
        self.emptyMessage = emptyMessage
    }

    /// The distribution of an assessment's object risks.
    public init(_ assessment: RoomAssessment,
                showsLegend: Bool = true,
                height: CGFloat = RiskDistributionBar.defaultHeight) {
        self.init(counts: assessment.counts, showsLegend: showsLegend, height: height)
    }

    private var entries: [(band: RiskBand, count: Int)] {
        RiskBand.allCases.compactMap { band in
            let count = counts[band] ?? 0
            return count > 0 ? (band, count) : nil
        }
    }

    private var total: Int { entries.reduce(0) { $0 + $1.count } }

    private var isEmpty: Bool { total == 0 }

    private var gap: CGFloat { TremorSpacing.hair }

    /// Proportional widths, with every present band lifted to a visible minimum
    /// and the surplus taken back from the segments that can afford it. Without
    /// this, one severe object among two hundred is a sub-pixel sliver — and
    /// that is precisely the object the user most needs to see.
    private func widths(in available: CGFloat) -> [CGFloat] {
        let list = entries
        guard !list.isEmpty, available > 0, total > 0 else { return [] }
        let count = CGFloat(list.count)
        let content = max(available - gap * (count - 1), 0)
        guard content > 0 else { return list.map { _ in 0 } }

        let minWidth = min(height, content / count)
        var raw = list.map { content * CGFloat($0.count) / CGFloat(total) }

        let deficit = raw.reduce(CGFloat(0)) { $0 + max(0, minWidth - $1) }
        let surplus = raw.reduce(CGFloat(0)) { $0 + max(0, $1 - minWidth) }
        if deficit > 0, surplus > 0 {
            raw = raw.map { width in
                width < minWidth ? minWidth : width - deficit * (width - minWidth) / surplus
            }
        } else if deficit > 0 {
            raw = raw.map { _ in content / count }
        }
        return raw
    }

    private var spokenSummary: String {
        guard !isEmpty else { return emptyMessage }
        return entries
            .map { "\($0.count) \($0.band.displayName.lowercased())" }
            .joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            track
            if showsLegend {
                if isEmpty {
                    Text(emptyMessage)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                } else {
                    legend
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Objects by risk band")
        .accessibilityValue(isEmpty ? emptyMessage : "\(total) objects. \(spokenSummary)")
    }

    private var track: some View {
        GeometryReader { geometry in
            let segments = widths(in: geometry.size.width)
            HStack(spacing: gap) {
                if isEmpty {
                    Capsule(style: .continuous)
                        .fill(TremorColor.surfaceSunken)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline)
                        )
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.band) { pair in
                        Capsule(style: .continuous)
                            .fill(pair.element.band.markColor)
                            .frame(width: pair.offset < segments.count ? segments[pair.offset] : 0)
                    }
                }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: height)
    }

    private var legend: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: TremorSpacing.hero + TremorSpacing.xxxl),
                         spacing: TremorSpacing.sm,
                         alignment: .leading)
            ],
            alignment: .leading,
            spacing: TremorSpacing.xs
        ) {
            ForEach(entries, id: \.band) { entry in
                HStack(spacing: TremorSpacing.xs) {
                    Image(systemName: entry.band.symbolName)
                        .font(TremorFont.caption)
                        .foregroundStyle(entry.band.markColor)
                    Text("\(entry.count)")
                        .tremorType(.captionEmphasis, numeric: true)
                        .foregroundStyle(TremorColor.ink)
                    Text(entry.band.displayName)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview("RiskDistributionBar") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            DataPreviewSection("Typical room") {
                RiskDistributionBar(counts: [.low: 6, .moderate: 4, .high: 2, .severe: 1])
            }

            DataPreviewSection("One severe among 180 — minimum width holds") {
                RiskDistributionBar(counts: [.low: 180, .severe: 1])
            }

            DataPreviewSection("All one band") {
                RiskDistributionBar(counts: [.low: 9])
            }

            DataPreviewSection("Zero objects") {
                RiskDistributionBar(counts: [:])
            }

            DataPreviewSection("No legend, hairline-thin") {
                RiskDistributionBar(counts: [.moderate: 3, .high: 3],
                                    showsLegend: false,
                                    height: TremorSpacing.xs)
            }

            DataPreviewSection("Every band equal") {
                RiskDistributionBar(counts: [.low: 5, .moderate: 5, .high: 5, .severe: 5])
            }

            DataPreviewSection("Greyscale") {
                RiskDistributionBar(counts: [.low: 6, .moderate: 4, .high: 2, .severe: 1])
                    .grayscale(1)
            }

            DataPreviewSection("Accessibility text size") {
                RiskDistributionBar(counts: [.low: 6, .moderate: 4, .high: 2, .severe: 1])
                    .environment(\.dynamicTypeSize, .accessibility2)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FactorBreakdownChart
// ─────────────────────────────────────────────────────────────────────────────

/// The ranked consequence contributions, as a horizontal bar list.
///
/// Tremor publishes its reasoning: an object's score is never "trust me, it's a
/// 90". This chart is where that promise is kept. Labels are the plain English
/// `ConsequenceBreakdown.rankedContributions` produces, bars are scaled against
/// the largest contribution so small factors stay readable, and the number
/// beside each bar is that factor's share of the whole consequence.
///
///     FactorBreakdownChart(risk.consequence, band: risk.band)
public struct FactorBreakdownChart: View {

    private let rows: [(label: String, contribution: Double)]
    private let total: Double
    private let band: RiskBand?
    private let isTruncated: Bool
    private let emptyMessage: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - contributions: already-ranked `(label, contribution)` pairs. Order is
    ///     preserved exactly as given — the model decides the ranking, not the
    ///     view. Zero and negative contributions are dropped.
    ///   - band: colours the bars with this band's mark. `nil` uses the brand
    ///     purple, which is right when the chart is not about one object's verdict.
    ///   - maximumRows: show only the top *n*. Percentages stay shares of the
    ///     full set, so a truncated list does not add up to 100%.
    ///   - emptyMessage: shown when nothing contributes.
    public init(contributions: [(label: String, contribution: Double)],
                band: RiskBand? = nil,
                maximumRows: Int? = nil,
                emptyMessage: String = "Nothing about this object drives its score.") {
        let trimmed = contributions.filter { $0.contribution > 0 }
        self.total = max(trimmed.reduce(0) { $0 + $1.contribution }, .leastNonzeroMagnitude)
        if let maximumRows, maximumRows < trimmed.count {
            self.rows = Array(trimmed.prefix(max(maximumRows, 0)))
            self.isTruncated = true
        } else {
            self.rows = trimmed
            self.isTruncated = false
        }
        self.band = band
        self.emptyMessage = emptyMessage
    }

    /// The ranked contributions of a consequence breakdown.
    public init(_ breakdown: ConsequenceBreakdown,
                band: RiskBand? = nil,
                maximumRows: Int? = nil) {
        self.init(contributions: breakdown.rankedContributions,
                  band: band,
                  maximumRows: maximumRows)
    }

    private var barColor: Color { band?.markColor ?? TremorColor.primary }
    private var trackColor: Color { band?.surfaceColor ?? TremorColor.primarySoft }

    private var peak: Double {
        max(rows.map(\.contribution).max() ?? 0, .leastNonzeroMagnitude)
    }

    private func percentText(_ contribution: Double) -> String {
        "\(Int((contribution / total * 100).rounded()))%"
    }

    /// At accessibility text sizes a three-column row cannot hold a label, a bar
    /// and a number, so the row folds into a label/value line above a full-width
    /// bar rather than clipping.
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var labelColumnWidth: CGFloat { TremorSpacing.hero * 2 }
    private var valueColumnWidth: CGFloat { TremorSpacing.xxxl }

    public var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                    if isStacked {
                        stackedRow(pair.element)
                    } else {
                        inlineRow(pair.element)
                    }
                }
                if isTruncated {
                    Text("Top \(rows.count) of the factors behind this score")
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .padding(.top, TremorSpacing.hair)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Why it scored this")
    }

    private func inlineRow(_ row: (label: String, contribution: Double)) -> some View {
        HStack(spacing: TremorSpacing.sm) {
            Text(row.label)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: labelColumnWidth, alignment: .leading)

            bar(row.contribution)

            Text(percentText(row.contribution))
                .tremorType(.captionEmphasis, numeric: true)
                .foregroundStyle(TremorColor.ink)
                .frame(width: valueColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(percentText(row.contribution))
    }

    private func stackedRow(_ row: (label: String, contribution: Double)) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                Text(row.label)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                Spacer(minLength: TremorSpacing.xxs)
                Text(percentText(row.contribution))
                    .tremorType(.captionEmphasis, numeric: true)
                    .foregroundStyle(TremorColor.ink)
            }
            bar(row.contribution)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(percentText(row.contribution))
    }

    private func bar(_ contribution: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                Capsule(style: .continuous)
                    .fill(barColor)
                    .frame(width: max(geometry.size.width * CGFloat(contribution / peak),
                                      TremorSpacing.xxs))
            }
        }
        .frame(height: TremorSpacing.xs)
    }
}

#Preview("FactorBreakdownChart") {
    let heavy = ConsequenceBreakdown(
        impactEnergy: 0.92, occupantExposure: 1.0, fallHeight: 0.88,
        egressBlockage: 0.6, breakage: 0.35, mass: 0.7, secondaryHazard: 0.1
    )
    let light = ConsequenceBreakdown(
        impactEnergy: 0.1, occupantExposure: 0.15, fallHeight: 0.05,
        egressBlockage: 0, breakage: 0, mass: 0.02, secondaryHazard: 0
    )
    let empty = ConsequenceBreakdown(
        impactEnergy: 0, occupantExposure: 0, fallHeight: 0,
        egressBlockage: 0, breakage: 0, mass: 0, secondaryHazard: 0
    )

    return ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            DataPreviewSection("Severe bookcase — every factor") {
                FactorBreakdownChart(heavy, band: .severe)
            }

            DataPreviewSection("Top three only") {
                FactorBreakdownChart(heavy, band: .high, maximumRows: 3)
            }

            DataPreviewSection("Low-risk object — small numbers") {
                FactorBreakdownChart(light, band: .low)
            }

            DataPreviewSection("No band — brand purple") {
                FactorBreakdownChart(heavy)
            }

            DataPreviewSection("Nothing contributes") {
                FactorBreakdownChart(empty, band: .low)
            }

            DataPreviewSection("Long custom labels") {
                FactorBreakdownChart(contributions: [
                    ("Lands squarely across the only way out of the bedroom", 0.28),
                    ("Who's in the way", 0.22),
                    ("Broken glass", 0.04),
                ], band: .severe)
            }

            DataPreviewSection("Accessibility size — rows fold") {
                FactorBreakdownChart(heavy, band: .severe)
                    .environment(\.dynamicTypeSize, .accessibility2)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - IntensityScaleView
// ─────────────────────────────────────────────────────────────────────────────

/// The Mercalli intensity scale, III–X, with the current level highlighted.
///
/// Sits directly above the intensity slider. Severity is encoded by bar *height*
/// as well as by fill, so the scale reads as a meter and survives greyscale. The
/// readout names the level three ways — roman numeral, plain-English shaking
/// label, and PGA in g — because "VII" alone means nothing to a first-time user
/// and "0.25 g" means nothing to anyone.
///
///     IntensityScaleView(intensity: .vii)
///     IntensityScaleView(intensity: level) { level = $0 }
public struct IntensityScaleView: View {

    private let intensity: MercalliIntensity
    private let showsReadout: Bool
    private let onSelect: ((MercalliIntensity) -> Void)?

    private static let levels = MercalliIntensity.allCases

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - intensity: the level to highlight.
    ///   - showsReadout: show the numeral / label / PGA line above the bars.
    ///     Defaults to `true`.
    ///   - onSelect: tapping a level calls this. `nil` makes the scale a purely
    ///     informational display with no tap targets.
    public init(intensity: MercalliIntensity,
                showsReadout: Bool = true,
                onSelect: ((MercalliIntensity) -> Void)? = nil) {
        self.intensity = intensity
        self.showsReadout = showsReadout
        self.onSelect = onSelect
    }

    private var minimumBarHeight: CGFloat { TremorSpacing.sm }
    private var maximumBarHeight: CGFloat { TremorSize.minimumTapTarget }

    private func barHeight(for level: MercalliIntensity) -> CGFloat {
        let first = Self.levels.first?.rawValue ?? level.rawValue
        let span = Double(Self.levels.count - 1)
        let position = Double(level.rawValue - first)
        let t = span > 0 ? position / span : 0
        return minimumBarHeight + (maximumBarHeight - minimumBarHeight) * CGFloat(t)
    }

    private func fill(for level: MercalliIntensity) -> Color {
        if level == intensity { return TremorColor.primary }
        if level < intensity { return TremorColor.primary.opacity(0.30) }
        return TremorColor.surfaceSunken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            if showsReadout { readout }
            bars
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shaking intensity")
        .accessibilityValue(
            "Mercalli \(intensity.roman). \(intensity.shakingLabel) shaking, "
            + "\(dataFormatPGA(intensity.representativePGAInG)). \(intensity.reference)."
        )
        .accessibilityHint(onSelect == nil ? "" : "Tap a level on the scale to change the earthquake.")
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
            Text(intensity.roman)
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
            Text(intensity.shakingLabel)
                .tremorType(.bodyEmphasis)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: TremorSpacing.xs)
            Text(dataFormatPGA(intensity.representativePGAInG))
                .tremorType(.subheadline, numeric: true)
                .foregroundStyle(TremorColor.inkTertiary)
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: TremorSpacing.xxs) {
            ForEach(Self.levels) { level in
                if let onSelect {
                    Button {
                        DataHaptics.selection()
                        onSelect(level)
                    } label: {
                        column(level)
                    }
                    .buttonStyle(DataPressStyle())
                    .accessibilityLabel("Intensity \(level.roman), \(level.shakingLabel)")
                    .accessibilityAddTraits(level == intensity ? [.isButton, .isSelected] : .isButton)
                } else {
                    column(level)
                }
            }
        }
        .animation(reduceMotion ? nil : TremorMotion.colorShift, value: intensity)
    }

    private func column(_ level: MercalliIntensity) -> some View {
        VStack(spacing: TremorSpacing.xxs) {
            RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
                .fill(fill(for: level))
                .frame(height: barHeight(for: level))
                .frame(maxHeight: maximumBarHeight, alignment: .bottom)

            Text(level.roman)
                .tremorType(level == intensity ? .captionEmphasis : .caption)
                .foregroundStyle(level == intensity ? TremorColor.primary : TremorColor.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        // The columns are only ~40pt wide on a 393pt screen, so the tap target
        // is padded out vertically to clear the 44pt minimum.
        .padding(.vertical, TremorSpacing.xxs)
        .contentShape(Rectangle())
    }
}

#Preview("IntensityScaleView") {
    struct Harness: View {
        @State private var level: MercalliIntensity = .vii

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    DataPreviewSection("Interactive — tap a level") {
                        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                            IntensityScaleView(intensity: level) { level = $0 }
                            Text(level.contentsDescription)
                                .tremorType(.callout)
                                .foregroundStyle(TremorColor.inkSecondary)
                        }
                    }

                    DataPreviewSection("Lowest — III") {
                        IntensityScaleView(intensity: .iii)
                    }

                    DataPreviewSection("Highest — X") {
                        IntensityScaleView(intensity: .x)
                    }

                    DataPreviewSection("Longest label — VII, Very strong") {
                        IntensityScaleView(intensity: .vii)
                    }

                    DataPreviewSection("No readout") {
                        IntensityScaleView(intensity: .vi, showsReadout: false)
                    }

                    DataPreviewSection("Greyscale — height still carries it") {
                        IntensityScaleView(intensity: .viii).grayscale(1)
                    }

                    DataPreviewSection("Accessibility text size") {
                        IntensityScaleView(intensity: .ix)
                            .environment(\.dynamicTypeSize, .accessibility2)
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
        }
    }
    return Harness()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - StatTile
// ─────────────────────────────────────────────────────────────────────────────

/// A compact label + big number + optional delta.
///
/// The number is always set in tabular figures so a row of tiles does not jitter
/// as values update during playback.
///
///     StatTile(label: "Objects at risk", value: "7")
///     StatTile(label: "Peak floor", value: "0.42", unit: "g",
///              delta: .init(text: "+18%", direction: .up, sentiment: .negative))
public struct StatTile: View {

    /// Which way the value moved, and whether that is good news.
    public struct Delta: Sendable, Hashable {

        /// The arrow shown beside the delta.
        public enum Direction: Sendable, Hashable {
            case up, down, flat

            var symbolName: String {
                switch self {
                case .up: return "arrow.up.right"
                case .down: return "arrow.down.right"
                case .flat: return "arrow.right"
                }
            }

            var spokenWord: String {
                switch self {
                case .up: return "up"
                case .down: return "down"
                case .flat: return "unchanged"
                }
            }
        }

        /// Whether the movement is good, bad or neither. Kept separate from
        /// `Direction` because in a safety app "down" is usually the good news,
        /// which is the opposite of a finance app.
        public enum Sentiment: Sendable, Hashable {
            case positive, negative, neutral

            var color: Color {
                switch self {
                case .positive: return TremorColor.success
                case .negative: return TremorColor.danger
                case .neutral: return TremorColor.inkTertiary
                }
            }
        }

        public var text: String
        public var direction: Direction
        public var sentiment: Sentiment

        public init(text: String, direction: Direction, sentiment: Sentiment = .neutral) {
            self.text = text
            self.direction = direction
            self.sentiment = sentiment
        }
    }

    private let label: String
    private let value: String
    private let unit: String?
    private let delta: Delta?
    private let alignment: HorizontalAlignment
    private let accent: Color?

    /// - Parameters:
    ///   - label: the overline above the number.
    ///   - value: the number itself, already formatted by the caller.
    ///   - unit: a small suffix set beside the number ("g", "kg", "m").
    ///   - delta: optional change indicator.
    ///   - alignment: `.leading` (default) or `.center` for a symmetric row.
    ///   - accent: colour for the number. Defaults to the ink.
    public init(label: String,
                value: String,
                unit: String? = nil,
                delta: Delta? = nil,
                alignment: HorizontalAlignment = .leading,
                accent: Color? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.alignment = alignment
        self.accent = accent
    }

    /// A tile whose number is coloured by a risk band.
    public init(label: String,
                value: String,
                unit: String? = nil,
                band: RiskBand,
                delta: Delta? = nil,
                alignment: HorizontalAlignment = .leading) {
        self.init(label: label, value: value, unit: unit, delta: delta,
                  alignment: alignment, accent: band.markColor)
    }

    private var spokenValue: String {
        var text = value
        if let unit { text += " \(unit)" }
        if let delta { text += ". \(delta.direction.spokenWord) \(delta.text)" }
        return text
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: TremorSpacing.xxs) {
            Text(label)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xxs) {
                Text(value)
                    .tremorType(.displayM, numeric: true)
                    .foregroundStyle(accent ?? TremorColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .tremorType(.title3)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }

            if let delta {
                HStack(spacing: TremorSpacing.hair) {
                    Image(systemName: delta.direction.symbolName)
                        .font(TremorFont.caption)
                    Text(delta.text)
                        .tremorType(.captionEmphasis, numeric: true)
                        .lineLimit(1)
                }
                .foregroundStyle(delta.sentiment.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
    }
}

#Preview("StatTile") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            DataPreviewSection("Row of three, on a card") {
                HStack(alignment: .top, spacing: TremorSpacing.md) {
                    StatTile(label: "Objects", value: "14")
                    StatTile(label: "At risk", value: "5", band: .high)
                    StatTile(label: "Peak floor", value: "0.42", unit: "g")
                }
                .padding(TremorSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                        .fill(TremorColor.surface)
                )
                .tremorShadow(.card)
            }

            DataPreviewSection("With deltas — up is bad news here") {
                HStack(alignment: .top, spacing: TremorSpacing.md) {
                    StatTile(label: "Room score", value: "72",
                             delta: .init(text: "+18", direction: .up, sentiment: .negative))
                    StatTile(label: "After fixes", value: "24",
                             delta: .init(text: "−48", direction: .down, sentiment: .positive))
                    StatTile(label: "Anchored", value: "3",
                             delta: .init(text: "0", direction: .flat, sentiment: .neutral))
                }
            }

            DataPreviewSection("Centred") {
                HStack(spacing: TremorSpacing.md) {
                    StatTile(label: "Slide", value: "1.4", unit: "m", alignment: .center)
                    StatTile(label: "Impact", value: "310", unit: "J", alignment: .center)
                }
            }

            DataPreviewSection("Long label, long value") {
                HStack(alignment: .top, spacing: TremorSpacing.md) {
                    StatTile(label: "Objects that block the only way out",
                             value: "128", band: .severe)
                    StatTile(label: "Median sliding displacement",
                             value: "12.75", unit: "m")
                }
            }

            DataPreviewSection("Every band") {
                HStack(alignment: .top, spacing: TremorSpacing.sm) {
                    ForEach(RiskBand.allCases) { band in
                        StatTile(label: band.displayName, value: "\(band.order + 1)",
                                 band: band, alignment: .center)
                    }
                }
            }

            DataPreviewSection("Accessibility text size") {
                HStack(alignment: .top, spacing: TremorSpacing.md) {
                    StatTile(label: "Objects", value: "14")
                    StatTile(label: "At risk", value: "5", band: .high)
                }
                .environment(\.dynamicTypeSize, .accessibility2)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ObjectThumbnail
// ─────────────────────────────────────────────────────────────────────────────

/// A rounded square for one object: the captured crop when there is one, and the
/// object type's SF Symbol on a band-tinted fill when there is not.
///
/// The fallback is deliberately not a grey placeholder — tinting it by band means
/// a list captured before any photos exist still reads as a risk list.
///
///     ObjectThumbnail(type: .bookshelfTall, band: .severe)
///     ObjectThumbnail(object: object, band: risk.band, image: crop)
public struct ObjectThumbnail: View {

    /// Default edge length — `TremorSize.row`, the Lyft rich-row thumbnail.
    /// Public so it can serve as the default argument of the public initialisers.
    public static let defaultSize: CGFloat = TremorSize.row

    private let type: ObjectType
    private let band: RiskBand?
    private let image: Image?
    private let size: CGFloat
    private let isLoading: Bool

    /// - Parameters:
    ///   - type: the object type, which supplies the fallback symbol and the
    ///     accessibility name.
    ///   - band: tints the fallback. `nil` uses the lavender brand surface.
    ///   - image: the captured crop. `nil` falls back to the symbol.
    ///   - size: edge length. Defaults to 56pt (`TremorSize.row`), the Lyft
    ///     rich-row thumbnail.
    ///   - isLoading: show the loading treatment while a crop is still coming.
    public init(type: ObjectType,
                band: RiskBand? = nil,
                image: Image? = nil,
                size: CGFloat = ObjectThumbnail.defaultSize,
                isLoading: Bool = false) {
        self.type = type
        self.band = band
        self.image = image
        self.size = size
        self.isLoading = isLoading
    }

    /// Convenience for a scanned object.
    public init(object: ScannedObject,
                band: RiskBand? = nil,
                image: Image? = nil,
                size: CGFloat = ObjectThumbnail.defaultSize,
                isLoading: Bool = false) {
        self.init(type: object.type, band: band, image: image, size: size, isLoading: isLoading)
    }

    /// Convenience for a `UIImage` crop straight off the capture pipeline.
    public init(type: ObjectType,
                band: RiskBand? = nil,
                uiImage: UIImage?,
                size: CGFloat = ObjectThumbnail.defaultSize,
                isLoading: Bool = false) {
        self.init(type: type,
                  band: band,
                  image: uiImage.map { Image(uiImage: $0) },
                  size: size,
                  isLoading: isLoading)
    }

    private var fillColor: Color { band?.surfaceColor ?? TremorColor.primarySoft }
    private var symbolColor: Color { band?.markColor ?? TremorColor.primary }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
    }

    private var spokenLabel: String {
        guard let band else { return type.displayName }
        return "\(type.displayName), \(band.displayName) risk"
    }

    public var body: some View {
        ZStack {
            shape.fill(isLoading ? TremorColor.surfaceSunken : fillColor)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(TremorColor.inkTertiary)
            } else if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: type.symbolName)
                    .font(.system(size: size * 0.40, weight: .medium))
                    .foregroundStyle(symbolColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                image == nil ? symbolColor.opacity(0.12) : TremorColor.stroke,
                lineWidth: TremorSize.hairline
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isImage)
    }
}

#Preview("ObjectThumbnail") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            DataPreviewSection("Fallback symbol, every band") {
                HStack(spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .bookshelfTall, band: .severe)
                    ObjectThumbnail(type: .television, band: .high)
                    ObjectThumbnail(type: .dresser, band: .moderate)
                    ObjectThumbnail(type: .sofa, band: .low)
                }
            }

            DataPreviewSection("No band — brand lavender") {
                HStack(spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .waterHeaterGas)
                    ObjectThumbnail(type: .pianoUpright)
                    ObjectThumbnail(type: .aquarium)
                    ObjectThumbnail(type: .unknown)
                }
            }

            DataPreviewSection("Sizes — 36 / 56 / 88 / 120") {
                HStack(alignment: .bottom, spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .mirrorLeaning, band: .severe, size: TremorSize.buttonSmall)
                    ObjectThumbnail(type: .mirrorLeaning, band: .severe, size: TremorSize.row)
                    ObjectThumbnail(type: .mirrorLeaning, band: .severe, size: TremorSize.rowRich)
                    ObjectThumbnail(type: .mirrorLeaning, band: .severe,
                                    size: TremorSpacing.hero + TremorSize.row)
                }
            }

            DataPreviewSection("Loading") {
                HStack(spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .crib, band: .high, isLoading: true)
                    ObjectThumbnail(type: .crib, band: .high,
                                    size: TremorSize.rowRich, isLoading: true)
                }
            }

            DataPreviewSection("With an image (SF Symbol stand-in for a crop)") {
                HStack(spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .bookshelfTall, band: .severe,
                                    image: Image(systemName: "photo.artframe"))
                    ObjectThumbnail(type: .bookshelfTall, band: .severe,
                                    image: Image(systemName: "photo.artframe"),
                                    size: TremorSize.rowRich)
                }
            }

            DataPreviewSection("In a rich row") {
                HStack(spacing: TremorSpacing.sm) {
                    ObjectThumbnail(type: .bookshelfTall, band: .severe)
                    VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                        Text(ObjectType.bookshelfTall.displayName)
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                        Text("Reaches the bed")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                    }
                    Spacer()
                    RiskBadge(.severe)
                }
                .padding(.horizontal, TremorSpacing.md)
                .frame(height: TremorSize.rowRich)
                .background(
                    RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                        .fill(TremorColor.surface)
                )
                .tremorShadow(.card)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TimelineScrubber
// ─────────────────────────────────────────────────────────────────────────────

/// Playback scrubber for the earthquake simulation.
///
/// Shows elapsed time against total, with a tick on the track at every moment an
/// object failed. Dragging reports continuously through `onScrub` and once more
/// through `onScrubEnd`; crossing a failure marker fires a light impact, so the
/// user feels where the damage happened without watching the numbers.
///
///     TimelineScrubber(currentTime: t, duration: 26,
///                      markers: markers, isPlaying: playing,
///                      onScrub: { t = $0 },
///                      onPlayPause: { playing.toggle() })
public struct TimelineScrubber: View {

    /// A moment an object failed.
    public struct Marker: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// Seconds from the start of the simulation.
        public var time: Double
        /// Band of the object that failed, which colours the tick.
        public var band: RiskBand
        /// What failed, for VoiceOver.
        public var label: String

        public init(id: UUID = UUID(), time: Double, band: RiskBand, label: String) {
            self.id = id
            self.time = time
            self.band = band
            self.label = label
        }
    }

    private let currentTime: Double
    private let duration: Double
    private let markers: [Marker]
    private let isPlaying: Bool
    private let onScrub: ((Double) -> Void)?
    private let onScrubEnd: ((Double) -> Void)?
    private let onPlayPause: (() -> Void)?

    @State private var isDragging = false
    @State private var dragTime: Double = 0
    @State private var lastHapticMarker: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trackHeight: CGFloat { TremorSpacing.xs }
    private var knobSize: CGFloat { TremorSpacing.lg }

    /// - Parameters:
    ///   - currentTime: playhead position in seconds.
    ///   - duration: total simulation length in seconds. Zero or less renders an
    ///     empty track and disables scrubbing.
    ///   - markers: failure moments. Defaults to none.
    ///   - isPlaying: drives the play/pause glyph.
    ///   - onScrub: called continuously while dragging. `nil` makes the scrubber
    ///     read-only.
    ///   - onScrubEnd: called once when the drag finishes.
    ///   - onPlayPause: shows the transport button when non-`nil`.
    public init(currentTime: Double,
                duration: Double,
                markers: [Marker] = [],
                isPlaying: Bool = false,
                onScrub: ((Double) -> Void)? = nil,
                onScrubEnd: ((Double) -> Void)? = nil,
                onPlayPause: (() -> Void)? = nil) {
        self.currentTime = currentTime
        self.duration = duration
        self.markers = markers
        self.isPlaying = isPlaying
        self.onScrub = onScrub
        self.onScrubEnd = onScrubEnd
        self.onPlayPause = onPlayPause
    }

    private var isScrubbable: Bool { onScrub != nil && duration > 0 }

    private var displayedTime: Double {
        let time = isDragging ? dragTime : currentTime
        return min(max(time, 0), max(duration, 0))
    }

    private var fraction: Double {
        duration > 0 ? displayedTime / duration : 0
    }

    private var spokenValue: String {
        let base = "\(dataFormatTime(displayedTime)) of \(dataFormatTime(duration))"
        guard let next = markers
            .filter({ $0.time >= displayedTime })
            .min(by: { $0.time < $1.time })
        else { return base }
        return "\(base). Next failure: \(next.label) at \(dataFormatTime(next.time))."
    }

    public var body: some View {
        VStack(spacing: TremorSpacing.xs) {
            HStack(spacing: TremorSpacing.sm) {
                if let onPlayPause {
                    playPauseButton(onPlayPause)
                }
                track
            }
            timeRow
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let playhead = width * CGFloat(fraction)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(TremorColor.surfaceSunken)
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(TremorColor.primary)
                    .frame(width: max(playhead, 0), height: trackHeight)

                // Failure ticks, drawn above the fill so they stay visible on
                // the part of the track already played through.
                ForEach(markers) { marker in
                    tick(marker)
                        .position(x: markerX(marker, in: width), y: geometry.size.height / 2)
                }

                knob
                    .position(x: knobX(playhead, in: width), y: geometry.size.height / 2)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width),
                     including: isScrubbable ? GestureMask.all : GestureMask.none)
        }
        .frame(height: TremorSize.minimumTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(spokenValue)
        .accessibilityHint(isScrubbable ? "Swipe up or down to move through the simulation." : "")
        // `accessibilityAdjustableAction` is what makes the element adjustable
        // to VoiceOver; there is no separate trait to add in SwiftUI.
        .accessibilityAdjustableAction { direction in
            guard isScrubbable, let onScrub else { return }
            let step = max(duration / 20, 0.1)
            let next: Double
            switch direction {
            case .increment: next = min(displayedTime + step, duration)
            case .decrement: next = max(displayedTime - step, 0)
            @unknown default: return
            }
            onScrub(next)
            onScrubEnd?(next)
        }
    }

    /// One failure tick. Split out of `track` so the type checker does not have
    /// to solve the whole `ZStack` and its geometry arithmetic at once.
    private func tick(_ marker: Marker) -> some View {
        let height: CGFloat = trackHeight * 2.2
        return Capsule(style: .continuous)
            .fill(marker.band.markColor)
            .frame(width: TremorSize.strokeEmphasis, height: height)
            .accessibilityHidden(true)
    }

    private func markerX(_ marker: Marker, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped: Double = min(max(marker.time / duration, 0), 1)
        return width * CGFloat(clamped)
    }

    private func knobX(_ playhead: CGFloat, in width: CGFloat) -> CGFloat {
        let inset: CGFloat = knobSize / 2
        let upper: CGFloat = max(width - inset, inset)
        return min(max(playhead, inset), upper)
    }

    private var knob: some View {
        Circle()
            .fill(TremorColor.surface)
            .frame(width: knobSize, height: knobSize)
            .overlay(
                Circle().strokeBorder(TremorColor.primary, lineWidth: TremorSize.strokeEmphasis)
            )
            .tremorShadow(.raised)
            .scaleEffect(isDragging && !reduceMotion ? 1.18 : 1)
            .opacity(isScrubbable ? 1 : 0.5)
            .animation(reduceMotion ? nil : TremorMotion.release, value: isDragging)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0, duration > 0 else { return }
                if !isDragging {
                    isDragging = true
                    DataHaptics.impact(.soft, intensity: 0.6)
                }
                let time = Double(min(max(value.location.x / width, 0), 1)) * duration
                dragTime = time
                fireMarkerHapticIfNeeded(at: time)
                onScrub?(time)
            }
            .onEnded { value in
                guard width > 0, duration > 0 else { return }
                let time = Double(min(max(value.location.x / width, 0), 1)) * duration
                dragTime = time
                isDragging = false
                lastHapticMarker = nil
                onScrub?(time)
                onScrubEnd?(time)
            }
    }

    /// One light tap as the playhead passes each failure, never twice for the
    /// same marker inside a single drag.
    private func fireMarkerHapticIfNeeded(at time: Double) {
        guard duration > 0 else { return }
        let tolerance = duration * 0.012
        guard let hit = markers.first(where: { abs($0.time - time) <= tolerance }) else {
            lastHapticMarker = nil
            return
        }
        guard hit.id != lastHapticMarker else { return }
        lastHapticMarker = hit.id
        DataHaptics.impact(.light)
    }

    // MARK: Chrome

    private func playPauseButton(_ action: @escaping () -> Void) -> some View {
        Button {
            DataHaptics.impact(.light)
            action()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(TremorFont.subheadline)
                .foregroundStyle(TremorColor.onPrimary)
                .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                .background(Circle().fill(TremorColor.primary))
        }
        .buttonStyle(DataPressStyle())
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint(isPlaying ? "Pauses the earthquake" : "Replays the earthquake")
    }

    private var timeRow: some View {
        HStack(spacing: TremorSpacing.xs) {
            Text(dataFormatTime(displayedTime))
                .tremorType(.footnote, numeric: true)
                .foregroundStyle(TremorColor.ink)
            Spacer(minLength: TremorSpacing.xs)
            if !markers.isEmpty {
                Text("\(markers.count) failed")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .accessibilityLabel("\(markers.count) objects failed during this simulation")
            }
            Spacer(minLength: TremorSpacing.xs)
            Text(dataFormatTime(duration))
                .tremorType(.footnote, numeric: true)
                .foregroundStyle(TremorColor.inkTertiary)
        }
        .padding(.leading, onPlayPause == nil ? 0 : TremorSize.minimumTapTarget + TremorSpacing.sm)
    }
}

#Preview("TimelineScrubber") {
    struct Harness: View {
        @State private var time: Double = 6.2
        @State private var playing = false

        private let markers: [TimelineScrubber.Marker] = [
            TimelineScrubber.Marker(time: 3.1, band: .moderate, label: "Books off the shelf"),
            TimelineScrubber.Marker(time: 7.4, band: .severe, label: "Tall bookshelf toppled"),
            TimelineScrubber.Marker(time: 8.0, band: .high, label: "Television fell"),
            TimelineScrubber.Marker(time: 15.6, band: .high, label: "Dresser walked into the door"),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    DataPreviewSection("Interactive — drag it") {
                        TimelineScrubber(
                            currentTime: time,
                            duration: 26,
                            markers: markers,
                            isPlaying: playing,
                            onScrub: { time = $0 },
                            onScrubEnd: { time = $0 },
                            onPlayPause: { playing.toggle() }
                        )
                    }

                    DataPreviewSection("No transport button") {
                        TimelineScrubber(currentTime: 12, duration: 26,
                                         markers: markers, onScrub: { _ in })
                    }

                    DataPreviewSection("Read-only — knob dimmed") {
                        TimelineScrubber(currentTime: 12, duration: 26, markers: markers)
                    }

                    DataPreviewSection("No failures") {
                        TimelineScrubber(currentTime: 4, duration: 26,
                                         onScrub: { _ in }, onPlayPause: {})
                    }

                    DataPreviewSection("At the start") {
                        TimelineScrubber(currentTime: 0, duration: 26, markers: markers,
                                         onScrub: { _ in }, onPlayPause: {})
                    }

                    DataPreviewSection("At the end, playing") {
                        TimelineScrubber(currentTime: 26, duration: 26, markers: markers,
                                         isPlaying: true, onScrub: { _ in }, onPlayPause: {})
                    }

                    DataPreviewSection("Zero duration — nothing simulated yet") {
                        TimelineScrubber(currentTime: 0, duration: 0,
                                         onScrub: { _ in }, onPlayPause: {})
                    }

                    DataPreviewSection("Long run, dense markers") {
                        TimelineScrubber(
                            currentTime: 61.5,
                            duration: 124,
                            markers: (0..<18).map { index in
                                TimelineScrubber.Marker(
                                    time: Double(index) * 6.4 + 2,
                                    band: RiskBand.allCases[index % 4],
                                    label: "Object \(index + 1)"
                                )
                            },
                            isPlaying: true,
                            onScrub: { _ in },
                            onPlayPause: {}
                        )
                    }
                }
                .padding(.vertical, TremorSpacing.xl)
            }
            .tremorScreen()
        }
    }
    return Harness()
}
