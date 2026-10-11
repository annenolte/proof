//
//  MethodView.swift
//  Tremor — Features / Library (S-20)
//
//  "How we know." The screen that decides whether anyone believes the rest of
//  the app.
//
//  It is reachable from every "?" in Tremor, so it has to work as a destination
//  and as a reference: long-form prose set generously, every claim carrying a
//  superscript that resolves to a real paper or standard, and four figures the
//  reader can actually touch — the intensity ladder, the floor amplification,
//  the rocking threshold and the scoring rubric. The last section is the one
//  that matters most: what we are *not* sure about, stated plainly, before
//  anyone has to find it out for themselves.
//
//  This file also holds the three short reference screens that hang off the same
//  part of Settings — the bibliography, privacy, and licences — because they are
//  the same kind of page and share the same typography.
//

import SwiftUI

// MARK: - S-20

struct MethodView: View {

    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var collapse: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "How proof works",
                collapseProgress: collapse,
                leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") { router.pop() },
                trailing: TremorNavBarItem(systemImage: "book", label: "Sources") { router.push(.sources) })

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xxl) {
                    intro

                    ForEach(MethodLibrary.sections) { section in
                        MethodSectionView(section: section) { router.push(.sources) }
                    }

                    closing
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.section)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let distance = TremorNavBar.largeTitleHeight(
                    hasSubtitle: false, dynamicTypeSize: dynamicTypeSize)
                collapse = distance > 0 ? min(1, max(0, Double(offset / distance))) : 0
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text("proof doesn't guess. Everything it tells you comes from published earthquake engineering, and this page shows you exactly which parts.")
                .tremorType(.title3)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Numbers in small type link to the source they came from. There are \(MethodLibrary.all.count) of them.")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TremorSpacing.xs)
    }

    private var closing: some View {
        TremorCard(padding: TremorSpacing.xl, fill: TremorColor.primarySoft, shadow: nil) {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("Read the sources")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                Text("Every paper and standard above, with a line on what we take from each one.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TremorButton("Sources and citations",
                            variant: .secondary,
                            size: .medium,
                            trailingIcon: "arrow.right") {
                    router.push(.sources)
                }
                .padding(.top, TremorSpacing.xs)
            }
        }
    }
}

// MARK: - Section

/// One section of the explainer: a heading, its paragraphs with superscripts,
/// its figure, and a row of tappable source numbers.
struct MethodSectionView: View {

    var section: MethodSection
    var onOpenSources: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            Text(section.title)
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    MethodParagraphView(paragraph: paragraph)
                }
            }

            figure

            if !section.citationIDs.isEmpty {
                MethodSourceChips(ids: section.citationIDs, action: onOpenSources)
            }
        }
    }

    @ViewBuilder
    private var figure: some View {
        switch section.figure {
        case .none:
            EmptyView()
        case .intensityTable:
            IntensityLadderFigure()
        case .floorAmplification:
            FloorAmplificationFigure()
        case .rockingThreshold:
            RockingThresholdFigure()
        case .rubric:
            RubricFigure()
        }
    }
}

/// A paragraph with its superscript markers.
///
/// The markers are typographic, not interactive — an 11pt tap target inside a
/// line of body text is not a control anyone can hit, and VoiceOver would read
/// it as a bare digit. The tappable affordance is the source-chip row under the
/// section, which says "Source 7" out loud.
struct MethodParagraphView: View {

    var paragraph: MethodParagraph

    var body: some View {
        (Text(paragraph.text) + markerText)
            .tremorType(.body)
            .foregroundStyle(TremorColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(paragraph.text)
    }

    private var markerText: Text {
        guard let marker = paragraph.marker else { return Text("") }
        return Text(" \(marker)")
            .font(TremorFont.font(.caption))
            .baselineOffset(Metric.superscriptRise)
            .foregroundColor(TremorColor.primary)
    }

    private enum Metric {
        /// Half the caption line height, which lands the digit on the cap line
        /// of the body text it follows.
        static let superscriptRise: CGFloat = TremorSpacing.xs
    }
}

/// The tappable "sources" row under a section.
struct MethodSourceChips: View {

    var ids: [String]
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TremorSpacing.xs) {
            Text("Sources")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)

