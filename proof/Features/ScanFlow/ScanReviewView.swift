//
//  ScanReviewView.swift
//  Tremor — S-10, scan review and quality gate
//
//  The purpose of this screen is to refuse to build a report on a bad scan, and
//  to do it without ever making the user feel told off.
//
//  Three things it must get right:
//
//   1. **Honesty about what was found.** "14 objects, 4 walls and 1 door" is the
//      first line, before any judgement. If a check failed we say which one and
//      what it means in a sentence, not with a red cross.
//   2. **Editing is cheap here and expensive later.** Deleting a phantom
//      "storage unit" that is really a radiator, or adding the wardrobe the
//      scanner walked past, costs one tap now and costs a wrong report later.
//   3. **Continuing anyway stays possible.** A degraded scan is still the user's
//      room. It is allowed through, it is recorded on the draft, and S-15 carries
//      the caveat for as long as the report exists.
//

import Foundation
import SwiftUI

// MARK: - S-10

struct ScanReviewView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var azimuth: Double = 0
    @State private var azimuthAtDragStart: Double?
    @State private var sheetFraction: CGFloat = Detent.medium
    @State private var fractionAtDragStart: CGFloat?
    @State private var isEditing = false
    @State private var isAddingObject = false
    @State private var pendingDeletion: ScannedObject?
    @State private var name: String = ""

    private var draft: ScanDraft? { appState.draft }
    private var result: ScanResult? { draft?.result }
    private var room: ScannedRoom? { result?.room }
    private var quality: ScanQualityReport? { result?.quality }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                stage(availableHeight: geometry.size.height)

                if let room, let quality {
                    // The dock is a sibling of the sheet rather than something
                    // inside it: every in-sheet arrangement — the footer slot, a
                    // safe-area inset — ends up fighting the scroll view for the
                    // last few points and losing the second action, and on a
                    // failed gate that action is the user's only way forward.
                    //
                    // The explicit bottom inset is the tab bar. The shell hangs
                    // it off `safeAreaInset`, which draws it *over* this screen
                    // rather than shortening it, so bottom-anchored content has
                    // to step out of its way itself.
                    ZStack(alignment: .bottom) {
                        sheet(room: room, quality: quality)
                            .frame(height: (geometry.size.height - geometry.safeAreaInsets.bottom)
                                   * sheetFraction)
                            .transition(.move(edge: .bottom))

                        footerDock(
                            passes: Self.adjusted(quality, objectCount: room.objects.count).passes,
                            hasObjects: !room.objects.isEmpty)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                } else {
                    missingResult
                }

                topControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TremorColor.ink.ignoresSafeArea())
        .onAppear { name = draft?.name ?? "" }
        .sheet(isPresented: $isAddingObject) {
            ScanAddObjectSheet { type in
                addObject(type)
                isAddingObject = false
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Remove the \($0.type.displayName.lowercased())?" } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove it", role: .destructive) {
                if let pendingDeletion { remove(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Keep it", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("It won't be in your report. You can always scan the room again.")
        }
    }

    // MARK: The frozen room

    private func stage(availableHeight: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [TremorColor.primary.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 460)

            IsometricRoomFigure(
                room: room,
                azimuth: azimuth,
                padding: TremorSpacing.xxl)
            .padding(.bottom, availableHeight * sheetFraction)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = azimuthAtDragStart ?? azimuth
                        azimuthAtDragStart = start
                        azimuth = start + Double(value.translation.width) / Metric.dragPointsPerTurn
                    }
                    .onEnded { _ in azimuthAtDragStart = nil })
            .accessibilityHint("Drag to turn the room around")
        }
        .ignoresSafeArea()
    }

    private var topControls: some View {
        VStack {
            HStack {
                TremorIconButton(
                    systemImage: "chevron.left",
                    style: .surface,
                    size: .large,
                    label: "Back to scanning",
                    hint: "Goes back and starts this room again",
                    action: { rescan() })

                Text("Scan review")
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.inkInverse)
                    .padding(.leading, TremorSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.top, TremorSpacing.xs)
            Spacer(minLength: 0)
        }
    }

    // MARK: The sheet

    private func sheet(room: ScannedRoom, quality: ScanQualityReport) -> some View {
        let adjusted = Self.adjusted(quality, objectCount: room.objects.count)
        let checks = ScanQualityCheck.checks(for: adjusted)
        let failures = checks.filter { !$0.passed }

        return TremorSheet(
            title: "How did it go?",
            subtitle: Self.subtitle(adjusted, units: tremor.settings.units),
            presentation: .inline
        ) {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                if !failures.isEmpty {
                    TremorBanner(
                        failures.count == 1
                            ? "One thing to check"
                            : "\(failures.count) things to check",
                        message: failures.map(\.detail).joined(separator: " "),
                        kind: .warning)
                }

                checklist(checks)

                objectSection(room: room)

                TremorTextField(
                    "Room name",
                    text: $name,
                    placeholder: draft.map { ScanDraft.defaultName(for: $0.kind) } ?? "Bedroom",
                    helpText: "You can change this later.",
                    onSubmit: { commitName() })
                .onChange(of: name) { _, _ in commitName() }
            }
            .padding(.bottom, Metric.dockClearance)
        }
        .overlay(alignment: .top) { sheetDragHandle }
    }

    /// A 44 pt strip at the top of the sheet that resizes it. Restricted to the
    /// grabber's own area so it can never fight the content's scrolling.
    private var sheetDragHandle: some View {
        Color.clear
            .frame(height: TremorSize.minimumTapTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = fractionAtDragStart ?? sheetFraction
                        fractionAtDragStart = start
                        sheetFraction = min(max(start - value.translation.height / Metric.sheetTravel,
                                                Detent.medium), Detent.large)
                    }
                    .onEnded { value in
                        fractionAtDragStart = nil
                        let target = (sheetFraction + (value.predictedEndTranslation.height < 0 ? 0.08 : -0.08))
                        withAnimation(TremorMotion.resolved(TremorMotion.sheet,
                                                           reduceMotion: reduceMotion)) {
                            sheetFraction = target > (Detent.medium + Detent.large) / 2
                                ? Detent.large : Detent.medium
                        }
                    })
            .accessibilityHidden(true)
    }

    private func checklist(_ checks: [ScanQualityCheck]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TremorSectionHeader("Quality check")
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                HStack(alignment: .top, spacing: TremorSpacing.sm) {
                    Image(systemName: check.symbolName)
                        .font(.system(size: TremorControlMetrics.glyphLarge, weight: .semibold))
                        .foregroundStyle(check.tint)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                        Text(check.title)
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                        Text(check.detail)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, TremorSpacing.xs)
                .accessibilityElement(children: .combine)
                .accessibilityValue(check.passed ? "Passed" : "Needs attention")

                if index < checks.count - 1 { TremorRowDivider(leadingInset: 0) }
            }
        }
    }

    // MARK: What we found

    @ViewBuilder
    private func objectSection(room: ScannedRoom) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader(
                "What we found",
                actionTitle: room.objects.isEmpty ? nil : (isEditing ? "Done" : "Edit"),
                actionHint: isEditing
                    ? "Stops editing the list of objects"
                    : "Lets you remove something we got wrong",
                action: room.objects.isEmpty ? nil : {
                    withAnimation(TremorMotion.resolved(TremorMotion.change,
                                                       reduceMotion: reduceMotion)) {
                        isEditing.toggle()
                    }
                })

            if room.objects.isEmpty {
                Text("No furniture was detected. You can add the big pieces yourself, or scan the room again and sweep the camera across each wall more slowly.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isEditing {
                VStack(spacing: 0) {
                    ForEach(room.objects) { object in
                        TremorListRow(
                            title: object.type.displayName,
                            subtitle: Self.dimensions(of: object, units: tremor.settings.units),
                            leading: .iconWell(object.type.symbolName),
                            accessory: .custom(AnyView(
                                TremorIconButton(
                                    systemImage: "trash",
                                    style: .ghost,
                                    size: .small,
                                    label: "Remove \(object.type.displayName)",
                                    action: { pendingDeletion = object })
                                .foregroundStyle(TremorColor.danger))))
                        TremorRowDivider()
                    }
                }
            } else {
                ScanObjectChipStrip(objects: room.objects)
            }

            TremorListRow(
                title: "Add something we missed",
                subtitle: "A wardrobe, a bookcase, a TV — anything the scanner walked past",
                leading: .iconWell("plus"),
                accessory: .chevron,
                accessibilityHint: "Opens a list of common furniture to add",
                action: { isAddingObject = true })
        }
    }

    // MARK: Footer

    private func footerDock(passes: Bool, hasObjects: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TremorColor.divider)
                .frame(height: TremorSize.hairline)
            footer(passes: passes, hasObjects: hasObjects)
                .padding(.horizontal, TremorSpacing.lg)
                .padding(.top, TremorSpacing.md)
                .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .background(TremorColor.surface)
    }

    @ViewBuilder
    private func footer(passes: Bool, hasObjects: Bool) -> some View {
        VStack(spacing: TremorSpacing.xs) {
            if passes {
                TremorButton("Build my report",
                            hint: "Identifies every object and runs the earthquake") {
                    proceed(degraded: false)
                }
                TremorButton("Scan again", variant: .tertiary, size: .medium) { rescan() }
            } else {
                TremorButton("Scan again",
                            hint: "Starts this room over") { rescan() }

                // A room with nothing in it has nothing to report on, so
                // "Continue anyway" would walk straight into a failure. The way
                // forward is to name what is actually in the room.
                if hasObjects {
                    TremorButton("Continue anyway", variant: .tertiary, size: .medium,
                                hint: "Builds the report from this scan and keeps a note that it was incomplete") {
                        proceed(degraded: true)
                    }
                } else {
                    TremorButton("Add what's in the room", variant: .tertiary, size: .medium,
                                hint: "Lets you add the furniture the scanner missed") {
                        isAddingObject = true
                    }
                }
            }
        }
    }

    // MARK: Missing result

    private var missingResult: some View {
        ZStack {
            TremorColor.canvas.ignoresSafeArea()
            TremorEmptyState(
                title: "There's no scan to review",
                message: "The capture didn't finish, so there's nothing here yet. Scanning again takes about three minutes.",
                systemImage: "viewfinder",
                actionTitle: "Scan again",
                action: { rescan() })
        }
    }

    // MARK: Actions

    private func commitName() {
        appState.updateDraft { $0.name = name }
    }

    private func proceed(degraded: Bool) {
        commitName()
        appState.updateDraft { $0.acceptedDegradedQuality = degraded }
        if degraded {
            appState.post(
                "Building with an incomplete scan",
                message: "Your report will carry a note about it.",
                style: .info)
        }
        router.processScan()
    }

    private func rescan() {
        appState.updateDraft {
            $0.result = nil
            $0.preview = nil
            $0.progress = ScanProgress()
            $0.coaching = nil
            $0.liveCrops = [:]
            $0.error = nil
            $0.acceptedDegradedQuality = false
        }
        router.pop()
    }

    private func remove(_ object: ScannedObject) {
        appState.updateDraft { draft in
            draft.result?.room.objects.removeAll { $0.id == object.id }
            draft.result?.crops.removeValue(forKey: object.id)
            draft.preview = draft.result?.room
        }
        appState.post("Removed the \(object.type.displayName.lowercased())", style: .info)
    }

    private func addObject(_ type: ObjectType) {
        guard let room else { return }
        let object = ScanObjectFactory.make(type, in: room)
        appState.updateDraft { draft in
            draft.result?.room.objects.append(object)
            draft.preview = draft.result?.room
        }
        appState.post("Added a \(type.displayName.lowercased())",
                      message: "We'll size it from the room and identify it with the rest.",
                      style: .success)
    }

    // MARK: Helpers

    /// The gate's own numbers, corrected for edits made on this screen.
    ///
    /// Only the object count and the "no furniture" issue can change here —
    /// wall completeness and confidence are properties of the capture and adding
    /// a wardrobe by hand does not improve them. Recomputing the whole report
    /// would quietly launder a bad scan into a good one.
    static func adjusted(_ quality: ScanQualityReport, objectCount: Int) -> ScanQualityReport {
        var issues = quality.issues.filter { $0 != .noObjects }
        if objectCount == 0 { issues.append(.noObjects) }
        return ScanQualityReport(
            wallCount: quality.wallCount,
            floorCount: quality.floorCount,
            openingCount: quality.openingCount,
            objectCount: objectCount,
            droppedObjectCount: quality.droppedObjectCount,
            completeWallFraction: quality.completeWallFraction,
            highConfidenceFraction: quality.highConfidenceFraction,
            lowConfidenceFraction: quality.lowConfidenceFraction,
            floorArea: quality.floorArea,
            issues: issues)
    }

    /// The one-line summary under "How did it go?" — what was found and how
    /// big the room turned out to be, in a single breath.
    static func subtitle(_ quality: ScanQualityReport, units: UnitSystem) -> String {
        let inventory = ScanFlowCopy.inventory(quality)
        guard let area = ScanFlowCopy.floorArea(quality.floorArea, units: units) else {
            return inventory
        }
        return "\(inventory) · \(area)"
    }

    static func dimensions(of object: ScannedObject, units: UnitSystem) -> String {
        let height = UnitFormatter.height(Double(object.extents.height), in: units)
        let width = UnitFormatter.length(Double(object.extents.width), in: units, decimals: 2)
        return "\(height) tall · \(width) wide"
    }

    private enum Detent {
        /// SPEC §2.7.4: the `medium` detent is 0.58 of the screen.
        static let medium: CGFloat = 0.58
        /// And `large` is 0.92.
        static let large: CGFloat = 0.94
    }

    private enum Metric {
        static let dragPointsPerTurn: Double = 120
        static let sheetTravel: CGFloat = 520
        /// Height of the docked actions, so the sheet's scroll content can
        /// clear them. Two 56/48 pt pills, their gap and their padding.
        static let dockClearance: CGFloat = 150
    }
}

