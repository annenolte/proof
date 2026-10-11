//
//  ShareSheet.swift
//  Tremor — S-21 share and export
//
//  A preview of the card, then the four things a person actually wants to do
//  with a safety report: post the card, send the PDF to a landlord, hand the
//  raw JSON to someone technical, and take the geometry away as USDZ.
//
//  Every export is built off the main actor and every one of them can fail
//  loudly and recoverably. Nothing here silently produces an empty file.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sheet

struct ShareSheet: View {

    let roomID: UUID

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    @State private var model = ShareModel()

    var body: some View {
        TremorSheet(title: "Share this room",
                   subtitle: subtitle,
                   presentation: .modal) {
            content
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TremorRadius.sheet)
        .presentationBackground(TremorColor.surface)
        .task(id: roomID) {
            await model.load(roomID: roomID, env: tremor, appState: appState)
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .ready: return "The card is an image. The report is a PDF anyone can read."
        default: return nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            loadingState

        case .noAssessment:
            TremorEmptyState(
                title: "Nothing to share yet",
                message: "Shake this room first — the card, the report and the data all come from what the earthquake did.",
                systemImage: "square.and.arrow.up",
                actionTitle: "Choose an earthquake",
                action: {
                    appState.stagePhase = .configurator
                    router.dismissSheet()
                })

        case .failed(let message):
            TremorEmptyState(
                title: "We couldn't put this together",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Try again",
                action: { Task { await model.load(roomID: roomID, env: tremor, appState: appState) } })

        case .ready:
            ready
        }
    }

    private var loadingState: some View {
        VStack(spacing: TremorSpacing.lg) {
            RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                .fill(TremorColor.surfaceSunken)
                .aspectRatio(ShareCard.designSize.width / ShareCard.designSize.height,
                             contentMode: .fit)
                .frame(maxWidth: .infinity)
            TremorProgressBar(label: "Drawing your card")
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var ready: some View {
        VStack(spacing: TremorSpacing.xxl) {
            cardPreview

            VStack(spacing: TremorSpacing.sm) {
                if let card = model.cardImage, let url = model.cardURL {
                    ShareLink(item: url,
                              subject: Text(model.shareSubject),
                              message: Text(model.shareMessage),
                              preview: SharePreview(model.shareSubject, image: Image(uiImage: card))) {
                        ShareRowLabel(title: "Share the card",
                                      subtitle: "A 1080 × 1920 image, ready for anywhere.",
                                      systemImage: "photo",
                                      isPrimary: true)
                    }
                    .accessibilityHint("Opens the share sheet with the card image")
                }

                exportRows
            }

            if let note = model.offlineNote {
                Text(note)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Your scan never leaves this phone unless you send it. Nothing here is uploaded.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cardPreview: some View {
        if let card = model.cardImage {
            Image(uiImage: card)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                        .strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline)
                }
                .tremorShadow(.raised)
                .accessibilityLabel(model.cardDescription)
        } else {
            TremorBanner("The card didn't draw",
                        message: "Everything else here still works. Try again if you want the image.",
                        kind: .warning,
                        actionTitle: "Try again",
                        action: { Task { await model.redrawCard() } })
        }
    }

    @ViewBuilder
    private var exportRows: some View {
        if let pdf = model.pdf {
            ShareLink(item: pdf, preview: SharePreview(pdf.title)) {
                ShareRowLabel(title: "Export the report",
                              subtitle: "\(model.pdfPageCount) pages · PDF · everything, with the maths.",
                              systemImage: "doc.richtext")
            }
            .accessibilityHint("Opens the share sheet with the PDF report")
        } else if model.isBuildingPDF {
            ShareRowPlaceholder(title: "Export the report", subtitle: "Building the PDF…")
        }

        if let json = model.json {
            ShareLink(item: json, preview: SharePreview(json.filename)) {
                ShareRowLabel(title: "Export the data",
                              subtitle: "JSON · every measurement and every score.",
                              systemImage: "curlybraces")
            }
            .accessibilityHint("Opens the share sheet with the raw data")
        }

        if let usdz = model.usdzURL {
            ShareLink(item: usdz, preview: SharePreview(usdz.lastPathComponent)) {
                ShareRowLabel(title: "Export the room",
                              subtitle: "USDZ · opens in Quick Look and any 3D tool.",
                              systemImage: "cube")
            }
            .accessibilityHint("Opens the share sheet with the 3D model")
        } else {
            ShareRowPlaceholder(
                title: "Export the room",
                subtitle: model.usdzUnavailableReason)
        }
    }
}

// MARK: - Rows

/// The label inside a `ShareLink`. A `ShareLink` supplies its own button
/// behaviour, so this is only ever the plate.
struct ShareRowLabel: View {

    let title: String
    let subtitle: String
    let systemImage: String
    var isPrimary: Bool = false

    var body: some View {
        HStack(spacing: TremorSpacing.md) {
            Image(systemName: systemImage)
                .font(TremorFont.title3)
                .foregroundStyle(isPrimary ? TremorColor.onPrimary : TremorColor.primary)
                .frame(width: TremorSpacing.xxxl, height: TremorSpacing.xxxl)
                .background(isPrimary ? TremorColor.primary : TremorColor.primarySoft,
                            in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail,
                                                 style: .continuous))

            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)

            Image(systemName: "square.and.arrow.up")
                .font(TremorFont.subheadline)
                .foregroundStyle(TremorColor.inkTertiary)
        }
        .padding(TremorSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TremorColor.surface,
                    in: RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                .strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline)
        }
        .contentShape(Rectangle())
    }
}