            ForEach(ids, id: \.self) { id in
                if let number = MethodLibrary.number(for: id),
                   let citation = MethodLibrary.citation(id) {
                    Button(action: action) {
                        Text("\(number)")
                            .tremorType(.captionEmphasis, numeric: true)
                            .foregroundStyle(TremorColor.primary)
                            .frame(minWidth: TremorSpacing.xl, minHeight: TremorSpacing.xl)
                            .background(TremorColor.primarySoft, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Source \(number): \(citation.title)")
                    .accessibilityHint("Opens the full list of sources")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, TremorSpacing.xxs)
    }
}

// MARK: - Figure: intensity ladder

/// The MMI table: numeral, plain-English name, and the acceleration each level
/// actually runs at.
struct IntensityLadderFigure: View {

    private static let levels = MercalliIntensity.allCases

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("The scale, and what each level runs at")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)

                ForEach(Self.levels) { level in
                    HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
                        Text(level.roman)
                            .tremorType(.subheadline, numeric: true)
                            .foregroundStyle(TremorColor.primary)
                            .frame(width: Metric.numeralWidth, alignment: .leading)

                        Text(level.shakingLabel)
                            .tremorType(.callout)
                            .foregroundStyle(TremorColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(String(format: "%.2f g", level.representativePGAInG))
                            .tremorType(.footnote, numeric: true)
                            .foregroundStyle(TremorColor.inkTertiary)
                    }
                    .padding(.vertical, TremorSpacing.hair)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Intensity \(level.roman), \(level.shakingLabel), about \(String(format: "%.2f", level.representativePGAInG)) g")
                }

                Text("g is the acceleration of gravity. At 1 g, sideways, an unanchored object is thrown.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.xxs)
            }
        }
    }

    private enum Metric {
        static let numeralWidth: CGFloat = TremorSpacing.xxxl
    }
}

// MARK: - Figure: floor amplification

/// Two steppers and a live H_f. The point is that the reader can put their own
/// building in and watch the number move.
struct FloorAmplificationFigure: View {

    @State private var floor = 3
    @State private var storeys = 5

    private var factor: Double {
        IntensityScale.floorAmplification(floor: floor, totalStoreys: storeys)
    }

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text("Try your own building")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)

                TremorStepper("Which floor", value: floorBinding, in: 0...(max(1, storeys) - 1),
                             format: { ScanSetupCopy.floorLabel($0) })
                TremorRowDivider(leadingInset: 0)
                TremorStepper("Floors in total", value: storeysBinding, in: 1...Metric.maximumStoreys)

                HStack(alignment: .center, spacing: TremorSpacing.md) {
                    FloorDiagram(floor: floor, totalStoreys: storeys)

                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        Text(String(format: "%.1f×", factor))
                            .tremorType(.displayM, numeric: true)
                            .foregroundStyle(TremorColor.primary)
                        Text("as hard as the ground shakes")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, TremorSpacing.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Amplification")
                .accessibilityValue(String(format: "%.1f times the ground motion", factor))
            }
        }
    }

    private var floorBinding: Binding<Int> {
        Binding(get: { floor }, set: { floor = min($0, max(0, storeys - 1)) })
    }

    private var storeysBinding: Binding<Int> {
        Binding(get: { storeys }, set: {
            storeys = $0
            floor = min(floor, max(0, $0 - 1))
        })
    }

    private enum Metric {
        static let maximumStoreys = 40
    }
}

// MARK: - Figure: rocking threshold

/// The slenderness slider. Drag it and watch the acceleration a thing tips at
/// collapse from "you'd never feel it" to "nothing short of a disaster".
struct RockingThresholdFigure: View {

    /// Height of the centre of mass over half-width. 1 is a cube on its side;
    /// 8 is a very tall, narrow shelf.
    @State private var slenderness: Double = 4

    /// a_rock / g = b / h_cm = 1 / slenderness (Housner 1963).
    private var thresholdInG: Double { 1.0 / max(slenderness, 0.5) }

    private var intensity: MercalliIntensity {
        IntensityScale.bin(forPGAInG: thresholdInG)
    }

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text("How slender is it?")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)

                HStack(alignment: .bottom, spacing: TremorSpacing.lg) {
                    SlendernessSilhouette(slenderness: slenderness)

                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        Text(String(format: "%.2f g", thresholdInG))
                            .tremorType(.displayM, numeric: true)
                            .foregroundStyle(LibraryBandPalette.mark(band))
                        Text("starts it rocking")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                        Text("That's about intensity \(intensity.roman) — \(intensity.shakingLabel.lowercased()) shaking.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                TremorSlider(
                    value: $slenderness,
                    in: 1...8,
                    step: 0.5,
                    label: "Height over half-width",
                    minimumLabel: "Squat",
                    maximumLabel: "Very tall",
                    valueLabel: { String(format: "%.1f : 1", $0) },
                    band: { value in LibraryBandPalette.tremorBand(RiskBand(score: min(100, (value - 1) / 7 * 100))) })

                Text("A chest of drawers is about 2 : 1. A tall bookcase is 5 : 1 or worse. This is the single number that decides most of it — which is why loading the heavy things onto the bottom shelf, which lowers the centre of mass, is the cheapest fix there is.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var band: RiskBand {
        // Slenderer is worse: a low tipping threshold is a high risk.
        RiskBand(score: max(0, min(100, (1 - thresholdInG) * 100)))
    }
}