// MARK: - Object chips

/// The detected-object strip: one chip per kind with its count, so "3 storage,
/// 1 bed" reads at a glance and a phantom detection is obvious.
struct ScanObjectChipStrip: View {

    let objects: [ScannedObject]

    private var groups: [(type: ObjectType, count: Int)] {
        Dictionary(grouping: objects, by: \.type)
            .map { (type: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $0.type.displayName) > ($1.count, $1.type.displayName) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TremorSpacing.xs) {
                ForEach(groups, id: \.type) { group in
                    TremorChip(
                        group.type.displayName,
                        systemImage: group.type.symbolName,
                        count: group.count > 1 ? group.count : nil,
                        isSelected: false,
                        showsSelectionCheck: false,
                        action: {})
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, TremorSpacing.hair)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detected objects")
        .accessibilityValue(
            groups.map { ScanFlowCopy.count($0.count, $0.type.displayName.lowercased(),
                                            $0.type.displayName.lowercased() + "s") }
                .joined(separator: ", "))
    }
}

// MARK: - Adding an object

/// The curated list of things people actually find missing from a scan.
///
/// Not all fifty archetypes: RoomPlan misses tall, flat, wall-hugging furniture
/// and screens, and those are also exactly the dangerous ones. Everything else
/// is either detected reliably or is not worth the tap.
enum ScanObjectFactory {

