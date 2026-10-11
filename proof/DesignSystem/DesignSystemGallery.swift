//
//  DesignSystemGallery.swift
//  Tremor — Design System / Living style guide
//
//  Every token and every component in every state, on one scrollable screen.
//  This is the artefact a designer reviews and the reference a screen author
//  copies from. If something is not in here, it is not in the system.
//
//  Structure follows the way the system is built, foundations first:
//
//      01–05  Foundations   colour, type, elevation, shape & space, motion
//      06–07  Buttons       TremorButton, TremorIconButton
//      08–09  Selection     TremorChip, TremorSegmentedControl
//      10–12  Input         TremorTextField, TremorStepper, TremorSlider, TremorToggle
//      13–15  Structure     TremorCard, TremorListRow, TremorSectionHeader
//      16–19  Feedback      TremorBanner, TremorEmptyState, progress, toast
//      20–21  Chrome        TremorNavBar, TremorSheet
//      22–26  Risk          RiskBadge, dial, distribution, factors, intensity
//      27–29  Data          StatTile, ObjectThumbnail, TimelineScrubber
//
//  The gallery is written with the system's own components wherever one exists,
//  so it is also a smoke test: if a component regresses, this screen shows it.
//

import SwiftUI

// MARK: - Root

/// The living style guide. Scrollable, complete, and safe to leave in the app.
struct DesignSystemGallery: View {

    @State private var toast: TremorToastMessage?

    var body: some View {
        TremorNavBarScrollView(
            title: "Design system",
            subtitle: "Every token and component, in every state",
            trailing: TremorNavBarItem(systemImage: "paintpalette",
                                      label: "About this gallery",
                                      hint: "Shows what this screen is for") {}
        ) {
            VStack(alignment: .leading, spacing: TremorSpacing.section) {
                GalleryIntro()
                GalleryFoundations()
                GalleryControls()
                GalleryContainers(toast: $toast)
                GalleryData()
                GalleryColophon()
            }
            .padding(.top, TremorSpacing.xs)
        }
        .tremorToast($toast)
    }
}

// MARK: - Grouped pages
//
// SwiftUI's ViewBuilder tops out at ten children, and a single 40-child body
// would take minutes to type-check. Each group below stays well under both.

private struct GalleryFoundations: View {
    var body: some View {
        Group {
            ColorSection()
            TypeSection()
            ElevationSection()
            ShapeSection()
            MotionSection()
        }
    }
}

private struct GalleryControls: View {
    var body: some View {
        Group {
            ButtonSection()
            IconButtonSection()
            ChipSection()
            SegmentedSection()
            TextFieldSection()
            StepperSliderSection()
            ToggleSection()
        }
    }
}

private struct GalleryContainers: View {
    @Binding var toast: TremorToastMessage?

    var body: some View {
        Group {
            CardSection()
            RowSection()
            SectionHeaderSection()
            BannerSection()
            EmptyStateSection()
            ProgressSection()
            ToastSection(toast: $toast)
            NavBarSection()
            SheetSection()
        }
    }
}

private struct GalleryData: View {
    var body: some View {
        Group {
            RiskBadgeSection()
            RiskDialSection()
            DistributionSection()
            FactorSection()
            IntensitySection()
            StatTileSection()
            ThumbnailSection()
            TimelineSection()
        }
    }
}

// MARK: - Gallery chrome
//
// Deliberately built from raw primitives rather than from TremorSectionHeader:
// the gallery's own furniture must never be mistaken for a specimen.

/// Section heading: a numbered overline eyebrow, a display-scale title and an
/// optional one-line brief. The 48pt gap above it is what gives the page its air.
private struct SectionHead: View {
    let number: String
    let title: String
    var brief: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            HStack(spacing: TremorSpacing.xs) {
                Text(number)
                    .tremorType(.overline, numeric: true)
                    .foregroundStyle(TremorColor.primary)
                Rectangle()
                    .fill(TremorColor.stroke)
                    .frame(height: TremorSize.hairline)
            }

            Text(title)
                .tremorType(.title1)
                .foregroundStyle(TremorColor.ink)
                .accessibilityAddTraits(.isHeader)

            if let brief {
                Text(brief)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.hair)
            }
        }
        .padding(.bottom, TremorSpacing.xs)
    }
}

/// One labelled specimen: an overline caption, an optional note, and the thing
/// itself on a white plate. The plate is what makes a component read as an
/// object rather than as page content.
private struct Specimen<Content: View>: View {
    let label: String
    var note: String?
    var padding: CGFloat = TremorSpacing.md
    var plate: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(label)
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)
                if let note {
                    Text(note)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if plate {
                TremorCard(padding: padding) {
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A section: heading plus a 24pt-rhythm stack of specimens.
private struct Section2<Content: View>: View {
    let number: String
    let title: String
    var brief: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xl) {
            SectionHead(number: number, title: title, brief: brief)
            content
        }
    }
}

// MARK: - Intro

private struct GalleryIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            Text("Warm ink on warm paper, one confident purple, and a great deal of air.")
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Structure from Lyft. Confidence from Zip. Three anchors, and everything else derived from them.")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: TremorSpacing.xs) {
                AnchorSwatch(color: TremorColor.primary, name: "Primary", hex: "#6542BE")
                AnchorSwatch(color: TremorColor.ink, name: "Ink", hex: "#1A0826")
                AnchorSwatch(color: TremorColor.canvas, name: "Canvas", hex: "#F1F0EC")
            }
        }
    }
}

