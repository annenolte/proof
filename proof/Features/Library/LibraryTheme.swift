//
//  LibraryTheme.swift
//  Tremor — Features / Library
//
//  Two small things every screen in this folder needs, and nothing else.
//
//  1. `LibraryBandPalette` — the bridge from the model's `RiskBand` to the
//     design system's `TremorRiskBand` colour pair. The design system keeps that
//     bridge `private` on purpose (Components+Data.swift explains why: sibling
//     files are written concurrently and must not collide), so a feature that
//     needs the colours declares its own. This is that declaration, named for
//     its folder so it cannot clash with another team's.
//
//  2. `TremorInfoButton` — the "?" that appears beside anything the app asserts.
//     SPEC S-20 is reachable "from every ? in the app", and a screen should not
//     have to re-derive what that control looks like.
//

import SwiftUI

// MARK: - Band colours

/// `RiskBand` → design-system colours. Colour is never the only channel: every
/// caller pairs these with the band's own `displayName` and `symbolName`.
enum LibraryBandPalette {

    static func tremorBand(_ band: RiskBand) -> TremorRiskBand {
        switch band {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .severe: return .severe
        }
    }

    /// Saturated colour: numerals, icons, rules.
    static func mark(_ band: RiskBand) -> Color { tremorBand(band).mark }

    /// Soft tinted fill: chips, tiles, card washes.
    static func surface(_ band: RiskBand) -> Color { tremorBand(band).surface }

    /// Colour for the summary card of a whole home. Same ramp, so the home
    /// verdict and a room verdict read as the same scale.
    static func wash(_ band: RiskBand?) -> Color {
        guard let band else { return TremorColor.primarySoft }
        return surface(band)
    }
}

// MARK: - The "?" affordance

/// The small circled question mark that opens "How we know" (S-20).
///
/// It is a 44pt tap target with a 20pt glyph, drawn without chrome so it can sit
/// beside a heading without competing with it. The accessibility label says what
/// it opens rather than "question mark", because the symbol name is meaningless
/// out loud.
struct TremorInfoButton: View {

    /// What the "?" is explaining, so VoiceOver can say
    /// "How we work out floor amplification. Button."
    var about: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: TremorControlMetrics.glyphMedium, weight: .medium))
                .foregroundStyle(TremorColor.primary)
                .frame(width: TremorSize.minimumTapTarget,
                       height: TremorSize.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How we know: \(about)")
        .accessibilityHint("Opens the method and sources")
    }
}

#Preview("Info button") {
    VStack(alignment: .leading, spacing: TremorSpacing.xl) {
        HStack(spacing: TremorSpacing.xs) {
            Text("How big?").tremorType(.title2).foregroundStyle(TremorColor.ink)
            TremorInfoButton(about: "the intensity scale") {}
        }
        HStack(spacing: TremorSpacing.xs) {
            ForEach(RiskBand.allCases) { band in
                VStack(spacing: TremorSpacing.xxs) {
                    Circle()
                        .fill(LibraryBandPalette.surface(band))
                        .overlay {
                            Image(systemName: band.symbolName)
                                .foregroundStyle(LibraryBandPalette.mark(band))
                        }
                        .frame(width: TremorSize.buttonMedium, height: TremorSize.buttonMedium)
                    Text(band.displayName)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkSecondary)
                }
            }
        }
    }
    .padding(TremorSpacing.xl)
    .tremorScreen()
}