/// The same plate, greyed, for an export that is not available. It always says
/// *why*, because a disabled row with no reason is a dead end.
struct ShareRowPlaceholder: View {

    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: TremorSpacing.md) {
            ProgressView()
                .controlSize(.small)
                .tint(TremorColor.inkTertiary)
                .frame(width: TremorSpacing.xxxl, height: TremorSpacing.xxxl)
                .background(TremorColor.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail,
                                                 style: .continuous))
            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.inkTertiary)
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TremorSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TremorColor.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Model

@MainActor
@Observable
final class ShareModel {

    enum Phase: Equatable {
        case loading
        case ready
        case noAssessment
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var room: ScannedRoom?
    private(set) var assessment: RoomAssessment?

    private(set) var cardImage: UIImage?
    private(set) var cardURL: URL?
    private(set) var pdf: SafetyReportPDF?
    private(set) var pdfPageCount: Int = 0
    private(set) var isBuildingPDF = false
    private(set) var json: AssessmentJSONExport?
    private(set) var usdzURL: URL?
    private(set) var isOnline = true

    @ObservationIgnored private var env: TremorEnvironment?

    init() {}

    func load(roomID: UUID, env: TremorEnvironment, appState: AppState) async {
        self.env = env
        phase = .loading

        // The open room is almost always the one being shared; only fall back to
        // the store when this sheet was raised from somewhere else.
        let room: ScannedRoom
        if let open = appState.room, open.id == roomID {
            room = open
        } else {
            do {
                room = try await env.rooms.load(id: roomID)
            } catch {
                phase = .failed(AppState.message(for: error))
                return
            }
        }
        self.room = room
        self.isOnline = env.network.isOnline

        let assessment: RoomAssessment?
        if let open = appState.assessment, open.roomID == roomID {
            assessment = open
        } else {
            assessment = await env.rooms.latestAssessment(for: roomID)
        }

        guard let assessment else {
            self.assessment = nil
            phase = .noAssessment
            return
        }
        self.assessment = assessment
        phase = .ready

        usdzURL = await env.rooms.usdzURL(for: roomID)
        await redrawCard()
        await buildDocuments(room: room, assessment: assessment)
    }

    /// Draws the card. Separated so the "try again" on a failed render does not
    /// rebuild the PDF too.
    func redrawCard() async {
        guard let room, let assessment else { return }
        cardImage = ShareCardRenderer.image(room: room, assessment: assessment)
        cardURL = try? ShareCardRenderer.writePNG(room: room, assessment: assessment)
    }

    private func buildDocuments(room: ScannedRoom, assessment: RoomAssessment) async {
        isBuildingPDF = true
        defer { isBuildingPDF = false }

        let built = await Task.detached(priority: .userInitiated) {
            let report = ReportBuilder().build(room: room, assessment: assessment)
            let renderer = PDFRenderer()
            let pdf = ShareExport.pdf(report, renderer: renderer)
            let pages = renderer.pageCount(of: report)
            let json = try? ShareExport.json(room: room, assessment: assessment, report: report)
            return (pdf: pdf, pages: pages, json: json)
        }.value

        pdf = built.pdf
        pdfPageCount = built.pages
        json = built.json
    }

    // MARK: Copy

    var shareSubject: String {
        guard let room, let assessment else { return "proof" }
        let name = room.name.isEmpty ? room.kind.displayName : room.name
        return "\(name) — \(assessment.overallBand.displayName) earthquake risk"
    }

    var shareMessage: String {
        guard let assessment else { return "Checked with proof." }
        let hazards = assessment.risksNeedingAction.count
        if hazards == 0 {
            return "I checked this room for earthquake safety with proof — nothing falls."
        }
        return "I checked this room for earthquake safety with proof. "
            + "\(hazards) \(hazards == 1 ? "thing" : "things") would come down at intensity "
            + "\(assessment.intensity.roman)."
    }

    var cardDescription: String {
        guard let room, let assessment else { return "Share card" }
        let name = room.name.isEmpty ? room.kind.displayName : room.name
        return "Share card for \(name). "
            + assessment.overallBand.spokenScore(assessment.overallScore)
            + ". \(assessment.risksNeedingAction.count) things need attention."
    }

    var usdzUnavailableReason: String {
        guard room != nil else { return "Not available." }
        return "This room has no 3D file — it was built from measurements rather than a mesh."
    }

    /// Offline changes nothing here: every export is built on the phone. Say so
    /// once, quietly, rather than blocking anything.
    var offlineNote: String? {
        isOnline ? nil : "You're offline. Everything on this screen is made on your phone, so it all still works."
    }
}

// MARK: - Previews

#Preview("S-21 — hazards") {
    SharePreviewHost()
}

#Preview("S-21 — nothing to share yet") {
    SharePreviewHost(assess: false)
}

struct SharePreviewHost: View {

    var room: ScannedRoom = RoomFixtures.dangerousBedroom
    var assess: Bool = true

    @State private var env = TremorEnvironment.makePreview()
    @State private var router = Router()
    @State private var appState: AppState?

    var body: some View {
        Group {
            if let appState {
                ShareSheet(roomID: room.id)
                    .environment(\.tremor, env)
                    .environment(router)
                    .environment(appState)
            } else {
                ProgressView().tremorScreen()
            }
        }
        .task {
            let state = AppState(env: env)
            state.adopt(room: room,
                        assessment: assess ? env.risk.assess(room: room, intensity: .viii) : nil)
            appState = state
        }
    }
}