/// A simple block whose proportions follow the slider, so the number has a
/// shape attached to it.
struct SlendernessSilhouette: View {

    var slenderness: Double

    var body: some View {
        let height = Metric.maximumHeight
        let width = max(Metric.minimumWidth, height / max(slenderness, 0.5))
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
                .fill(TremorColor.primary.opacity(0.24))
                .overlay {
                    RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
                        .strokeBorder(TremorColor.primary, lineWidth: TremorSize.hairline)
                }
                .frame(width: width, height: height)
        }
        .frame(width: Metric.maximumHeight, height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private enum Metric {
        static let maximumHeight: CGFloat = 96
        static let minimumWidth: CGFloat = TremorSpacing.sm
    }
}

// MARK: - Figure: rubric

/// The seven consequence factors and their weights, straight from the engine so
/// the page cannot drift from the code.
struct RubricFigure: View {

    private static let rows: [(label: String, weight: Double, detail: String)] = {
        let w = ConsequenceBreakdown.weights
        return [
            ("Impact energy", w.impactEnergy, "How much energy it lands with — its weight times how far its centre falls."),
            ("Who's in the way", w.occupantExposure, "Whether a bed, a sofa or a cot is inside its reach."),
            ("How far it falls", w.fallHeight, "Something toppling from head height does more than something toppling from knee height."),
            ("Blocks your way out", w.egressBlockage, "Whether it lands across a door or a hallway."),
            ("Broken glass", w.breakage, "Glass doors, mirrors and screens that shatter on impact."),
            ("Sheer weight", w.mass, "Mass on its own, because heavy things pin people."),
            ("Fire or flood", w.secondaryHazard, "Gas lines, water lines and live electrical connections."),
        ]
    }()

    private var maximumWeight: Double {
        Self.rows.map(\.weight).max() ?? 1
    }

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text("The seven factors, and what each is worth")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)

                ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                            Text(row.label)
                                .tremorType(.callout)
                                .foregroundStyle(TremorColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(Int((row.weight * 100).rounded()))%")
                                .tremorType(.footnote, numeric: true)
                                .foregroundStyle(TremorColor.inkTertiary)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TremorColor.surfaceSunken)
                                Capsule()
                                    .fill(TremorColor.primary)
                                    .frame(width: geometry.size.width * row.weight / maximumWeight)
                            }
                        }
                        .frame(height: TremorSpacing.xxs)

                        Text(row.detail)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, TremorSpacing.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.label), \(Int((row.weight * 100).rounded())) percent. \(row.detail)")
                }
            }
        }
    }
}

// MARK: - Sources

/// The bibliography. Every entry says what Tremor takes from it, because a list
/// of references nobody can act on is decoration.
struct SourcesView: View {

    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Sources",
                leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") { router.pop() })

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    Text("Everything in proof rests on these. Where a source is public, tapping it opens the paper or the standard.")
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, TremorSpacing.xs)

                    ForEach(MethodLibrary.all) { citation in
                        CitationRow(citation: citation) { url in openURL(url) }
                    }
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.top, TremorSpacing.xs)
                .padding(.bottom, TremorSpacing.section)
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
    }
}

struct CitationRow: View {

    var citation: Citation
    var onOpen: (URL) -> Void

