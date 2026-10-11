//
//  DemoRoomsView.swift
//  Tremor — Features / Onboarding — S-08
//
//  The screen a phone without a LiDAR scanner sees. SPEC §1.4 S-08: **not a
//  dead end.**
//
//  The temptation here is to write an apology. That would be the wrong product:
//  scanning is one of five stages, and the other four — object understanding,
//  the physics, the risk scoring, the fix-it plan — run identically on any
//  iPhone. So this screen says which devices have the sensor, plainly and once,
//  and then hands over three fully-populated rooms from `RoomFixtures` that go
//  through the *real* pipeline. Nothing downstream knows or cares that the
//  geometry came from a bundle rather than from a camera.
//

import SwiftUI

// MARK: - The catalogue

/// One offer on S-08: a bundled room, and the reason to pick it.
struct DemoRoomOption: Identifiable, Equatable {

    let room: ScannedRoom
    /// One sentence about what makes this room worth looking at. Written to be
    /// honest about the outcome — the living room is here precisely because
    /// almost nothing in it moves.
    let blurb: String
    /// Set on exactly one option, and it is the one that makes the point.
    let isRecommended: Bool

    var id: UUID { room.id }

    var name: String { room.name }

    /// Floor area in m², from the room's own floor surface.
    var floorArea: Double {
        guard let floor = room.surfaces.first(where: { $0.kind == .floor }) else { return 0 }
        return Double(floor.extents.width) * Double(floor.extents.depth)
    }

    /// "9 things · 15 m²". The building context matters to the physics but not
    /// to the choice being made here, so it stays off the card and keeps the
    /// line to one row.
    var metadata: String {
        let things = room.objects.count == 1 ? "1 thing" : "\(room.objects.count) things"
        guard floorArea > 0 else { return things }
        return things + " · " + String(format: "%.0f m²", floorArea)
    }
}

/// The three rooms S-08 offers, and the quality report a bundled room carries
/// into the rest of the pipeline.
///
/// Three, not five: the library ships five fixtures, but a first-run screen that
/// asks for a decision between five unfamiliar options gets a slower decision
/// and a worse one. These three are the extremes — the dangerous room, the safe
/// room, and the one full of regulated appliances.
enum DemoRoomCatalogue {

    static var all: [DemoRoomOption] {
        [
            DemoRoomOption(
                room: RoomFixtures.dangerousBedroom,
                blurb: "A loaded bookcase within falling distance of the pillow, and a picture hung over the bed. The room that surprises people.",
                isRecommended: true),
            DemoRoomOption(
                room: RoomFixtures.safeLivingRoom,
                blurb: "Low, heavy furniture and a wall-mounted television. Almost nothing here moves — which is worth seeing too.",
                isRecommended: false),
            DemoRoomOption(
                room: RoomFixtures.kitchen,
                blurb: "A gas range, an unstrapped fridge and a cupboard of glass, right beside the only way out.",
                isRecommended: false),
        ]
    }

    /// The quality report a bundled room enters the pipeline with.
    ///
    /// Derived from the room itself rather than hard-coded, so a fixture that
    /// gained or lost a wall reports honestly. Fixtures are complete by
    /// construction, so this always passes — which is the point: the quality
    /// gate is not skipped for demo rooms, it is simply satisfied.
    static func quality(for room: ScannedRoom) -> ScanQualityReport {
        let walls = room.surfaces.filter { $0.kind == .wall }
        let floors = room.surfaces.filter { $0.kind == .floor }
        let openings = room.surfaces.filter { $0.kind == .door || $0.kind == .window || $0.kind == .opening }
        let area = floors.first.map { Double($0.extents.width) * Double($0.extents.depth) } ?? 0

        return ScanQualityReport(
            wallCount: walls.count,
            floorCount: floors.count,
            openingCount: openings.count,
            objectCount: room.objects.count,
            droppedObjectCount: 0,
            completeWallFraction: 1,
            highConfidenceFraction: 1,
            lowConfidenceFraction: 0,
            floorArea: area,
            issues: [])
    }