private struct AnchorSwatch: View {
    let color: Color
    let name: String
    let hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                .fill(color)
                .frame(height: 64)
                .overlay {
                    RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                        .strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline)
                }
            Text(name)
                .tremorType(.captionEmphasis)
                .foregroundStyle(TremorColor.ink)
            Text(hex)
                .tremorType(.caption, numeric: true)
                .foregroundStyle(TremorColor.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 01 Colour

private struct ColorToken: Identifiable {
    let id = UUID()
    let name: String
    let hex: String
    let color: Color
}

private let galleryGrid2 = [
    GridItem(.flexible(), spacing: TremorSpacing.sm),
    GridItem(.flexible(), spacing: TremorSpacing.sm),
]

private let galleryGrid3 = [
    GridItem(.flexible(), spacing: TremorSpacing.sm),
    GridItem(.flexible(), spacing: TremorSpacing.sm),
    GridItem(.flexible(), spacing: TremorSpacing.sm),
]

private struct SwatchGrid: View {
    let tokens: [ColorToken]

    var body: some View {
        LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
            ForEach(tokens) { token in
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                        .fill(token.color)
                        .frame(height: 64)
                        .overlay {
                            RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                                .strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline)
                        }
                    Text(token.name)
                        .tremorType(.captionEmphasis)
                        .foregroundStyle(TremorColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(token.hex)
                        .tremorType(.caption, numeric: true)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct ColorSection: View {

    private var ink: [ColorToken] {
        [.init(name: "ink", hex: "#1A0826", color: TremorColor.ink),
         .init(name: "inkSecondary", hex: "#1A0826 · 72%", color: TremorColor.inkSecondary),
         .init(name: "inkTertiary", hex: "#1A0826 · 62%", color: TremorColor.inkTertiary),
         .init(name: "inkInverse", hex: "#FFFFFA", color: TremorColor.inkInverse)]
    }

    private var surfaces: [ColorToken] {
        [.init(name: "canvas", hex: "#F1F0EC", color: TremorColor.canvas),
         .init(name: "surface", hex: "#FFFFFF", color: TremorColor.surface),
         .init(name: "surfaceRaised", hex: "#FFFFFA", color: TremorColor.surfaceRaised),
         .init(name: "surfaceSunken", hex: "#E9E7E3", color: TremorColor.surfaceSunken),
         .init(name: "scrim", hex: "#1A0826 · 30%", color: TremorColor.scrim)]
    }

    private var interactive: [ColorToken] {
        [.init(name: "primary", hex: "#6542BE", color: TremorColor.primary),
         .init(name: "primaryPressed", hex: "#5737A3", color: TremorColor.primaryPressed),
         .init(name: "primarySoft", hex: "#EDE6FF", color: TremorColor.primarySoft),
         .init(name: "onPrimary", hex: "#FFFFFA", color: TremorColor.onPrimary),
         .init(name: "accent", hex: "#E6FE72", color: TremorColor.accent)]
    }

    private var lines: [ColorToken] {
        [.init(name: "stroke", hex: "#D7D3CC", color: TremorColor.stroke),
         .init(name: "strokeStrong", hex: "#B9B2B4", color: TremorColor.strokeStrong),
         .init(name: "divider", hex: "#E7E5E1", color: TremorColor.divider),
         .init(name: "focusRing", hex: "#6542BE · 15%", color: TremorColor.focusRing),
         .init(name: "shadowTint", hex: "#1A0826 · 10%", color: TremorColor.shadowTint)]
    }

    private var semantic: [ColorToken] {
        [.init(name: "success", hex: "#0F7A4F", color: TremorColor.success),
         .init(name: "warning", hex: "#8A5300", color: TremorColor.warning),
         .init(name: "danger", hex: "#B3172F", color: TremorColor.danger),
         .init(name: "info", hex: "#2160BE", color: TremorColor.info)]
    }

    var body: some View {
        Section2(number: "01",
                 title: "Colour",
                 brief: "No neutral is a true grey. Secondary ink is alpha over the primary ink, never a separate grey.") {

            Specimen(label: "Ink", note: "Zip’s #1A0826 is hsl(281°, 65%, 9%) — a purple at 9% lightness. 16.6:1 on canvas.") {
                SwatchGrid(tokens: ink)
            }

            Specimen(label: "Surfaces", note: "Warm paper canvas, generous white plates on top of it.") {
                SwatchGrid(tokens: surfaces)
            }

            Specimen(label: "Interactive", note: "One purple does all the work. The lime accent is a surprise surface only — never text, never more than a few percent of a screen.") {
                SwatchGrid(tokens: interactive)
            }

            Specimen(label: "Lines", note: "1pt hairlines; 1.5pt for selection and focus.") {
                SwatchGrid(tokens: lines)
            }

            Specimen(label: "Semantic states", note: "Success is not a risk band — the Low band is teal, so “safe” is never carried by green alone.") {
                SwatchGrid(tokens: semantic)
            }

            Specimen(label: "Risk bands",
                     note: "Severity is encoded three times: hue on the blue↔yellow axis, mark luminance falling as risk rises, and surface luminance falling with it.") {
                RiskBandLadder()
            }
        }
    }
}

private struct RiskBandLadder: View {
    private let hexes: [TremorRiskBand: (String, String)] = [
        .low: ("#0A7189", "#DFF1F6"),
        .moderate: ("#754E00", "#FBE7BE"),
        .high: ("#80260A", "#FBD1C4"),
        .severe: ("#6B0029", "#F9B8D0"),
    ]

    var body: some View {
        VStack(spacing: TremorSpacing.sm) {
            ForEach(TremorRiskBand.allCases, id: \.self) { band in
                HStack(spacing: TremorSpacing.sm) {
                    Text(band.title)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.ink)
                        .frame(width: 72, alignment: .leading)

                    RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
                        .fill(band.mark)
                        .frame(height: 40)
                        .overlay {
                            Text(hexes[band]?.0 ?? "")
                                .tremorType(.caption, numeric: true)
                                .foregroundStyle(TremorColor.inkInverse)
                        }

                    RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
                        .fill(band.surface)
                        .frame(height: 40)
                        .overlay {
                            Text(hexes[band]?.1 ?? "")
                                .tremorType(.caption, numeric: true)
                                .foregroundStyle(band.mark)
                        }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - 02 Type

private struct TypeSection: View {

    var body: some View {
        Section2(number: "02",
                 title: "Type",
                 brief: "Instrument Sans at display sizes, Inter at text sizes. Three workhorse sizes: 17, 15, 13.") {

            Specimen(label: "Display · Instrument Sans", padding: TremorSpacing.lg) {
                TypeRamp(styles: [.displayXL, .displayL, .displayM, .title1, .title2, .title3])
            }

            Specimen(label: "Text · Inter", padding: TremorSpacing.lg) {
                TypeRamp(styles: [.headline, .body, .bodyEmphasis, .callout, .subheadline, .footnote, .caption, .captionEmphasis, .overline])
            }

            Specimen(label: "Weight is the hierarchy",
                     note: "body and bodyEmphasis are the same 17pt. Lyft builds its whole list hierarchy this way.") {
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text("Tall bookcase")
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    Text("Tall bookcase")
                        .tremorType(.body)
                        .foregroundStyle(TremorColor.inkSecondary)
                }
            }

            Specimen(label: "Tabular figures",
                     note: "`.tremorType(_:numeric: true)` for anything that counts, so digits don’t jitter.") {
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text("111.11  ·  000.00")
                        .tremorType(.title2, numeric: true)
                        .foregroundStyle(TremorColor.ink)
                    Text("111.11  ·  000.00")
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }
        }
    }
}

private struct TypeRamp: View {
    let styles: [TremorType]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                if index > 0 {
                    Rectangle()
                        .fill(TremorColor.divider)
                        .frame(height: TremorSize.hairline)
                        .padding(.vertical, TremorSpacing.sm)
                }
                TypeSpecimenRow(style: style)
            }
        }
    }
}

private struct TypeSpecimenRow: View {
    let style: TremorType

    var body: some View {
        let spec = style.spec
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(sample)
                .tremorType(style)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            Text(meta(spec))
                .tremorType(.caption, numeric: true)
                .foregroundStyle(TremorColor.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func meta(_ spec: TremorTypeSpec) -> String {
        let tracking = spec.tracking == 0
            ? "0"
            : String(format: "%+.2f", spec.tracking)
        let weight = spec.face.rawValue.split(separator: "-").last.map(String.init) ?? ""
        return "\(style.rawValue)  ·  \(Int(spec.size))/\(Int(spec.lineHeight))  ·  \(weight)  ·  \(tracking)"
    }

    private var sample: String {
        switch style {
        case .displayXL: return "Severe"
        case .displayL: return "0.42 g"
        case .displayM: return "Your bedroom"
        case .title1: return "Objects at risk"
        case .title2: return "Choose an intensity"
        case .title3: return "What we found"
        case .headline: return "Tall bookcase"
        case .body: return "The bookcase slid 340 mm and stopped short of the bed."
        case .bodyEmphasis: return "The bookcase slid 340 mm."
        case .callout: return "Anchor it to a stud with two L-brackets."
        case .subheadline: return "Not anchored"
        case .footnote: return "1.8 m · 42 kg · loaded"
        case .caption: return "Estimated from the scan"
        case .captionEmphasis: return "Estimated"
        case .overline: return "Foundations"
        }
    }
}

// MARK: - 03 Elevation

private struct ElevationSection: View {
    var body: some View {
        Section2(number: "03",
                 title: "Elevation",
                 brief: "Two layers — an ambient hairline plus a soft key — in aubergine at low alpha. Never black.") {

            Specimen(label: "The six levels", plate: false) {
                LazyVGrid(columns: galleryGrid3, spacing: TremorSpacing.md) {
                    ForEach(TremorShadow.allCases, id: \.self) { level in
                        VStack(spacing: TremorSpacing.xs) {
                            RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                                .fill(TremorColor.surface)
                                .frame(height: 72)
                                .tremorShadow(level)
                            Text(level.rawValue)
                                .tremorType(.caption)
                                .foregroundStyle(TremorColor.inkTertiary)
                        }
                    }
                }
            }

            Specimen(label: "panel — the sheet glow",
                     note: "Omnidirectional, not a drop shadow. The sheet floats off the viewport in every direction.",
                     padding: TremorSpacing.xl) {
                RoundedRectangle(cornerRadius: TremorRadius.sheet, style: .continuous)
                    .fill(TremorColor.surface)
                    .frame(height: 80)
                    .tremorShadow(.panel)
            }
        }
    }
}

// MARK: - 04 Shape & space

private struct ShapeSection: View {

    private let radii: [(String, CGFloat)] = [
        ("xs · 4", TremorRadius.xs),
        ("sm · 8", TremorRadius.sm),
        ("thumbnail · 12", TremorRadius.thumbnail),
        ("card · 16", TremorRadius.card),
        ("modal · 20", TremorRadius.modal),
        ("sheet · 24", TremorRadius.sheet),
        ("xxl · 28", TremorRadius.xxl),
        ("button / chip · pill", TremorRadius.button),
    ]

    private let spacings: [(String, CGFloat)] = [
        ("hair · 2", TremorSpacing.hair),
        ("xxs · 4", TremorSpacing.xxs),
        ("xs · 8", TremorSpacing.xs),
        ("sm · 12", TremorSpacing.sm),
        ("md · 16", TremorSpacing.md),
        ("lg · 20", TremorSpacing.lg),
        ("xl · 24", TremorSpacing.xl),
        ("xxl · 32", TremorSpacing.xxl),
        ("xxxl · 40", TremorSpacing.xxxl),
        ("section · 48", TremorSpacing.section),
        ("hero · 64", TremorSpacing.hero),
    ]

    private let sizes: [(String, CGFloat)] = [
        ("buttonLarge", TremorSize.buttonLarge),
        ("buttonMedium", TremorSize.buttonMedium),
        ("buttonSmall", TremorSize.buttonSmall),
        ("field", TremorSize.field),
        ("row", TremorSize.row),
        ("rowTwoLine", TremorSize.rowTwoLine),
        ("rowRich", TremorSize.rowRich),
        ("topBar", TremorSize.topBar),
        ("minimumTapTarget", TremorSize.minimumTapTarget),
    ]

    var body: some View {
        Section2(number: "04",
                 title: "Shape & space",
                 brief: "4pt base, 8pt rhythm, 24pt page gutter. Pills for buttons, 16 for cards, 24 for sheets.") {

            Specimen(label: "Radii") {
                LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
                    ForEach(radii, id: \.0) { name, value in
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            RoundedRectangle(cornerRadius: value, style: .continuous)
                                .fill(TremorColor.primarySoft)
                                .frame(height: 56)
                                .overlay {
                                    RoundedRectangle(cornerRadius: value, style: .continuous)
                                        .strokeBorder(TremorColor.primary.opacity(0.35),
                                                      lineWidth: TremorSize.hairline)
                                }
                            Text(name)
                                .tremorType(.caption)
                                .foregroundStyle(TremorColor.inkTertiary)
                        }
                    }
                }
            }

            Specimen(label: "Spacing scale") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(spacings, id: \.0) { name, value in
                        HStack(spacing: TremorSpacing.sm) {
                            Capsule(style: .continuous)
                                .fill(TremorColor.primary)
                                .frame(width: value, height: 10)
                            Text(name)
                                .tremorType(.caption, numeric: true)
                                .foregroundStyle(TremorColor.inkTertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            Specimen(label: "Component heights") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(sizes, id: \.0) { name, value in
                        HStack(spacing: TremorSpacing.sm) {
                            Text(name)
                                .tremorType(.footnote)
                                .foregroundStyle(TremorColor.inkSecondary)
                            Spacer(minLength: TremorSpacing.xs)
                            Text("\(Int(value)) pt")
                                .tremorType(.captionEmphasis, numeric: true)
                                .foregroundStyle(TremorColor.ink)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 05 Motion

private struct MotionSection: View {

    private let rows: [(String, String)] = [
        ("tap", "100 ms · change · scale 0.97"),
        ("release", "200 ms · change"),
        ("reveal", "300 ms · enter · crossfade + 8pt rise"),
        ("dismiss", "250 ms · exit"),
        ("sheet", "350 ms · enter"),
        ("sheetExit", "300 ms · exit"),
        ("change", "300 ms · symmetric ease"),
        ("colorShift", "250 ms · linear — colour is never eased"),
        ("springy", "spring 0.34 / 0.78 — results landing with weight"),
        ("staggerDelay", "125 ms between list items"),
    ]

    var body: some View {
        Section2(number: "05",
                 title: "Motion",
                 brief: "Enter decelerates hard, exit accelerates away, and exits are always shorter than enters.") {

            Specimen(label: "Named animations", padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { TremorRowDivider() }
                        TremorListRow(title: row.0, subtitle: row.1)
                    }
                }
            }

            Specimen(label: "Press feedback", note: "Every control scales to 0.97 on press. Tap and hold any button in this gallery.") {
                MotionDemo()
            }
        }
    }
}

private struct MotionDemo: View {
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TremorSpacing.md) {
            RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                .fill(TremorColor.primary)
                .frame(width: 88, height: 56)
                .scaleEffect(pressed ? TremorMotion.pressScale : 1)
                .animation(reduceMotion ? nil : TremorMotion.tap, value: pressed)
                .onTapGesture {
                    pressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { pressed = false }
                }
                .accessibilityHidden(true)

            Text("Tap to see the 0.97 press scale on the change curve.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 06 Buttons

private struct ButtonSection: View {
    var body: some View {
        Section2(number: "06",
                 title: "Buttons",
                 brief: "Full pills at 56 / 48 / 36pt. The primary fill is the only saturated purple on a screen.") {

            Specimen(label: "Variants · large") {
                VStack(spacing: TremorSpacing.xs) {
                    TremorButton("Run the simulation") {}
                    TremorButton("Rescan the room", variant: .secondary) {}
                    TremorButton("Not now", variant: .tertiary) {}
                    TremorButton("Delete this room", variant: .destructive) {}
                }
            }

            Specimen(label: "Accent",
                     note: "The lime is a surprise surface, not a second primary. Zip keeps it under 5% of a screen, so it never runs full width here.") {
                HStack(spacing: TremorSpacing.xs) {
                    TremorButton("Fix it first", variant: .accent, size: .medium, fillsWidth: false) {}
                    Spacer(minLength: 0)
                }
            }

            Specimen(label: "Sizes", note: "large 56 · medium 48 · small 36. All full pills.") {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    TremorButton("Large", size: .large, fillsWidth: false) {}
                    TremorButton("Medium", size: .medium, fillsWidth: false) {}
                    TremorButton("Small", size: .small, fillsWidth: false) {}
                }
            }

            Specimen(label: "With icons") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Scan a room", leadingIcon: "viewfinder") {}
                    TremorButton("See the report", variant: .secondary, trailingIcon: "arrow.right") {}
                    TremorButton("Share", variant: .tertiary, size: .medium,
                                leadingIcon: "square.and.arrow.up") {}
                }
            }

            Specimen(label: "Loading", note: "Width does not change and colour stays full strength — a loading CTA is not a disabled CTA.") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Simulating", isLoading: true) {}
                    TremorButton("Simulating", variant: .secondary, isLoading: true) {}
                }
            }

            Specimen(label: "Disabled", note: "A 62% white veil over the whole control, Lyft’s treatment — not a grey swap.") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Run the simulation") {}.disabled(true)
                    TremorButton("Rescan", variant: .secondary) {}.disabled(true)
                    TremorButton("Not now", variant: .tertiary) {}.disabled(true)
                    TremorButton("Delete", variant: .destructive) {}.disabled(true)
                }
            }

            Specimen(label: "Long labels", note: "Two lines rather than truncation; the pill grows.") {
                TremorButton("Anchor the bookcase to a stud before you sleep here again") {}
            }
        }
    }
}

// MARK: - 07 Icon buttons

private struct IconButtonSection: View {
    var body: some View {
        Section2(number: "07",
                 title: "Icon buttons",
                 brief: "Circular at 48 / 44 / 36pt. White fill, raised, 24pt glyph.") {

            Specimen(label: "Styles") {
                HStack(spacing: TremorSpacing.md) {
                    IconSpecimen(label: "surface") {
                        TremorIconButton(systemImage: "arrow.left", style: .surface, label: "Back") {}
                    }
                    IconSpecimen(label: "material") {
                        TremorIconButton(systemImage: "map", style: .material, label: "Map") {}
                    }
                    IconSpecimen(label: "primary") {
                        TremorIconButton(systemImage: "play.fill", style: .primary, label: "Play") {}
                    }
                    IconSpecimen(label: "ghost") {
                        TremorIconButton(systemImage: "ellipsis", style: .ghost, label: "More") {}
                    }
                }
            }

            Specimen(label: "Sizes") {
                HStack(alignment: .bottom, spacing: TremorSpacing.md) {
                    IconSpecimen(label: "large 48") {
                        TremorIconButton(systemImage: "plus", size: .large, label: "Add") {}
                    }
                    IconSpecimen(label: "medium 44") {
                        TremorIconButton(systemImage: "plus", size: .medium, label: "Add") {}
                    }
                    IconSpecimen(label: "small 36") {
                        TremorIconButton(systemImage: "plus", size: .small, label: "Add") {}
                    }
                }
            }

            Specimen(label: "Selected & disabled") {
                HStack(spacing: TremorSpacing.md) {
                    IconSpecimen(label: "selected") {
                        TremorIconButton(systemImage: "bookmark.fill", label: "Saved", isSelected: true) {}
                    }
                    IconSpecimen(label: "unselected") {
                        TremorIconButton(systemImage: "bookmark", label: "Save") {}
                    }
                    IconSpecimen(label: "disabled") {
                        TremorIconButton(systemImage: "trash", label: "Delete") {}.disabled(true)
                    }
                }
            }
        }
    }
}

private struct IconSpecimen<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: TremorSpacing.xs) {
            content
            Text(label)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
        }
    }
}

// MARK: - 07 Chips

private struct ChipSection: View {
    @State private var selected: Set<String> = ["Severe"]

    private let filters = ["All", "Severe", "High", "Moderate", "Low"]

    var body: some View {
        Section2(number: "08",
                 title: "Chips",
                 brief: "36pt pills. Selection is ink, not colour, and a check always comes with it.") {

            Specimen(label: "Live · multi-select") {
                TremorFlowRow {
                    ForEach(filters, id: \.self) { name in
                        TremorChip(name, isSelected: selected.contains(name)) {
                            if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
                        }
                    }
                }
            }

            Specimen(label: "With icons and counts") {
                TremorFlowRow {
                    TremorChip("Bedroom", systemImage: "bed.double.fill", count: 12) {}
                    TremorChip("Kitchen", systemImage: "cooktop.fill", count: 4, isSelected: true) {}
                    TremorChip("Office", systemImage: "desktopcomputer") {}
                }
            }

            Specimen(label: "States") {
                TremorFlowRow {
                    TremorChip("Unselected") {}
                    TremorChip("Selected", isSelected: true) {}
                    TremorChip("No check", isSelected: true, showsSelectionCheck: false) {}
                    TremorChip("Disabled") {}.disabled(true)
                }
            }
        }
    }
}

/// A wrapping row, so chip and badge groups reflow onto as many lines as they
/// need instead of being sliced by the edge of the plate they sit on.
private struct TremorFlowRow<Content: View>: View {
    var spacing: CGFloat = TremorSpacing.xs
    @ViewBuilder var content: Content

    var body: some View {
        WrapLayout(spacing: spacing, lineSpacing: TremorSpacing.xs) {
            content
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - 07b Segmented

private enum GallerySegment: String, CaseIterable, Identifiable, Hashable {
    case objects, room, report
    var id: String { rawValue }
    var title: String {
        switch self {
        case .objects: return "Objects"
        case .room: return "Room"
        case .report: return "Report"
        }
    }
    var icon: String {
        switch self {
        case .objects: return "cube"
        case .room: return "square.split.bottomrightquarter"
        case .report: return "doc.text"
        }
    }
}

private enum GalleryPair: String, CaseIterable, Identifiable, Hashable {
    case before, after
    var id: String { rawValue }
}

private struct SegmentedSection: View {
    @State private var tab: GallerySegment = .objects
    @State private var pair: GalleryPair = .before

    var body: some View {
        Section2(number: "09",
                 title: "Segmented control",
                 brief: "A sunken track, a white thumb sliding on the change curve, labels crossfading behind it.") {

            Specimen(label: "Three segments · live") {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    TremorSegmentedControl(selection: $tab, label: "View") { $0.title }
                    Text("Selected: \(tab.title)")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }

            Specimen(label: "With icons") {
                TremorSegmentedControl(selection: $tab, label: "View", icon: { $0.icon }) { $0.title }
            }

            Specimen(label: "Two segments") {
                TremorSegmentedControl(selection: $pair, label: "Comparison") { $0.rawValue.capitalized }
            }

            Specimen(label: "Disabled") {
                TremorSegmentedControl(selection: $tab, label: "View") { $0.title }
                    .disabled(true)
            }
        }
    }
}

// MARK: - 08 Text fields

private struct TextFieldSection: View {
    @State private var name = ""
    @State private var filled = "Master bedroom"
    @State private var mass = "42"
    @State private var secret = "hunter2"
    @State private var broken = "-3"

    var body: some View {
        Section2(number: "10",
                 title: "Text fields",
                 brief: "56pt, 12pt radius, a label that never disappears, a 1.5pt stroke that answers focus and error.") {

            Specimen(label: "Empty & filled") {
                VStack(spacing: TremorSpacing.md) {
                    TremorTextField("Room name", text: $name, placeholder: "e.g. Master bedroom")
                    TremorTextField("Room name", text: $filled)
                }
            }

            Specimen(label: "Leading icon, help text, numeric keyboard") {
                TremorTextField("Mass",
                               text: $mass,
                               placeholder: "0",
                               helpText: "Estimated from the scan. Override it if you know better.",
                               leadingIcon: "scalemass",
                               keyboardType: .decimalPad)
            }

            Specimen(label: "Error") {
                TremorTextField("Mass",
                               text: $broken,
                               errorMessage: "Mass has to be greater than zero.",
                               leadingIcon: "scalemass",
                               keyboardType: .decimalPad)
            }

            Specimen(label: "Secure, with reveal") {
                TremorTextField("Passcode", text: $secret, isSecure: true, leadingIcon: "lock")
            }

            Specimen(label: "Disabled") {
                TremorTextField("Room name", text: $filled, helpText: "Locked while the simulation runs.")
                    .disabled(true)
            }
        }
    }
}

// MARK: - 08b Stepper / slider

private struct StepperSliderSection: View {
    @State private var shelves = 4
    @State private var people = 0
    @State private var intensity: Double = 7
    @State private var confidence: Double = 3

    var body: some View {
        Section2(number: "11",
                 title: "Stepper & slider",
                 brief: "The slider bands its own track, so the value reads as a risk level before you let go.") {

            Specimen(label: "Stepper") {
                VStack(spacing: TremorSpacing.md) {
                    TremorStepper("Shelves", value: $shelves, in: 1...10)
                    TremorStepper("People in the room", value: $people, in: 0...8) {
                        $0 == 0 ? "None" : "\($0)"
                    }
                }
            }

            Specimen(label: "Stepper at its bounds", note: "The − / + buttons disable independently.") {
                VStack(spacing: TremorSpacing.md) {
                    TremorStepper("At minimum", value: .constant(0), in: 0...5)
                    TremorStepper("At maximum", value: .constant(5), in: 0...5)
                }
            }

            Specimen(label: "Slider · banded", padding: TremorSpacing.lg) {
                TremorSlider(value: $intensity,
                            in: 3...10,
                            label: "Shaking intensity",
                            minimumLabel: "Barely felt",
                            maximumLabel: "Extreme",
                            valueLabel: { "Mercalli \(Int($0))" })
            }

            Specimen(label: "Slider · plain", padding: TremorSpacing.lg) {
                TremorSlider(value: $confidence, in: 1...5, label: "Confidence")
            }

            Specimen(label: "Slider · disabled", padding: TremorSpacing.lg) {
                TremorSlider(value: .constant(6), in: 3...10, label: "Shaking intensity")
                    .disabled(true)
            }
        }
    }
}

// MARK: - 08c Toggles

private struct ToggleSection: View {
    @State private var anchored = true
    @State private var haptics = false
    @State private var bare = true

    var body: some View {
        Section2(number: "12",
                 title: "Toggles",
                 brief: "51 × 31 track, purple when on, 200ms on the change curve.") {

            Specimen(label: "Rows") {
                VStack(spacing: TremorSpacing.md) {
                    TremorToggle("Anchored to the wall",
                                subtitle: "Strapped, bolted or built in.",
                                systemImage: "wrench.and.screwdriver.fill",
                                isOn: $anchored)
                    TremorRowDivider(leadingInset: 0)
                    TremorToggle("Haptics", isOn: $haptics)
                }
            }

            Specimen(label: "States") {
                VStack(spacing: TremorSpacing.md) {
                    TremorToggle("On", isOn: .constant(true))
                    TremorToggle("Off", isOn: .constant(false))
                    TremorToggle("On · disabled", isOn: .constant(true)).disabled(true)
                    TremorToggle("Off · disabled", isOn: .constant(false)).disabled(true)
                }
            }

            Specimen(label: "Bare switch style", note: "`TremorSwitchToggleStyle()` on a plain Toggle, when the row is yours.") {
                Toggle("Bare", isOn: $bare)
                    .toggleStyle(TremorSwitchToggleStyle())
                    .labelsHidden()
            }
        }
    }
}

// MARK: - 09 Cards

private struct CardSection: View {
    var body: some View {
        Section2(number: "13",
                 title: "Cards",
                 brief: "16pt radius, 16pt padding. A generous white plate on warm canvas is the structural idea.") {

            Specimen(label: "Default", plate: false) {
                TremorCard {
                    CardBody(title: "Tall bookcase",
                             detail: "1.8 m, 42 kg, loaded. Not anchored.")
                }
            }

            Specimen(label: "Selected · 1.5pt ink border", plate: false) {
                TremorCard(isSelected: true) {
                    CardBody(title: "Tall bookcase", detail: "Selection is expressed with ink, not colour.")
                }
            }

            Specimen(label: "Tinted fill, no shadow", plate: false) {
                TremorCard(fill: TremorColor.primarySoft, shadow: nil) {
                    CardBody(title: "Anchor this first",
                             detail: "The lavender surface is Zip’s workhorse fill.")
                }
            }

            Specimen(label: "Flat on the canvas", plate: false) {
                TremorCard(fill: TremorColor.surfaceSunken, shadow: nil) {
                    CardBody(title: "Sunken", detail: "For recessed wells and quiet asides.")
                }
            }

            Specimen(label: "Tappable", plate: false) {
                TremorCard.tappable(accessibilityLabel: "Open the bedroom report",
                                   action: {}) {
                    CardBody(title: "Bedroom", detail: "Tap me — I scale to 0.97 and wash on press.")
                }
            }

            Specimen(label: "Zero padding, sheet radius", plate: false) {
                TremorCard(padding: 0, radius: TremorRadius.sheet, shadow: .raised) {
                    VStack(spacing: 0) {
                        TremorListRow(title: "Bookcase", accessory: .risk(.severe))
                        TremorRowDivider()
                        TremorListRow(title: "Dresser", accessory: .risk(.moderate))
                    }
                }
            }
        }
    }
}

private struct CardBody: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(title)
                .tremorType(.bodyEmphasis)
                .foregroundStyle(TremorColor.ink)
            Text(detail)
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 10 Rows

private struct RowSection: View {
    @State private var rowToggle = true

    var body: some View {
        Section2(number: "14",
                 title: "List rows",
                 brief: "56 / 72 / 88pt tall, 16pt insets, and a trailing block that holds when the title wraps.") {

            Specimen(label: "Leading treatments", padding: 0) {
                VStack(spacing: 0) {
                    TremorListRow(title: "No leading", subtitle: "Plain two-line row", accessory: .chevron) {}
                    TremorRowDivider()
                    TremorListRow(title: "Icon", subtitle: "24pt symbol in ink",
                                 leading: .icon("cube"), accessory: .chevron) {}
                    TremorRowDivider()
                    TremorListRow(title: "Icon well", subtitle: "Lavender 40pt well",
                                 leading: .iconWell("books.vertical.fill"), accessory: .chevron) {}
                    TremorRowDivider()
                    TremorListRow(title: "Tinted well", subtitle: "Any tint, any fill",
                                 leading: .iconWell(symbol: "flame.fill",
                                                    tint: TremorColor.danger,
                                                    fill: TremorColor.danger.opacity(0.12)),
                                 accessory: .chevron) {}
                    TremorRowDivider()
                    TremorListRow(title: "Risk mark", subtitle: "Band shape, band colour, band name",
                                 leading: .risk(.severe), accessory: .chevron) {}
                }
            }

            Specimen(label: "Trailing accessories", padding: 0) {
                VStack(spacing: 0) {
                    TremorListRow(title: "Chevron", leading: .icon("chevron.right"), accessory: .chevron) {}
                    TremorRowDivider()
                    TremorListRow(title: "Value", accessory: .value("1.8 m")) {}
                    TremorRowDivider()
                    TremorListRow(title: "Risk chip", accessory: .risk(.high)) {}
                    TremorRowDivider()
                    TremorListRow(title: "Badge", accessory: .badge("12")) {}
                    TremorRowDivider()
                    TremorListRow(title: "Toggle", subtitle: "The row becomes a real Toggle",
                                 accessory: .toggle($rowToggle))
                    TremorRowDivider()
                    TremorListRow(title: "Custom", accessory: .custom(AnyView(
                        RiskBadge(.low, size: .small)
                    ))) {}
                    TremorRowDivider()
                    TremorListRow(title: "None — static row", subtitle: "No action, no chevron")
                }
            }

            Specimen(label: "Selected & long titles", padding: 0) {
                VStack(spacing: 0) {
                    TremorListRow(title: "Selected",
                                 subtitle: "Lavender wash, purple mark",
                                 leading: .iconWell("checkmark"),
                                 isSelected: true) {}
                    TremorRowDivider()
                    TremorListRow(title: "A very tall bookcase against the north wall of the bedroom",
                                 subtitle: "Wraps to two lines; the risk chip stays put",
                                 leading: .risk(.severe),
                                 accessory: .risk(.severe)) {}
                }
            }

            Specimen(label: "Divider insets", padding: 0) {
                VStack(spacing: 0) {
                    TremorListRow(title: "16pt inset (default)")
                    TremorRowDivider()
                    TremorListRow(title: "Full bleed")
                    TremorRowDivider(leadingInset: 0)
                    TremorListRow(title: "Last row")
                }
            }
        }
    }
}

// MARK: - 10b Section headers

private struct SectionHeaderSection: View {
    var body: some View {
        Section2(number: "15",
                 title: "Section headers",
                 brief: "A letterspaced micro-label above the content, with an optional trailing text action.") {

            Specimen(label: "Variants") {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    TremorSectionHeader("Objects at risk")
                    TremorSectionHeader("Objects at risk", subtitle: "Ordered by what would hurt most")
                    TremorSectionHeader("Objects at risk", actionTitle: "See all", actionHint: "Opens the full list") {}
                    TremorSectionHeader("Objects at risk",
                                       subtitle: "Ordered by what would hurt most",
                                       actionTitle: "See all") {}
                }
            }
        }
    }
}

// MARK: - 11 Banners

private struct BannerSection: View {
    var body: some View {
        Section2(number: "16",
                 title: "Banners",
                 brief: "Flat tinted plates. A banner is a message about the content, not a peer of it.") {

            Specimen(label: "Kinds", plate: false) {
                VStack(spacing: TremorSpacing.sm) {
                    TremorBanner("Scan complete", message: "18 objects measured.", kind: .success)
                    TremorBanner("Simulation is an estimate",
                                message: "Real shaking varies with your building and soil.",
                                kind: .info)
                    TremorBanner("Two objects could not be measured",
                                message: "Rescan the far wall for a complete report.",
                                kind: .warning)
                    TremorBanner("Couldn’t reach the solver", message: "Check your connection.", kind: .danger)
                    TremorBanner("Draft saved locally", kind: .neutral)
                    TremorBanner("Tip", message: "Anchoring one bookcase drops this room a whole band.", kind: .highlight)
                }
            }

            Specimen(label: "Risk banners", plate: false) {
                VStack(spacing: TremorSpacing.sm) {
                    ForEach(TremorRiskBand.allCases, id: \.self) { band in
                        TremorBanner("\(band.title) risk",
                                    message: "The band name always travels with the colour.",
                                    kind: .risk(band))
                    }
                }
            }

            Specimen(label: "With an action and a dismiss", plate: false) {
                VStack(spacing: TremorSpacing.sm) {
                    TremorBanner("Two objects could not be measured",
                                message: "Rescan the far wall for a complete report.",
                                kind: .warning,
                                actionTitle: "Rescan",
                                action: {})
                    TremorBanner("Draft saved", kind: .neutral, onDismiss: {})
                    TremorBanner("Anchor this first",
                                message: "It is over a bed and it is not secured.",
                                kind: .risk(.severe),
                                actionTitle: "How",
                                action: {},
                                onDismiss: {})
                }
            }
        }
    }
}

// MARK: - 11b Empty states

private struct EmptyStateSection: View {
    var body: some View {
        Section2(number: "17",
                 title: "Empty states",
                 brief: "A symbol in a lavender well, a title, one supporting line, at most one action.") {

            Specimen(label: "With an action", padding: TremorSpacing.lg) {
                TremorEmptyState(title: "No rooms yet",
                                message: "Scan a room and proof will show you what moves in an earthquake.",
                                systemImage: "viewfinder",
                                actionTitle: "Scan a room",
                                actionHint: "Opens the scanner",
                                action: {})
            }

            Specimen(label: "Message only", padding: TremorSpacing.lg) {
                TremorEmptyState(title: "Nothing needs attention",
                                message: "Every object in this room stays put at this intensity.",
                                systemImage: "checkmark.seal")
            }

            Specimen(label: "Title only", padding: TremorSpacing.lg) {
                TremorEmptyState(title: "No results", systemImage: "magnifyingglass")
            }

            Specimen(label: "Custom illustration", padding: TremorSpacing.lg) {
                TremorEmptyState(title: "Simulation failed",
                                message: "The solver ran out of room. Try a smaller scan.",
                                actionTitle: "Try again",
                                action: {}) {
                    TremorSymbolIllustration("exclamationmark.triangle.fill",
                                            tint: TremorColor.danger,
                                            fill: TremorColor.danger.opacity(0.12))
                }
            }
        }
    }
}

// MARK: - 11c Progress

private struct ProgressSection: View {
    @State private var value: Double = 0.42

    var body: some View {
        Section2(number: "18",
                 title: "Progress",
                 brief: "4pt bars and a ring for long jobs. Both go static under Reduce Motion.") {

            Specimen(label: "Bars") {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    TremorProgressBar(value: 0)
                    TremorProgressBar(value: value, label: "Reconstructing", showsValueLabel: true)
                    TremorProgressBar(value: 1, label: "Done", tint: TremorColor.success, showsValueLabel: true)
                    TremorProgressBar(value: 0.68, label: "Severe objects", tint: TremorRiskBand.severe.mark)
                    TremorProgressBar(label: "Solving")
                }
            }

            Specimen(label: "Rings") {
                HStack(alignment: .top, spacing: TremorSpacing.lg) {
                    TremorProgressRing(value: 0.72, caption: "72%", size: 96)
                    TremorProgressRing(value: 1, caption: "Done", size: 96, tint: TremorColor.success)
                    TremorProgressRing(caption: "Solving", size: 96)
                }
                .frame(maxWidth: .infinity)
            }

            Specimen(label: "Drive it", note: "Drag to watch the bar and ring track together.") {
                VStack(spacing: TremorSpacing.md) {
                    TremorSlider(value: $value, in: 0...1, step: 0.01,
                                label: "Progress",
                                valueLabel: { "\(Int($0 * 100))%" })
                    TremorProgressBar(value: value)
                }
            }
        }
    }
}

// MARK: - 11d Toast

private struct ToastSection: View {
    @Binding var toast: TremorToastMessage?

    var body: some View {
        Section2(number: "19",
                 title: "Toast",
                 brief: "Inverse surface, 12pt radius, in over 300ms, auto-dismissing. Swipe up to kill it early.") {

            Specimen(label: "Live · presents at the top of the screen", padding: 0) {
                VStack(spacing: 0) {
                    TremorListRow(title: "Success", leading: .icon("checkmark.circle")) {
                        toast = TremorToastMessage("Room saved")
                    }
                    TremorRowDivider()
                    TremorListRow(title: "Info with a body", leading: .icon("info.circle")) {
                        toast = TremorToastMessage("Simulation queued",
                                                  message: "Results appear as soon as the solver finishes.",
                                                  style: .info)
                    }
                    TremorRowDivider()
                    TremorListRow(title: "Warning", leading: .icon("exclamationmark.triangle")) {
                        toast = TremorToastMessage("Partial scan", message: "One wall is missing.", style: .warning)
                    }
                    TremorRowDivider()
                    TremorListRow(title: "Error, long", leading: .icon("xmark.octagon")) {
                        toast = TremorToastMessage("Couldn’t save the recording",
                                                  message: "proof needs permission to add videos to your photo library.",
                                                  style: .error,
                                                  duration: 5)
                    }
                }
            }

            Specimen(label: "Static · every style", plate: false) {
                VStack(spacing: TremorSpacing.sm) {
                    TremorToast(TremorToastMessage("Room saved"))
                    TremorToast(TremorToastMessage("Simulation queued",
                                                 message: "Results appear as soon as the solver finishes.",
                                                 style: .info))
                    TremorToast(TremorToastMessage("Partial scan", message: "One wall is missing.", style: .warning))
                    TremorToast(TremorToastMessage("Couldn’t save", style: .error))
                }
            }
        }
    }
}

// MARK: - 12 Nav bar

private struct NavBarSection: View {
    var body: some View {
        Section2(number: "20",
                 title: "Top bar",
                 brief: "A 28pt large title collapsing to a 17pt centred one. This screen is wrapped in it.") {

            Specimen(label: "Expanded · collapseProgress 0", padding: 0) {
                TremorNavBar(title: "Your rooms",
                            subtitle: "3 scanned · 7 need attention",
                            collapseProgress: 0,
                            leading: TremorNavBarItem(systemImage: "line.3.horizontal", label: "Menu") {},
                            trailing: TremorNavBarItem(systemImage: "plus", label: "New scan") {})
            }

            Specimen(label: "Half collapsed · 0.5", padding: 0) {
                TremorNavBar(title: "Your rooms",
                            subtitle: "3 scanned · 7 need attention",
                            collapseProgress: 0.5,
                            leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") {},
                            trailing: TremorNavBarItem(systemImage: "ellipsis", label: "More") {})
            }

            Specimen(label: "Collapsed · 1", padding: 0) {
                TremorNavBar(title: "Your rooms",
                            collapseProgress: 1,
                            leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") {},
                            trailing: TremorNavBarItem(systemImage: "ellipsis", label: "More") {})
            }
        }
    }
}

// MARK: - 12b Sheet

private struct SheetSection: View {
    @State private var showsSheet = false
    @State private var showsSheetWithCTA = false

    var body: some View {
        Section2(number: "21",
                 title: "Bottom sheet",
                 brief: "24pt top corners, a 36 × 4 grabber, a docked CTA, and the omnidirectional panel glow.") {

            Specimen(label: "Inline, with a docked CTA", plate: false) {
                TremorSheet(title: "Choose an intensity",
                           subtitle: "How hard should the ground shake?",
                           scrolls: false,
                           action: TremorSheetAction(title: "Reset") {}) {
                    VStack(alignment: .leading, spacing: TremorSpacing.md) {
                        TremorListRow(title: "Mercalli VII",
                                     subtitle: "Very strong · most tall furniture overturns",
                                     leading: .risk(.high),
                                     isSelected: true) {}
                        TremorListRow(title: "Mercalli VI",
                                     subtitle: "Strong · books come off shelves",
                                     leading: .risk(.moderate)) {}
                    }
                } footer: {
                    TremorSheetPrimaryAction(title: "Run the simulation") {}
                }
                .clipShape(RoundedRectangle(cornerRadius: TremorRadius.sheet, style: .continuous))
            }

            Specimen(label: "Modal presentation") {
                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Present a sheet", variant: .secondary) { showsSheet = true }
                    TremorButton("Present with a docked CTA", variant: .secondary) { showsSheetWithCTA = true }
                }
            }
        }
        .tremorSheet(isPresented: $showsSheet,
                    detents: [.medium, .large],
                    title: "About this room",
                    subtitle: "Scanned 2 days ago") {
            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                ForEach(0..<6, id: \.self) { index in
                    TremorListRow(title: "Object \(index + 1)", accessory: .chevron) {}
                }
            }
        }
        .tremorSheet(isPresented: $showsSheetWithCTA,
                    detents: [.medium],
                    title: "Anchor this bookcase") {
            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                TremorBanner("It stands over a bed", kind: .risk(.severe))
                Text("Two L-brackets into studs, 150 mm from each end of the top shelf. Fifteen minutes and about £8.")
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            TremorSheetPrimaryAction(title: "Mark as anchored") { showsSheetWithCTA = false }
        }
    }
}

// MARK: - 13 Risk badges

private struct RiskBadgeSection: View {
    var body: some View {
        Section2(number: "22",
                 title: "Risk badges",
                 brief: "A distinct symbol shape and the band name always travel with the colour.") {

            Specimen(label: "Small · every band") {
                TremorFlowRow {
                    ForEach(RiskBand.allCases) { band in
                        RiskBadge(band, size: .small)
                    }
                }
            }

            Specimen(label: "Large · every band") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { band in
                        RiskBadge(band, size: .large)
                    }
                }
            }

            Specimen(label: "With the recommended action") {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    ForEach(RiskBand.allCases) { band in
                        RiskBadge(band, size: .large, showsAction: true)
                    }
                }
            }

            Specimen(label: "Without the symbol") {
                TremorFlowRow {
                    ForEach(RiskBand.allCases) { band in
                        RiskBadge(band, size: .small, showsSymbol: false)
                    }
                }
            }
        }
    }
}

