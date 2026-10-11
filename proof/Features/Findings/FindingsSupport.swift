//
//  FindingsSupport.swift
//  Tremor — Findings (S-16, S-17, S-21)
//
//  The small shared pieces the three findings screens need and the design
//  system does not ship: a label/value stat row, a disclosure that reveals the
//  maths behind a number, a checkbox, and the formatting the three screens must
//  agree on.
//
//  Everything here is *composed* from `DesignSystem` tokens and components. No
//  new colours, no literal sizes: if something looks like a new primitive it is
//  a rearrangement of existing ones.
//

import SwiftUI

// MARK: - Band colours

/// The risk-band colour pair, reachable from feature code.
///
/// `Components+Data.swift` keeps its own file-private bridge for the same
/// purpose; these carry distinct names so the two can never collide.
extension RiskBand {

    var tremorRiskBand: TremorRiskBand {
        switch self {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .severe: return .severe
        }
    }

    /// Saturated colour, for numerals, icons and rules.
    var bandMark: Color { tremorRiskBand.mark }
    /// Soft tinted fill, for plates and chips.
    var bandSurface: Color { tremorRiskBand.surface }

    /// "Severe, ninety out of one hundred" — the VoiceOver phrasing the spec
    /// requires of every score readout in the app.
    func spokenScore(_ score: Double) -> String {
        "\(displayName), \(Int(score.rounded())) out of 100"
    }
}

// MARK: - Formatting

/// The number formatting the findings screens share.
///
/// It defers to `ReportFormat` wherever the report already has a rule, so the
/// PDF and the screen can never disagree about what 0.152 g rounds to.
enum FindingsFormat {

    /// "0.15 g".
    static func g(_ value: Double) -> String { ReportFormat.g(value) }

    /// "86 kg" or "190 lb", following the user's unit preference.
    static func mass(_ kg: Double, units: UnitSystem) -> String {
        UnitFormatter.mass(kg, in: units)
    }

    /// "about 86 kg (66–106 kg)" — the estimate and the honest spread around it.
    static func massWithRange(_ kg: Double, range: ClosedRange<Double>, units: UnitSystem) -> String {
        guard let spread = massSpread(kg, range: range, units: units) else {
            return "about \(mass(kg, units: units))"
        }
        return "about \(mass(kg, units: units)) (\(spread))"
    }

    /// Just the spread — "could be 66–106 kg" — for the quiet line under a
    /// headline number. `nil` when the prior is tight enough that a range would
    /// read as a typo.
    static func massSpread(_ kg: Double, range: ClosedRange<Double>,
                           units: UnitSystem) -> String? {
        let low = max(range.lowerBound, kg * 0.7)
        let high = min(range.upperBound, kg * 1.3)
        guard high > low + 0.5 else { return nil }
        return "could be \(mass(low, units: units))–\(mass(high, units: units))"
    }

    /// "0.80 × 1.90 × 0.30 m", or feet and inches.
    static func dimensions(_ extents: Extents, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return ReportFormat.dimensions(extents)
        case .imperial:
            let parts = [extents.width, extents.height, extents.depth]
                .map { UnitFormatter.height(Double($0), in: .imperial) }
            return parts.joined(separator: " × ")
        }
    }

    /// "1.4 kJ".
    static func energy(_ joules: Double) -> String { ReportFormat.energy(joules) }

    /// "about $12" or "$12–40".
    static func money(_ range: ClosedRange<Double>) -> String {
        if range.upperBound < 0.01 { return "Free" }
        if range.upperBound - range.lowerBound < 0.5 {
            return "about \(ReportFormat.money(range.lowerBound))"
        }
        return "\(ReportFormat.money(range.lowerBound))–\(ReportFormat.money(range.upperBound))"
    }

    /// "10 min", "2 hours".
    static func duration(_ minutes: Int) -> String { ReportFormat.duration(minutes) }

    /// "4 in 5" — a probability people can picture, rather than "83%".
    static func chanceInWords(_ likelihood: Double) -> String {
        let clamped = min(max(likelihood, 0), 1)
        switch clamped {
        case ..<0.02: return "almost no chance"
        case ..<0.15: return "about a 1 in 10 chance"
        case ..<0.30: return "about a 1 in 4 chance"
        case ..<0.45: return "about a 1 in 3 chance"
        case ..<0.60: return "about a 1 in 2 chance"
        case ..<0.80: return "about a 2 in 3 chance"
        case ..<0.95: return "a 4 in 5 chance"
        default: return "almost certain"
        }
    }

    /// The score as an integer string, for a display numeral.
    static func score(_ value: Double) -> String { "\(Int(value.rounded()))" }
}