    private var number: Int { MethodLibrary.number(for: citation.id) ?? 0 }

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                Text("\(number)")
                    .tremorType(.captionEmphasis, numeric: true)
                    .foregroundStyle(TremorColor.primary)
                    .frame(width: TremorSpacing.xl, height: TremorSpacing.xl)
                    .background(TremorColor.primarySoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(citation.reference)
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(citation.usedFor)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let url = citation.url {
                        Button {
                            onOpen(url)
                        } label: {
                            HStack(spacing: TremorSpacing.xxs) {
                                Text("Read it")
                                    .tremorType(.subheadline)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                            }
                            .foregroundStyle(TremorColor.primary)
                            .frame(minHeight: TremorSize.minimumTapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Read \(citation.title)")
                        .accessibilityHint("Opens the publisher's page in Safari")
                    } else {
                        Text("Not available online.")
                            .tremorType(.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .padding(.top, TremorSpacing.xxs)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source \(number)")
    }
}

// MARK: - Privacy

struct PrivacyView: View {

    @Environment(Router.self) private var router

    var body: some View {
        ReferencePage(title: "Privacy", blocks: Self.blocks) { router.pop() }
    }

    static let blocks: [ReferenceBlock] = [
        ReferenceBlock(
            heading: "The short version",
            body: "Your scans, your reports and your fix-it plans live on your iPhone. proof has no server of its own, no analytics, and no advertising. Nothing about your home is transmitted anywhere unless you switch on smarter object details, and even then it's one cropped photo of one piece of furniture at a time."),
        ReferenceBlock(
            heading: "What the camera does",
            body: "Scanning uses the camera and the LiDAR sensor to measure the shape of the room. Frames are processed on the phone as they arrive and are not recorded. What we keep is a small cropped photo of each object we found — so you can see what we identified — and the room's geometry."),
        ReferenceBlock(
            heading: "Smarter object details",
            body: "If you turn it on, a cropped photo of each object is sent to OpenAI along with its size in centimetres and the category the scanner guessed. That's the whole request: no name, no account, no location, no floor plan, and never a full camera frame. The photo is stripped of its metadata first, and requests are marked so they aren't used for training."),
        ReferenceBlock(
            heading: "Your account",
            body: "Signing in with Apple stores an anonymous identifier and, if you shared them, a display name and a relay email. You can use every part of proof without an account — nothing is held back."),
        ReferenceBlock(
            heading: "Getting it all back, or getting rid of it",
            body: "Settings has \"Export everything\", which hands you one self-contained file per room, and \"Delete all rooms\", which removes them. Deleting the app removes everything else with it."),
    ]
}

// MARK: - Licences

struct LicencesView: View {

    @Environment(Router.self) private var router

    var body: some View {
        ReferencePage(title: "Licences", blocks: Self.blocks) { router.pop() }
    }

    static let blocks: [ReferenceBlock] = [
        ReferenceBlock(
            heading: "Inter",
            body: "Copyright 2016 The Inter Project Authors. Licensed under the SIL Open Font License, Version 1.1. Used for every text size in proof."),
        ReferenceBlock(
            heading: "Instrument Sans",
            body: "Copyright 2022 The Instrument Sans Project Authors. Licensed under the SIL Open Font License, Version 1.1. Used for every display size in proof."),
        ReferenceBlock(
            heading: "SF Symbols",
            body: "Apple SF Symbols are used under the Apple licence terms, in Apple software on Apple platforms only."),
        ReferenceBlock(
            heading: "FEMA E-74 and FEMA 528",
            body: "Published by the Federal Emergency Management Agency and in the public domain as United States government works. proof's mitigation advice is derived from them."),
        ReferenceBlock(
            heading: "USGS ShakeMap",
            body: "Intensity and ground-motion tables published by the United States Geological Survey, in the public domain as United States government works."),
        ReferenceBlock(
            heading: "Everything else",
            body: "The physics, the risk engine, the design system and the app are proof's own work. No third-party frameworks are linked into this app beyond Apple's own."),
    ]
}

// MARK: - Reference page

/// A heading-and-paragraph reference screen. Privacy and Licences are the same
/// page with different words, so they are the same view.
struct ReferenceBlock: Identifiable, Hashable, Sendable {
    var id: String { heading }
    let heading: String
    let body: String
}

struct ReferencePage: View {

    var title: String
    var blocks: [ReferenceBlock]
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: title,
                leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back", action: onBack))

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            Text(block.heading)
                                .tremorType(.title3)
                                .foregroundStyle(TremorColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            Text(block.body)
                                .tremorType(.body)
                                .foregroundStyle(TremorColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.top, TremorSpacing.xs)
                .padding(.bottom, TremorSpacing.section)
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
    }
}

// MARK: - Previews

#Preview("S-20 — method") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings, path: [.method])
}

#Preview("S-20 — accessibility 3") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings, path: [.method])
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Sources") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings, path: [.sources])
}

#Preview("Privacy") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings, path: [.privacy])
}

#Preview("Licences") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings, path: [.licences])
}

#Preview("Figures") {
    ScrollView {
        VStack(spacing: TremorSpacing.xl) {
            IntensityLadderFigure()
            FloorAmplificationFigure()
            RockingThresholdFigure()
            RubricFigure()
        }
        .padding(TremorSpacing.pageInset)
    }
    .tremorScreen(inset: 0)
}