    static let offered: [ObjectType] = [
        .bookshelfTall, .wardrobe, .dresser, .highboy, .chinaCabinet,
        .filingCabinet, .television, .mirrorLeaning, .floorLamp, .refrigerator,
        .waterHeater, .pianoUpright
    ]

    /// Typical size for a type, in metres — width × height × depth.
    ///
    /// These are catalogue dimensions for the ordinary version of each piece;
    /// the mass that comes out of them is still the catalogue's own density
    /// prior times this volume, so an added object goes through exactly the
    /// same physics as a scanned one, and the report says its size was
    /// estimated rather than measured.
    static func typicalExtents(for type: ObjectType) -> Extents {
        switch type {
        case .bookshelfTall: return Extents(width: 0.80, height: 1.80, depth: 0.30)
        case .wardrobe: return Extents(width: 1.20, height: 2.00, depth: 0.60)
        case .dresser: return Extents(width: 1.20, height: 0.85, depth: 0.50)
        case .highboy: return Extents(width: 0.90, height: 1.40, depth: 0.45)
        case .chinaCabinet: return Extents(width: 1.10, height: 1.90, depth: 0.45)
        case .filingCabinet: return Extents(width: 0.45, height: 1.32, depth: 0.62)
        case .television: return Extents(width: 1.23, height: 0.71, depth: 0.08)
        case .mirrorLeaning: return Extents(width: 0.60, height: 1.60, depth: 0.05)
        case .floorLamp: return Extents(width: 0.35, height: 1.60, depth: 0.35)
        case .refrigerator: return Extents(width: 0.75, height: 1.80, depth: 0.70)
        case .waterHeater: return Extents(width: 0.55, height: 1.50, depth: 0.55)
        case .pianoUpright: return Extents(width: 1.50, height: 1.25, depth: 0.62)
        default: return Extents(width: 0.60, height: 1.00, depth: 0.45)
        }
    }