// MARK: - Stat row

/// A label on the left, a value on the right, and — when there is one — the
/// working shown underneath on tap.
///
/// Lyft's value row (`label` tertiary on the left, `value-w1-heavy` on the
/// right) with Zip's footnote culture bolted on: every number in this app can
/// be asked where it came from.
struct FindingsStatRow<Detail: View>: View {

    let label: String
    let value: String
    var caption: String?
    /// A quieter line under the value — the uncertainty around a number, kept
    /// off the headline so the headline stays one short phrase.
    var valueCaption: String?
    var chip: String?
    var chipIsCaution: Bool = false
    @ViewBuilder var detail: Detail

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDetail: Bool { Detail.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasDetail {
                Button {
                    withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(spokenValue)
                .accessibilityHint(isExpanded ? "Hides the working" : "Shows how this was worked out")
                .accessibilityAddTraits(.isButton)
            } else {
                header
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(spokenValue)
            }

            if hasDetail, isExpanded {
                detail
                    .padding(.top, TremorSpacing.sm)
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
            }
        }
        .padding(.vertical, TremorSpacing.sm)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(label)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: TremorSpacing.xxs) {
                Text(value)
                    .tremorType(.bodyEmphasis, numeric: true)
                    .foregroundStyle(TremorColor.ink)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let valueCaption {
                    Text(valueCaption)
                        .tremorType(.caption, numeric: true)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let chip {
                    FindingsTag(chip, isCaution: chipIsCaution)
                }
            }

            if hasDetail {
                Image(systemName: "chevron.down")
                    .font(TremorFont.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private var spokenValue: String {
        var text = value
        if let valueCaption { text += ". \(valueCaption)" }
        if let caption { text += ". \(caption)" }
        if let chip { text += ". \(chip)" }
        return text
    }
}

extension FindingsStatRow where Detail == EmptyView {
    init(label: String, value: String, caption: String? = nil,
         valueCaption: String? = nil,
         chip: String? = nil, chipIsCaution: Bool = false) {
        self.init(label: label, value: value, caption: caption,
                  valueCaption: valueCaption,
                  chip: chip, chipIsCaution: chipIsCaution) { EmptyView() }
    }
}

// MARK: - Working

/// The formula, its inputs and its citation — what a stat row reveals.
struct FindingsWorking: View {

    let formula: String
    let inputs: String
    let citation: String

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text(formula)
                .tremorType(.captionEmphasis, numeric: true)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(inputs)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(citation)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TremorSpacing.sm)
        .background(TremorColor.surfaceSunken, in: RoundedRectangle(cornerRadius: TremorRadius.sm,
                                                                   style: .continuous))
    }
}

// MARK: - Tag

/// A tiny static chip. `TremorChip` is a control; this is a label, so it has no
/// tap target and no selection state.
struct FindingsTag: View {

    private let text: String
    private let systemImage: String?
    private let isCaution: Bool

    init(_ text: String, systemImage: String? = nil, isCaution: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.isCaution = isCaution
    }

