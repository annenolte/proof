//
//  ShareCard.swift
//  Tremor — S-21 the shareable card
//
//  A 1080 × 1920 card: the room, its verdict, the three things most likely to
//  hurt someone, and the wordmark. It is the only artwork in the app that gets
//  Zip's hard offset shadow, and the only place the yuzu accent is allowed to
//  carry an entire block.
//
//  Rendered off-screen with `ImageRenderer` at a fixed 1080 × 1920 so it looks
//  the same whatever phone made it — a share card that reflows with Dynamic Type
//  is a share card that arrives broken.
//

import SwiftUI

// MARK: - Card

struct ShareCard: View {

    /// The card's design size in points. Rendered at 1080 × 1920 by scaling ×3.
    static let designSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    let roomName: String
    let roomKind: RoomKind
    let intensity: MercalliIntensity
    let score: Double
    let band: RiskBand
    let counts: [RiskBand: Int]
    let hazards: [(name: String, verdict: String, band: RiskBand, symbol: String)]
    let objectCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            verdict
            Spacer(minLength: TremorSpacing.md)
            hazardList
            Spacer(minLength: TremorSpacing.md)
            wordmark
        }
        .padding(TremorSpacing.xxl)
        .frame(width: Self.designSize.width, height: Self.designSize.height, alignment: .topLeading)
        .background(TremorColor.canvas)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text("Earthquake check")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            Text(roomName)
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("\(objectCount) things checked at intensity \(intensity.roman) — \(intensity.shakingLabel.lowercased()) shaking")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            // The badge sits on its own line rather than beside the numeral.
            // At the card's fixed 360pt width a large badge and a 48pt numeral
            // are within a few points of the available run, and the loser gets
            // truncated to an ellipsis — which is how the score came out as
            // three boxes the first time this was drawn.
            RiskBadge(band, size: .large)

            HStack(alignment: .lastTextBaseline, spacing: TremorSpacing.xs) {
                Text(FindingsFormat.score(score))
                    .tremorType(.displayXL)
                    .foregroundStyle(band.bandMark)
                    .fixedSize()
                Text("out of 100")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize()
                Spacer(minLength: 0)
            }

            RiskDistributionBar(counts: counts, showsLegend: true)
        }
        .padding(TremorSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Zip §6's hard offset shadow: no blur, brand aubergine. Reserved for
        // the onboarding hero and this card, and used nowhere else.
        //
        // Drawn as a second plate behind the first rather than with `.shadow`:
        // a zero-blur shadow on a view containing text renders every glyph a
        // second time in ink, which reads as a printing fault.
        .background(alignment: .topLeading) { plate }
        .padding(.top, TremorSpacing.xl)
        // The offset plate reaches 12pt past the bottom edge; without this the
        // next section sits on top of it.
        .padding(.bottom, TremorSpacing.lg)
        .padding(.horizontal, TremorSpacing.sm)
    }

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
        return ZStack {
            shape.fill(TremorColor.ink)
                .offset(x: -TremorSpacing.sm, y: TremorSpacing.sm)
            shape.fill(TremorColor.surface)
        }
    }

    @ViewBuilder
    private var hazardList: some View {
        if hazards.isEmpty {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("Nothing falls")
                    .tremorType(.title2)
                    .foregroundStyle(TremorColor.ink)
                Text("At this strength of shaking everything in this \(roomKind.displayName.lowercased()) stays where it is.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Text("Worst offenders")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)

                ForEach(Array(hazards.enumerated()), id: \.offset) { pair in
                    HStack(spacing: TremorSpacing.sm) {
                        Image(systemName: pair.element.symbol)
                            .font(TremorFont.title3)
                            .foregroundStyle(pair.element.band.bandMark)
                            .frame(width: TremorSpacing.xxxl, height: TremorSpacing.xxxl)
                            .background(pair.element.band.bandSurface,
                                        in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail,
                                                             style: .continuous))

                        VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                            Text(pair.element.name)
                                .tremorType(.bodyEmphasis)
                                .foregroundStyle(TremorColor.ink)
                                .lineLimit(1)
                            Text(pair.element.verdict)
                                .tremorType(.footnote)
                                .foregroundStyle(TremorColor.inkSecondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(pair.element.band.displayName)
                            .tremorType(.captionEmphasis)
                            .foregroundStyle(pair.element.band.bandMark)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private var wordmark: some View {
        HStack(spacing: TremorSpacing.xs) {
            Image(systemName: "waveform.path")
                .font(TremorFont.subheadline)
                .foregroundStyle(TremorColor.ink)
            Text("proof")
                .tremorType(.title3)
                .foregroundStyle(TremorColor.ink)
            Spacer(minLength: 0)
            Text("Scanned with LiDAR · scored to FEMA E-74")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
        }
        .padding(.top, TremorSpacing.md)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TremorColor.stroke)
                .frame(height: TremorSize.hairline)
        }
    }
}

// MARK: - Building one

extension ShareCard {

    /// Builds the card from a room and its verdict. Pure, so the renderer and
    /// the tests see exactly the same content.
    init(room: ScannedRoom, assessment: RoomAssessment, topHazards: Int = 3) {
        let ranked = assessment.objectRisks
            .filter { $0.band >= .moderate }
            .sorted { $0.score > $1.score }
            .prefix(topHazards)

        self.init(
            roomName: room.name.isEmpty ? room.kind.displayName : room.name,
            roomKind: room.kind,
            intensity: assessment.intensity,
            score: assessment.overallScore,
            band: assessment.overallBand,
            counts: assessment.counts,
            hazards: ranked.map { risk in
                let object = room.object(id: risk.objectID)
                return (name: object?.type.displayName ?? "Object",
                        verdict: object.map { ReportBuilder.headline(risk: risk, object: $0) }
                            ?? risk.reasons.first ?? "At risk",
                        band: risk.band,
                        symbol: object?.type.symbolName ?? "shippingbox")
            },
            objectCount: room.objects.count)
    }
}

// MARK: - Renderer

/// Rasterises the card at share resolution, off the main thread's critical path.
@MainActor
enum ShareCardRenderer {

    /// 1080 × 1920, the size every social surface wants.
    static var pixelSize: CGSize {
        CGSize(width: ShareCard.designSize.width * ShareCard.renderScale,
               height: ShareCard.designSize.height * ShareCard.renderScale)
    }

    /// Renders the card. Returns `nil` only if the renderer itself fails, which
    /// the caller shows as a retryable error rather than an empty frame.
    static func image(room: ScannedRoom, assessment: RoomAssessment) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(room: room, assessment: assessment))
        renderer.scale = ShareCard.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Writes the card to a temporary PNG, for the share paths that need a file.
    static func writePNG(room: ScannedRoom, assessment: RoomAssessment) throws -> URL {
        guard let image = image(room: room, assessment: assessment),
              let data = image.pngData()
        else { throw ShareCardError.renderFailed }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TremorExports/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = room.name.isEmpty ? "Room" : room.name
        let url = directory.appendingPathComponent("\(name) — proof.png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum ShareCardError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        "We couldn't draw the card. Everything else about this report is fine — try again, or export the PDF instead."
    }
}

// MARK: - Previews

#Preview("Share card — hazards") {
    ShareCard(room: RoomFixtures.dangerousBedroom,
              assessment: RiskEngine().assess(room: RoomFixtures.dangerousBedroom, intensity: .viii))
        .scaleEffect(0.9)
}

#Preview("Share card — nothing falls") {
    ShareCard(room: RoomFixtures.safeLivingRoom,
              assessment: RiskEngine().assess(room: RoomFixtures.safeLivingRoom, intensity: .vi))
        .scaleEffect(0.9)
}