    /// Everything the scan draft needs to enter S-11 as if the room had just
    /// been captured.
    static func progress(for room: ScannedRoom) -> ScanProgress {
        ScanProgress(
            walls: 1, floor: 1, openings: 1, objects: 1,
            objectCount: room.objects.count,
            elapsed: 0,
            isReadyToFinish: true)
    }
}

// MARK: - What the screen leads with

/// The headline and explanation, which depend on *why* the user is here.
///
/// Three cases, and they are genuinely different situations: a phone that has no
/// sensor, a Simulator that has no camera at all, and someone with a perfectly
/// capable iPhone who chose a demo room on purpose. Telling the third group
/// their iPhone can't scan would be both wrong and insulting.
enum DemoRoomsIntro {

    static func headline(capabilities: DeviceCapabilities) -> String {
        if capabilities.supportsRoomScanning { return "Start with a room we prepared." }
        if capabilities.isSimulator { return "The Simulator can't scan a room." }
        return "This iPhone doesn't have a LiDAR scanner."
    }

    static func message(capabilities: DeviceCapabilities) -> String {
        if capabilities.supportsRoomScanning {
            return "A good way to see what a finished report looks like before you walk around your own home. Everything runs for real."
        }
        if capabilities.isSimulator {
            return "There's no camera and no depth sensor here, so scanning is the one thing that can't run. Everything after it can, and does."
        }
        return "Scanning uses the LiDAR sensor, which is fitted to every iPhone Pro and Pro Max from the iPhone 12 Pro onwards, and to the iPad Pro. It's the only part of proof that needs it."
    }

    /// The promise that turns this screen from a rejection into an offer.
    static let assurance = "Object detection, the physics, the risk scoring and the fix-it plan all run on this device, on real geometry. The scan is the only part we've done for you."
}

// MARK: - S-08