    var body: some View {
        HStack(spacing: TremorSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(TremorFont.caption)
            }
            Text(text)
                .tremorType(.captionEmphasis)
        }
        .foregroundStyle(isCaution ? TremorColor.warning : TremorColor.primary)
        .padding(.horizontal, TremorSpacing.xs)
        .padding(.vertical, TremorSpacing.xxs)
        .background(isCaution ? TremorColor.surfaceSunken : TremorColor.primarySoft,
                    in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Section

/// An overline label above a block of content. The findings screens are long,
/// and this is what keeps them navigable by the VoiceOver heading rotor.
struct FindingsSectionLabel: View {

    private let title: String
    private let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(title)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Checkbox

/// The 24pt checkbox from the Lyft spec: 6pt radius, ink border when empty,
/// primary fill with a white tick when ticked.
struct FindingsCheckbox: View {

    let isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let side: CGFloat = TremorSpacing.xl   // 24pt

    var body: some View {
        RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
            .fill(isOn ? TremorColor.primary : TremorColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
                    .strokeBorder(isOn ? TremorColor.primary : TremorColor.strokeStrong,
                                  lineWidth: TremorSize.strokeEmphasis)
            }
            .overlay {
                Image(systemName: "checkmark")
                    .font(TremorFont.captionEmphasis)
                    .fontWeight(.bold)
                    .foregroundStyle(TremorColor.onPrimary)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(width: Self.side, height: Self.side)
            .animation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                       value: isOn)
            .accessibilityHidden(true)
    }
}

// MARK: - Before / after score

/// The two numbers that sell a fix: what it scores now, and what it will score
/// once the work is done.
///
/// Never colour alone — each number carries its band name, and the arrow between
/// them is a glyph, so the improvement survives greyscale.
struct FindingsScoreDelta: View {

    let currentScore: Double
    let currentBand: RiskBand
    let projectedScore: Double
    let projectedBand: RiskBand
    var currentLabel: String = "Now"
    var projectedLabel: String = "After the fixes"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var improves: Bool { projectedScore < currentScore - 0.5 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    column(currentLabel, currentScore, currentBand, alignment: .leading)
                    column(projectedLabel, projectedScore, projectedBand, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: TremorSpacing.md) {
                    column(currentLabel, currentScore, currentBand, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(TremorFont.title3)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .padding(.top, TremorSpacing.lg)
                        .accessibilityHidden(true)
                    column(projectedLabel, projectedScore, projectedBand, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func column(_ label: String, _ score: Double, _ band: RiskBand,
                        alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: TremorSpacing.xxs) {
            Text(label)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            Text(FindingsFormat.score(score))
                .tremorType(.displayM, numeric: true)
                .foregroundStyle(band.bandMark)
            RiskBadge(band)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var spoken: String {
        let now = "\(currentLabel): \(currentBand.spokenScore(currentScore))"
        let after = "\(projectedLabel): \(projectedBand.spokenScore(projectedScore))"
        let verdict = improves
            ? "That is \(Int((currentScore - projectedScore).rounded())) points better."
            : "The score does not move."
        return "\(now). \(after). \(verdict)"
    }
}

// MARK: - Previews

#Preview("Findings support") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.lg) {
            FindingsSectionLabel("Why it scores this", subtitle: "Every number can be asked where it came from.")

            TremorCard {
                VStack(spacing: 0) {
                    FindingsStatRow(label: "Weight", value: "about 86 kg (66–106 kg)",
                                    chip: "Estimated") {
                        FindingsWorking(
                            formula: "m = ρ · V · load",
                            inputs: "0.80 × 1.90 × 0.30 m at 190 kg/m³, packed (×1.5)",
                            citation: "Density priors from manufacturer specification sheets.")
                    }
                    TremorRowDivider()
                    FindingsStatRow(label: "Height ÷ depth", value: "6.3",
                                    caption: "Very tall and narrow")
                    TremorRowDivider()
                    FindingsStatRow(label: "Starts to move at", value: "0.15 g",
                                    caption: "Your floor reached 0.55 g")
                }
            }

            TremorCard {
                FindingsScoreDelta(currentScore: 82, currentBand: .severe,
                                   projectedScore: 14, projectedBand: .low)
            }

            HStack(spacing: TremorSpacing.md) {
                FindingsCheckbox(isOn: false)
                FindingsCheckbox(isOn: true)
                FindingsTag("AI-refined", systemImage: "sparkles")
                FindingsTag("Estimated", isCaution: true)
            }
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}