    /// Places a new object against the wall the room has most space beside,
    /// which is where furniture actually stands, and marks it as user-supplied
    /// so nothing downstream mistakes it for a measurement.
    static func make(_ type: ObjectType, in room: ScannedRoom) -> ScannedObject {
        let extents = typicalExtents(for: type)
        let bounds = IsometricRoomGeometry.bounds(of: room)
        let centre = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            bounds.min.y + extents.height / 2,
            bounds.min.z + extents.depth / 2 + 0.05)

        let mass = ObjectClassifier.priorMass(type: type, extents: extents, loading: .partial)
        return ScannedObject(
            type: type,
            placement: Placement(centre: centre, yaw: 0),
            extents: extents,
            provenance: IdentificationProvenance(
                source: .user, confidence: 1.0, scannerCategory: "user"),
            mass: mass.kg,
            loading: .partial)
    }
}

/// The picker raised by "Add something we missed".
private struct ScanAddObjectSheet: View {

    let onPick: (ObjectType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Add an object",
                subtitle: "We'll use a typical size for it",
                trailing: TremorNavBarItem(systemImage: "xmark", label: "Close") { dismiss() })

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ScanObjectFactory.offered) { type in
                        TremorListRow(
                            title: type.displayName,
                            subtitle: ScanReviewView.dimensions(
                                of: ScanObjectFactory.make(
                                    type, in: ScannedRoom(name: "", kind: .other)),
                                units: .metric),
                            leading: .iconWell(type.symbolName),
                            accessory: .chevron,
                            accessibilityHint: "Adds it to this room",
                            action: { onPick(type) })
                        TremorRowDivider()
                    }
                }
                .padding(.vertical, TremorSpacing.xs)
            }
        }
        .tremorScreen(inset: TremorSpacing.md)
    }
}

// MARK: - Previews

#Preview("S-10 all checks pass") {
    ScanFlowPreviewHost(stage: .review(quality: .clean))
}

#Preview("S-10 failed checks") {
    ScanFlowPreviewHost(stage: .review(quality: .degraded))
}

#Preview("S-10 no objects") {
    ScanFlowPreviewHost(stage: .review(quality: .empty))
}

#Preview("S-10 nothing to review") {
    ScanFlowPreviewHost(stage: .review(quality: .missing))
}