// MARK: - 13b Score dial

private struct RiskDialSection: View {
    var body: some View {
        Section2(number: "23",
                 title: "Risk score dial",
                 brief: "The room’s headline number. The arc sweeps on appear; the numeral is tabular.") {

            Specimen(label: "Severe · 88", padding: TremorSpacing.lg) {
                RiskScoreDial(score: 88, animatesOnAppear: false)
                    .frame(maxWidth: .infinity)
            }

            Specimen(label: "Every band, compact", padding: TremorSpacing.lg) {
                LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
                    ForEach([12.0, 38.0, 61.0, 92.0], id: \.self) { score in
                        RiskScoreDial(score: score, caption: nil, diameter: 148,
                                      animatesOnAppear: false)
                    }
                }
            }

            Specimen(label: "Edges · 0 and 100", padding: TremorSpacing.lg) {
                HStack(spacing: TremorSpacing.md) {
                    RiskScoreDial(score: 0, caption: nil, diameter: 148, animatesOnAppear: false)
                    RiskScoreDial(score: 100, caption: nil, diameter: 148, animatesOnAppear: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 13c Distribution

private struct DistributionSection: View {
    var body: some View {
        Section2(number: "24",
                 title: "Risk distribution",
                 brief: "One bar for a whole room. Tiny segments lift to a visible minimum so nothing hides.") {

            Specimen(label: "Mixed room, with legend") {
                RiskDistributionBar(counts: [.low: 9, .moderate: 5, .high: 3, .severe: 1])
            }

            Specimen(label: "One severe among many") {
                RiskDistributionBar(counts: [.low: 179, .severe: 1])
            }

            Specimen(label: "Single band") {
                RiskDistributionBar(counts: [.low: 12])
            }

            Specimen(label: "No legend, thicker") {
                RiskDistributionBar(counts: [.low: 4, .moderate: 4, .high: 4, .severe: 4],
                                    showsLegend: false,
                                    height: 16)
            }

            Specimen(label: "Empty") {
                RiskDistributionBar(counts: [:])
            }
        }
    }
}

// MARK: - 13d Factors

private struct FactorSection: View {
    private let contributions: [(label: String, contribution: Double)] = [
        ("Impact energy", 0.26),
        ("Who’s in the way", 0.21),
        ("How far it falls", 0.13),
        ("Blocks your way out", 0.09),
        ("Broken glass", 0.06),
        ("Sheer weight", 0.04),
        ("Fire or flood risk", 0.02),
    ]

    var body: some View {
        Section2(number: "25",
                 title: "Factor breakdown",
                 brief: "Why an object scored what it scored. Never “trust me, it’s a 90”.") {

            Specimen(label: "Full breakdown, banded") {
                FactorBreakdownChart(contributions: contributions, band: .severe)
            }

            Specimen(label: "Top three", note: "Percentages stay shares of the full factor set, so a truncated list correctly does not sum to 100%.") {
                FactorBreakdownChart(contributions: contributions, band: .high, maximumRows: 3)
            }

            Specimen(label: "Brand purple (no band)") {
                FactorBreakdownChart(contributions: Array(contributions.prefix(4)))
            }

            Specimen(label: "Empty") {
                FactorBreakdownChart(contributions: [])
            }
        }
    }
}

// MARK: - 13e Intensity

private struct IntensitySection: View {
    @State private var intensity: MercalliIntensity = .vii

    var body: some View {
        Section2(number: "26",
                 title: "Intensity scale",
                 brief: "Mercalli III–X. Severity is bar height as well as fill, so it survives greyscale.") {

            Specimen(label: "Interactive", padding: TremorSpacing.lg) {
                IntensityScaleView(intensity: intensity) { intensity = $0 }
            }

            Specimen(label: "Display only · weak", padding: TremorSpacing.lg) {
                IntensityScaleView(intensity: .iv)
            }

            Specimen(label: "Display only · extreme", padding: TremorSpacing.lg) {
                IntensityScaleView(intensity: .x)
            }

            Specimen(label: "No readout", padding: TremorSpacing.lg) {
                IntensityScaleView(intensity: .vi, showsReadout: false)
            }
        }
    }
}

// MARK: - 14 Stat tiles

private struct StatTileSection: View {
    var body: some View {
        Section2(number: "27",
                 title: "Stat tiles",
                 brief: "A label, one big tabular number, a unit and a delta. Sentiment colours the delta only.") {

            Specimen(label: "Basic") {
                LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
                    StatTile(label: "Objects", value: "18")
                    StatTile(label: "Peak floor", value: "0.42", unit: "g")
                    StatTile(label: "Time to topple", value: "3.4", unit: "s")
                    StatTile(label: "Heaviest", value: "84", unit: "kg")
                }
            }

            Specimen(label: "With deltas") {
                LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
                    StatTile(label: "At risk", value: "7",
                             delta: .init(text: "+3", direction: .up, sentiment: .negative))
                    StatTile(label: "Secured", value: "11",
                             delta: .init(text: "+4", direction: .up, sentiment: .positive))
                    StatTile(label: "Unchanged", value: "0",
                             delta: .init(text: "no change", direction: .flat, sentiment: .neutral))
                    StatTile(label: "Score", value: "62",
                             delta: .init(text: "−14", direction: .down, sentiment: .positive))
                }
            }

            Specimen(label: "Banded and accented") {
                LazyVGrid(columns: galleryGrid2, spacing: TremorSpacing.md) {
                    StatTile(label: "Room score", value: "88", band: .severe)
                    StatTile(label: "Room score", value: "12", band: .low)
                    StatTile(label: "Centred", value: "4", alignment: .center)
                    StatTile(label: "Accented", value: "9", accent: TremorColor.primary)
                }
            }
        }
    }
}

// MARK: - 14b Thumbnails

private struct ThumbnailSection: View {
    private let types: [ObjectType] = [.bookshelfTall, .television, .refrigerator, .waterHeater, .dresser, .bed]

    var body: some View {
        Section2(number: "28",
                 title: "Object thumbnails",
                 brief: "A symbol per object type in a tinted well, banded once the object has a verdict.") {

            Specimen(label: "By type") {
                TremorFlowRow {
                    ForEach(types) { type in
                        ObjectThumbnail(type: type)
                    }
                }
            }

            Specimen(label: "Banded") {
                TremorFlowRow {
                    ForEach(RiskBand.allCases) { band in
                        ObjectThumbnail(type: .bookshelfTall, band: band)
                    }
                }
            }

            Specimen(label: "Sizes and loading") {
                HStack(alignment: .bottom, spacing: TremorSpacing.md) {
                    ObjectThumbnail(type: .television, size: 40)
                    ObjectThumbnail(type: .television, size: 56)
                    ObjectThumbnail(type: .television, size: 72)
                    ObjectThumbnail(type: .television, size: 56, isLoading: true)
                }
            }
        }
    }
}

// MARK: - 14c Timeline

private struct TimelineSection: View {
    @State private var time: Double = 3.2
    @State private var isPlaying = false

    private var markers: [TimelineScrubber.Marker] {
        [.init(time: 1.8, band: .moderate, label: "Lamp tips"),
         .init(time: 3.4, band: .severe, label: "Bookcase topples"),
         .init(time: 5.1, band: .high, label: "TV falls")]
    }

    var body: some View {
        Section2(number: "29",
                 title: "Timeline scrubber",
                 brief: "The simulation transport. Failure markers sit on the track and tick as you cross them.") {

            Specimen(label: "Interactive, with transport", padding: TremorSpacing.lg) {
                TimelineScrubber(currentTime: time,
                                 duration: 8,
                                 markers: markers,
                                 isPlaying: isPlaying,
                                 onScrub: { time = $0 },
                                 onScrubEnd: { time = $0 },
                                 onPlayPause: { isPlaying.toggle() })
            }

            Specimen(label: "Read-only, no markers", padding: TremorSpacing.lg) {
                TimelineScrubber(currentTime: 2.0, duration: 8)
            }

            Specimen(label: "At the start and the end", padding: TremorSpacing.lg) {
                VStack(spacing: TremorSpacing.lg) {
                    TimelineScrubber(currentTime: 0, duration: 8, markers: markers)
                    TimelineScrubber(currentTime: 8, duration: 8, markers: markers)
                }
            }
        }
    }
}

// MARK: - Colophon

private struct GalleryColophon: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Rectangle()
                .fill(TremorColor.stroke)
                .frame(height: TremorSize.hairline)
                .padding(.bottom, TremorSpacing.xs)
            Text("proof design system")
                .tremorType(.captionEmphasis)
                .foregroundStyle(TremorColor.ink)
            Text("Colour and elevation from Zip. Structure, type discipline and motion from Lyft. Ink #1A0826 · canvas #F1F0EC · primary #6542BE.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, TremorSpacing.xxl)
    }
}

// MARK: - Previews

#Preview("Gallery") {
    DesignSystemGallery()
}

#Preview("Gallery · xxxLarge") {
    DesignSystemGallery()
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Gallery · accessibility3") {
    DesignSystemGallery()
        .environment(\.dynamicTypeSize, .accessibility3)
}