struct DemoRoomsView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    @State private var preparingID: UUID?
    @State private var failure: String?

    private var options: [DemoRoomOption] { DemoRoomCatalogue.all }

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Demo rooms",
                leading: TremorNavBarItem(
                    systemImage: "chevron.left",
                    label: "Back",
                    action: { router.pop() }))

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    intro

                    if let failure {
                        TremorBanner(
                            "That room didn't open",
                            message: failure,
                            kind: .warning,
                            actionTitle: "Try again",
                            action: { self.failure = nil })
                    }

                    TremorSectionHeader("Pick a room")

                    ForEach(options) { option in
                        DemoRoomCard(
                            option: option,
                            isPreparing: preparingID == option.id,
                            isDisabled: preparingID != nil && preparingID != option.id,
                            action: { choose(option) })
                    }

                    footer
                }
                .padding(.horizontal, TremorSpacing.md)
                .padding(.vertical, TremorSpacing.md)
            }
        }
        .tremorScreen(inset: 0)
    }

    // MARK: Pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text(DemoRoomsIntro.headline(capabilities: tremor.capabilities))
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(DemoRoomsIntro.message(capabilities: tremor.capabilities))
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: TremorSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                    .foregroundStyle(TremorColor.success)
                    .accessibilityHidden(true)
                Text(DemoRoomsIntro.assurance)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(TremorSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TremorColor.primarySoft,
                        in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
            .padding(.top, TremorSpacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            if tremor.capabilities.supportsRoomScanning {
                TremorButton("Scan my own room instead",
                            variant: .secondary,
                            size: .medium,
                            leadingIcon: "camera.viewfinder",
                            hint: "Starts a new scan of a room you're standing in") {
                    appState.beginScan()
                    router.startScan(deviceCanScan: true)
                }
            }

            Text("Demo rooms don't touch your library — nothing is saved unless you ask for it.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TremorSpacing.sm)
    }

    // MARK: Behaviour

    /// Loads a fixture into the scan draft exactly as the capture screen would
    /// have, and hands it to S-11. Everything downstream is real.
    private func choose(_ option: DemoRoomOption) {
        guard preparingID == nil else { return }
        preparingID = option.id
        failure = nil

        let room = option.room
        appState.beginScan(kind: room.kind, isDemo: true)
        appState.updateDraft { draft in
            draft.name = room.name
            draft.building = room.building
            draft.preview = room
            draft.progress = DemoRoomCatalogue.progress(for: room)
            draft.result = ScanResult(
                room: room,
                quality: DemoRoomCatalogue.quality(for: room),
                elapsed: 0)
        }

        guard appState.draft?.result != nil else {
            preparingID = nil
            failure = "Something went wrong loading that room. Try again, or pick a different one."
            return
        }

        preparingID = nil
        router.processScan()
    }
}

// MARK: - The card

/// One demo room: its real plan drawn from its real geometry, its name, what is
/// interesting about it, and what it contains.
struct DemoRoomCard: View {

    let option: DemoRoomOption
    var isPreparing: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        TremorCard.tappable(
            padding: TremorSpacing.sm,
            accessibilityLabel: "\(option.name). \(option.metadata). \(option.blurb)",
            accessibilityHint: "Opens this room and builds its report",
            action: action
        ) {
            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                RoomPlanSketch(room: option.room)
                    .frame(width: Metric.sketch, height: Metric.sketch)
                    .background(TremorColor.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail,
                                                     style: .continuous))
                    .overlay {
                        if isPreparing {
                            RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                                .fill(TremorColor.surface.opacity(TremorControlMetrics.disabledVeil))
                                .overlay { ProgressView().tint(TremorColor.primary) }
                        }
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    HStack(spacing: TremorSpacing.xs) {
                        Text(option.name)
                            .tremorType(.headline)
                            .foregroundStyle(TremorColor.ink)
                            .lineLimit(1)
                        if option.isRecommended { recommendedBadge }
                        Spacer(minLength: 0)
                    }

                    Text(option.metadata)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .lineLimit(2)

                    Text(option.blurb)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, TremorSpacing.hair)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                    .foregroundStyle(TremorColor.inkTertiary)
                    .padding(.top, TremorSpacing.xxs)
                    .accessibilityHidden(true)
            }
        }
        .disabled(isDisabled || isPreparing)
        .opacity(isDisabled ? TremorControlMetrics.disabledVeil : 1)
    }

    private var recommendedBadge: some View {
        Text("Start here")
            .tremorType(.captionEmphasis)
            .foregroundStyle(TremorColor.ink)
            .padding(.horizontal, TremorSpacing.xs)
            .padding(.vertical, TremorSpacing.hair)
            .background(TremorColor.accent, in: Capsule(style: .continuous))
            .accessibilityLabel("Recommended")
    }

    private enum Metric {
        static let sketch: CGFloat = 88
    }
}

// MARK: - The plan sketch

/// A top-down plan of a room, drawn from the room's own surfaces and objects.
///
/// It is not decoration: the walls are the wall segments, the rectangles are the
/// furniture footprints at their real size and yaw. That means the thumbnail for
/// the bedroom actually shows the bookcase standing beside the bed, which is the
/// thing the card is claiming.
struct RoomPlanSketch: View {

    let room: ScannedRoom

    /// Objects sitting on top of other objects are omitted: at thumbnail scale a
    /// vase on a nightstand is a smudge on top of a nightstand.
    private var footprints: [ScannedObject] {
        room.objects.filter { $0.supportedBy == nil && $0.mounting != .wallMounted }
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard let bounds = Self.bounds(of: room) else { return }

            let inset = TremorSpacing.xs
            let available = CGSize(width: max(1, size.width - inset * 2),
                                   height: max(1, size.height - inset * 2))
            let span = max(bounds.width, 0.1)
            let depth = max(bounds.height, 0.1)
            let scale = min(available.width / span, available.height / depth)
            let origin = CGPoint(
                x: size.width / 2 - CGFloat(bounds.midX) * scale,
                y: size.height / 2 - CGFloat(bounds.midY) * scale)

            func project(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y + CGFloat(z) * scale)
            }

            // Floor plate.
            let plate = Path(CGRect(
                x: project(bounds.minX, bounds.minY).x,
                y: project(bounds.minX, bounds.minY).y,
                width: CGFloat(bounds.width) * scale,
                height: CGFloat(bounds.height) * scale))
            context.fill(plate, with: .color(TremorColor.surface))

            // Walls.
            var walls = Path()
            for surface in room.surfaces where surface.kind == .wall {
                let half = Double(surface.extents.width) / 2
                let yaw = Double(surface.placement.yaw)
                let cx = Double(surface.placement.centre.x)
                let cz = Double(surface.placement.centre.z)
                walls.move(to: project(cx - cos(yaw) * half, cz - sin(yaw) * half))
                walls.addLine(to: project(cx + cos(yaw) * half, cz + sin(yaw) * half))
            }
            context.stroke(walls,
                           with: .color(TremorColor.ink.opacity(0.42)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Footprints.
            for object in footprints {
                let w = Double(object.extents.width) / 2
                let d = Double(object.extents.depth) / 2
                let yaw = Double(object.placement.yaw)
                let cx = Double(object.placement.centre.x)
                let cz = Double(object.placement.centre.z)
                let corners = [(-w, -d), (w, -d), (w, d), (-w, d)].map { local -> CGPoint in
                    let rx = local.0 * cos(yaw) - local.1 * sin(yaw)
                    let rz = local.0 * sin(yaw) + local.1 * cos(yaw)
                    return project(cx + rx, cz + rz)
                }
                var path = Path()
                path.move(to: corners[0])
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.closeSubpath()
                context.fill(path, with: .color(TremorColor.primary.opacity(0.20)))
                context.stroke(path, with: .color(TremorColor.primary.opacity(0.65)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// The room's extent in the floor plane, in metres.
    static func bounds(of room: ScannedRoom) -> CGRect? {
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        for surface in room.surfaces where surface.kind == .wall || surface.kind == .floor {
            let half = Double(surface.extents.width) / 2
            let halfDepth = Double(surface.extents.depth) / 2
            let yaw = Double(surface.placement.yaw)
            let cx = Double(surface.placement.centre.x)
            let cz = Double(surface.placement.centre.z)
            let extentX = abs(cos(yaw)) * half + abs(sin(yaw)) * halfDepth
            let extentZ = abs(sin(yaw)) * half + abs(cos(yaw)) * halfDepth
            minX = min(minX, cx - extentX); maxX = max(maxX, cx + extentX)
            minZ = min(minZ, cz - extentZ); maxZ = max(maxZ, cz + extentZ)
        }

        guard maxX > minX, maxZ > minZ else { return nil }
        return CGRect(x: minX, y: minZ, width: maxX - minX, height: maxZ - minZ)
    }
}

// MARK: - Previews

#Preview("S-08 no LiDAR") {
    OnboardingPreviewHost(env: .makePreview(capabilities: .scanIncapable, seedsFixtures: false)) {
        DemoRoomsView()
    }
}

#Preview("S-08 simulator") {
    OnboardingPreviewHost(env: .makePreview(
        capabilities: DeviceCapabilities(supportsRoomScanning: false, isSimulator: true),
        seedsFixtures: false)) {
        DemoRoomsView()
    }
}

#Preview("S-08 scan-capable device") {
    OnboardingPreviewHost(env: .makePreview(capabilities: .scanCapable, seedsFixtures: false)) {
        DemoRoomsView()
    }
}

#Preview("S-08 large text") {
    OnboardingPreviewHost(env: .makePreview(capabilities: .scanIncapable, seedsFixtures: false)) {
        DemoRoomsView()
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Room plan sketches") {
    HStack(spacing: TremorSpacing.md) {
        ForEach(DemoRoomCatalogue.all) { option in
            RoomPlanSketch(room: option.room)
                .frame(width: 96, height: 96)
                .background(TremorColor.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail,
                                                 style: .continuous))
        }
    }
    .padding(TremorSpacing.xl)
    .tremorScreen()
}
