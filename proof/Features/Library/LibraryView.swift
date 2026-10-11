//
//  LibraryView.swift
//  Tremor — Features / Library (S-06)
//
//  The home screen: what the app opens to, every time, forever.
//
//  Top to bottom (SPEC §1.4 S-06): the large collapsing title, the ink hero card
//  that starts a scan, a whole-home safety summary, then a card per room with
//  its plate, its name, its object count, its worst band and when it was last
//  shaken. Sort and band filter sit between the summary and the list.
//
//  Three notes on the shape of this file:
//
//  • It is a `List`, not a `ScrollView`. Swipe-to-delete has to be real —
//    SPEC calls for it — and a hand-rolled drag gesture is worse than the system
//    one in every way that matters, especially to VoiceOver and Switch Control.
//    The collapsing large title is driven from the list's own scroll geometry.
//
//  • Nothing here is a dead end. The empty state offers both the scan and the
//    demo room. The error state offers a retry. A filter that hides everything
//    offers to clear itself. A damaged room offers to be removed. An accidental
//    delete can be taken back for eight seconds.
//
//  • Every state renders: loading, empty, filtered-empty, error, offline (the
//    shell's banner), no-LiDAR (the hero card changes), and loaded.
//

import SwiftUI

// MARK: - Screen

struct LibraryView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = LibraryModel()
    @State private var collapse: Double = 0
    @State private var renaming: RoomSummary?
    @State private var inspecting: RoomSummary?
    @State private var confirmingDelete: RoomSummary?

    var body: some View {
        VStack(spacing: 0) {
            // No trailing bar item: SPEC S-06 puts "Edit" on the section header,
            // beside the rows it edits, and a lone glyph floating in an
            // otherwise empty bar reads as a mistake.
            TremorNavBar(title: "Rooms", collapseProgress: collapse)

            list
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .task {
            model.attach(tremor)
            await model.load()
        }
        // The shell keeps both tab stacks alive, so `.task` fires once and never
        // again. Coming back from the stage — after a scan, a rename or a delete
        // made over there — has to re-read the index, quietly and with no
        // skeleton, or the library shows yesterday's truth.
        .onChange(of: router.roomsPath.count) { _, depth in
            guard depth == 0 else { return }
            Task { await model.refresh() }
        }
        .sheet(item: $renaming) { room in
            RenameRoomSheet(room: room) { newName in
                Task {
                    let ok = await model.rename(room, to: newName)
                    if ok { appState.post("Renamed", style: .success) }
                }
            }
        }
        .sheet(item: $inspecting) { room in
            RoomDetailSheet(
                room: room,
                onOpen: { open(room) },
                onRename: { renaming = room },
                onDuplicate: { duplicate(room) },
                onShare: { router.share(roomID: room.id) },
                onDelete: { confirmingDelete = room })
        }
        .confirmationDialog(
            "Delete this room?",
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { room in
            Button("Delete \(room.name)", role: .destructive) { delete(room) }
            Button("Keep it", role: .cancel) {}
        } message: { room in
            Text("\(room.name) and its reports will be removed from this iPhone. You'll have a few seconds to undo it.")
        }
    }

    // MARK: List

    private var list: some View {
        List {
            Section {
                heroCard
                    .libraryRow()

                switch model.phase {
                case .loading where model.isEmpty:
                    LibrarySkeleton()
                        .libraryRow()

                case .failed(let message):
                    TremorBanner(
                        "Couldn't open your library",
                        message: message,
                        kind: .danger,
                        actionTitle: "Try again",
                        action: { Task { await model.load() } })
                    .libraryRow()

                case .loaded, .loading:
                    loadedContent
                }
            }
            .listSectionSeparator(.hidden)

            // Keeps the last card clear of the tab bar and gives the footer air.
            Color.clear
                .frame(height: TremorSpacing.xl)
                .libraryRow()
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await model.refresh() }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let distance = TremorNavBar.largeTitleHeight(
                hasSubtitle: false, dynamicTypeSize: dynamicTypeSize)
            collapse = distance > 0 ? min(1, max(0, Double(offset / distance))) : 0
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let pending = model.pendingDeletion {
            undoBanner(pending)
                .libraryRow()
        }

        if model.damagedCount > 0 {
            TremorBanner(
                model.damagedCount == 1 ? "One room can't be read" : "\(model.damagedCount) rooms can't be read",
                message: "Their files were damaged, probably by a failed save. Everything else in your library is fine.",
                kind: .warning,
                actionTitle: "Remove them",
                action: {
                    Task {
                        let removed = await model.purgeDamaged()
                        appState.post(
                            removed == 1 ? "Removed 1 damaged room" : "Removed \(removed) damaged rooms",
                            style: .info)
                    }
                })
            .libraryRow()
        }

        if model.isEmpty {
            emptyState
                .libraryRow()
        } else {
            summaryBlock
                .libraryRow()

            TremorSectionHeader(
                "Your rooms",
                actionTitle: model.isEditing ? "Done" : "Edit",
                actionHint: model.isEditing
                    ? "Hides the delete buttons"
                    : "Shows a delete button on every room",
                action: { withAnimation(motion) { model.isEditing.toggle() } })
            .libraryRow()

            if model.rooms.count > 1 {
                LibraryFilterBar(
                    sort: $model.sort,
                    band: $model.bandFilter,
                    availableBands: model.availableBands)
                .libraryRow(horizontal: 0)
            }

            if model.isFilteredEmpty {
                filteredEmptyState
                    .libraryRow()
            } else {
                ForEach(model.visibleRooms) { room in
                    RoomCard(
                        room: room,
                        isEditing: model.isEditing,
                        onOpen: { open(room) },
                        onMore: { inspecting = room },
                        onDelete: { confirmingDelete = room })
                    .libraryRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            confirmingDelete = room
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            renaming = room
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(TremorColor.primary)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            inspecting = room
                        } label: {
                            Label("Details", systemImage: "info.circle")
                        }
                        .tint(TremorColor.primary)
                        Button {
                            router.share(roomID: room.id)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(TremorColor.info)
                    }
                    .contextMenu {
                        Button { open(room) } label: { Label("Open", systemImage: "cube.transparent") }
                        Button { inspecting = room } label: { Label("Room details", systemImage: "info.circle") }
                        Button { renaming = room } label: { Label("Rename", systemImage: "pencil") }
                        Button { duplicate(room) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button { router.share(roomID: room.id) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        Divider()
                        Button(role: .destructive) { confirmingDelete = room } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            methodFooter
                .libraryRow()
        }
    }

    // MARK: Hero

    /// SPEC S-06: full-width ink card, 24pt padding, the big action, and a 44pt
    /// circular button at the trailing edge. The whole card is one tap target.
    private var heroCard: some View {
        let canScan = tremor.capabilities.supportsRoomScanning
        return Button {
            startScan()
        } label: {
            HStack(alignment: .center, spacing: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(canScan ? "Scan a room" : "Try a demo room")
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.primarySoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(canScan
                         ? "About 3 minutes, walking slowly around the room"
                         : "This iPhone has no LiDAR scanner, so start with a room we prepared")
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkInverse.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: TremorControlMetrics.glyphMedium, weight: .semibold))
                    .foregroundStyle(TremorColor.onPrimary)
                    .frame(width: TremorSize.minimumTapTarget, height: TremorSize.minimumTapTarget)
                    .background(TremorColor.primary, in: Circle())
            }
            .padding(TremorSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TremorColor.ink, in: RoundedRectangle(
                cornerRadius: TremorRadius.card, style: .continuous))
            .tremorShadow(.raised)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(canScan
                           ? "Asks three quick questions, then starts the scan"
                           : "Opens the demo rooms")
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryBlock: some View {
        if let summary = model.summary {
            HomeSafetyCard(summary: summary) { router.openMethod() }
        } else {
            TremorCard(padding: TremorSpacing.md, fill: TremorColor.primarySoft, shadow: nil) {
                HStack(alignment: .top, spacing: TremorSpacing.sm) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: TremorControlMetrics.glyphMedium, weight: .medium))
                        .foregroundStyle(TremorColor.primary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                        Text("Nothing shaken yet")
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                        Text("Open a room and run an earthquake — about twenty seconds, and you'll see exactly what falls.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Empty states

    private var emptyState: some View {
        VStack(spacing: TremorSpacing.md) {
            TremorEmptyState(
                title: "No rooms yet",
                message: "Scan the room you sleep in first. That's where most earthquake injuries happen — people are in bed, and they can't get out of the way."
            ) {
                RoomIsometricGlyph(band: nil, objectCount: 9, seed: 0x1ED6E)
                    .frame(width: Metric.emptyIllustration, height: Metric.emptyIllustration)
                    .clipShape(Circle())
            }

            TremorButton("Try a demo room instead",
                        variant: .tertiary,
                        size: .medium,
                        hint: "Opens three rooms we prepared, so you can see the whole app without scanning") {
                router.useDemoRoom()
            }
            .padding(.horizontal, TremorSpacing.xl)
            .padding(.bottom, TremorSpacing.xl)
        }
    }

    private var filteredEmptyState: some View {
        TremorEmptyState(
            title: "No rooms in that band",
            message: model.bandFilter.map {
                "None of your rooms came out \($0.displayName.lowercased()) at the intensity you last used."
            } ?? "Nothing matches the current filter.",
            systemImage: "line.3.horizontal.decrease.circle",
            actionTitle: "Show all rooms",
            actionHint: "Clears the risk filter",
            action: { withAnimation(motion) { model.bandFilter = nil } })
    }

    // MARK: Undo

    @ViewBuilder
    private func undoBanner(_ pending: PendingRoomDeletion) -> some View {
        if pending.canUndo {
            TremorBanner(
                "Deleted \(pending.name)",
                message: pending.message,
                kind: .neutral,
                actionTitle: "Undo",
                action: {
                    Task {
                        if await model.undoDelete() {
                            appState.post("\(pending.name) is back", style: .success)
                        }
                    }
                },
                onDismiss: { model.dismissUndo() })
            .transition(.opacity)
        } else {
            TremorBanner(
                "Deleted \(pending.name)",
                message: pending.message,
                kind: .warning,
                onDismiss: { model.dismissUndo() })
            .transition(.opacity)
        }
    }

    // MARK: Footer

    private var methodFooter: some View {
        Button {
            router.openMethod()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                Text("Scores follow FEMA E-74 with Housner rocking dynamics. Tap to see the maths.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(TremorFont.font(.caption))
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, TremorSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How proof scores rooms")
        .accessibilityHint("Opens the method and sources")
    }

    // MARK: Actions

    private var motion: Animation? {
        TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } })
    }

    private func startScan() {
        let canScan = tremor.capabilities.supportsRoomScanning
        appState.beginScan(isDemo: !canScan)
        router.startScan(deviceCanScan: canScan)
    }

    private func open(_ room: RoomSummary) {
        guard !room.isDamaged else {
            inspecting = room
            return
        }
        appState.openRoom(id: room.id)
        router.openRoom(room.id)
    }

    private func duplicate(_ room: RoomSummary) {
        Task {
            if let name = await model.duplicate(room) {
                appState.post("Duplicated", message: "Saved as \(name).", style: .success)
            }
        }
    }

    private func delete(_ room: RoomSummary) {
        confirmingDelete = nil
        Task { _ = await model.delete(room) }
    }

    private enum Metric {
        /// SPEC S-06: a 120pt spot illustration in the empty state.
        static let emptyIllustration: CGFloat = 120
    }
}

// MARK: - Row chrome

private extension View {
    /// The list-row treatment every block on S-06 shares: no separator, no
    /// system background, the page gutter, and a little vertical air so the card
    /// shadows are not clipped by their neighbours.
    func libraryRow(horizontal: CGFloat = TremorSpacing.md) -> some View {
        self
            .listRowInsets(EdgeInsets(
                top: TremorSpacing.xxs,
                leading: horizontal,
                bottom: TremorSpacing.xxs,
                trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Home safety card

/// The whole-home verdict: one headline, one distribution bar, one honest
/// footnote. Deliberately the least decorated card on the screen.
struct HomeSafetyCard: View {

    var summary: HomeSafetySummary
    var onExplain: () -> Void

    var body: some View {
        TremorCard(padding: TremorSpacing.xl,
                  fill: LibraryBandPalette.surface(summary.worstBand),
                  shadow: nil) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    Text("Your home")
                        .tremorType(.overline)
                        .foregroundStyle(TremorColor.ink.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    TremorInfoButton(about: "how a home is scored", action: onExplain)
                        .padding(.trailing, -TremorSpacing.sm)
                }

                HStack(alignment: .top, spacing: TremorSpacing.xs) {
                    Image(systemName: summary.worstBand.symbolName)
                        .font(.system(size: TremorType.title3.spec.size, weight: .semibold))
                        .foregroundStyle(LibraryBandPalette.mark(summary.worstBand))
                        .accessibilityHidden(true)

                    Text(summary.headline)
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(summary.message)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                RiskDistributionBar(counts: summary.counts,
                                    emptyMessage: "No rooms shaken yet")
                    .padding(.top, TremorSpacing.xxs)
                    // The shared bar counts objects; here every segment is a
                    // whole room, so its spoken label is replaced.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rooms by risk band")
                    .accessibilityValue(summary.spokenDistribution)

                if summary.unsimulatedCount > 0 {
                    Text(summary.unsimulatedCount == 1
                         ? "1 room hasn't been shaken yet, so it isn't counted here."
                         : "\(summary.unsimulatedCount) rooms haven't been shaken yet, so they aren't counted here.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Filter bar

/// Sort and band filter, as one horizontally scrolling strip of chips.
///
/// The sort is a menu behind a single chip rather than three chips, because sort
/// is one-of-three and a row of three selected-looking chips reads as a filter.
struct LibraryFilterBar: View {

    @Binding var sort: LibrarySort
    @Binding var band: RiskBand?
    var availableBands: [RiskBand]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TremorSpacing.xs) {
                Menu {
                    Picker("Sort rooms", selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                } label: {
                    chipLabel(sort.title, symbol: sort.symbolName, isSelected: false, trailing: "chevron.down")
                }
                .accessibilityLabel("Sort rooms")
                .accessibilityValue(sort.announcement)

                Divider()
                    .frame(height: TremorSize.buttonSmall / 2)
                    .padding(.horizontal, TremorSpacing.xxs)

                TremorChip("All", isSelected: band == nil, showsSelectionCheck: false) {
                    withAnimation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion)) {
                        band = nil
                    }
                }

                ForEach(availableBands) { option in
                    TremorChip(option.displayName,
                              systemImage: option.symbolName,
                              isSelected: band == option,
                              showsSelectionCheck: false) {
                        withAnimation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion)) {
                            band = (band == option) ? nil : option
                        }
                    }
                }
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.xxs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort and filter")
    }

    private func chipLabel(_ title: String,
                           symbol: String,
                           isSelected: Bool,
                           trailing: String?) -> some View {
        HStack(spacing: TremorSpacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
            Text(title).tremorType(.subheadline)
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
            }
        }
        .foregroundStyle(TremorColor.ink)
        .padding(.horizontal, TremorSpacing.sm)
        .frame(minHeight: TremorSize.buttonSmall)
        .background(TremorColor.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(TremorColor.stroke, lineWidth: TremorSize.hairline) }
    }
}

// MARK: - Skeleton

/// SPEC S-06 loading: three skeleton rows. The hero card is already above them,
/// because it never needs data.
struct LibrarySkeleton: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                TremorCard(padding: TremorSpacing.sm, shadow: .hairline) {
                    HStack(spacing: TremorSpacing.sm) {
                        RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                            .fill(TremorColor.surfaceSunken)
                            .frame(width: TremorSize.row, height: TremorSize.row)
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            bar(width: Metric.longBar)
                            bar(width: Metric.shortBar)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .opacity(isPulsing ? Metric.pulseLow : 1)
        .animation(pulse, value: isPulsing)
        .onAppear { isPulsing = !reduceMotion }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening your library")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Reduce Motion suppresses a repeating shimmer entirely — it is decoration,
    /// not content, and a pulsing block is exactly what the setting is for.
    private var pulse: Animation? {
        reduceMotion
            ? nil
            : .easeInOut(duration: Metric.pulseSeconds).repeatForever(autoreverses: true)
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
            .fill(TremorColor.surfaceSunken)
            .frame(width: width, height: TremorSpacing.sm)
    }

    private enum Metric {
        static let longBar: CGFloat = 140
        static let shortBar: CGFloat = 96
        static let pulseLow: Double = 0.55
        static let pulseSeconds: Double = 1.2
    }
}

// MARK: - Rename

/// A one-field sheet. Small on purpose: renaming a room is not a form.
struct RenameRoomSheet: View {

    var room: RoomSummary
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Rename",
                leading: TremorNavBarItem(systemImage: "xmark", label: "Cancel") { dismiss() })

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                TremorTextField(
                    "Room name",
                    text: $name,
                    placeholder: room.kind.displayName,
                    helpText: "Something you'll recognise in a list — \"Our bedroom\", \"Kid's room\".",
                    submitLabel: .done,
                    autocapitalization: .words,
                    onSubmit: save)
                .focused($isFocused)

                Spacer(minLength: 0)

                TremorButton("Save") { save() }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.lg)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .presentationDetents([.height(Metric.sheetHeight), .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = room.name
            isFocused = true
        }
    }

    private func save() {
        onSave(name)
        dismiss()
    }

    private enum Metric {
        static let sheetHeight: CGFloat = 280
    }
}

// MARK: - Previews

#Preview("S-06 — loaded") {
    RootPreviewHost(env: .makePreview(), phase: .ready)
}

#Preview("S-06 — empty") {
    RootPreviewHost(env: .makePreview(seedsFixtures: false), phase: .ready)
}

#Preview("S-06 — no LiDAR") {
    RootPreviewHost(env: .makePreview(capabilities: .scanIncapable), phase: .ready)
}

#Preview("S-06 — offline") {
    RootPreviewHost(env: .makePreview(online: false), phase: .ready)
}

#Preview("S-06 — accessibility 3") {
    RootPreviewHost(env: .makePreview(), phase: .ready)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Home safety card") {
    ScrollView {
        VStack(spacing: TremorSpacing.md) {
            ForEach(RiskBand.allCases) { band in
                HomeSafetyCard(
                    summary: HomeSafetySummary(
                        roomCount: 5,
                        simulatedCount: 4,
                        counts: [band: 2, .low: 2],
                        worstBand: band,
                        lastSimulated: Date()),
                    onExplain: {})
            }
        }
        .padding(TremorSpacing.md)
    }
    .tremorScreen(inset: 0)
}

#Preview("Library skeleton") {
    LibrarySkeleton()
        .padding(TremorSpacing.md)
        .tremorScreen(inset: 0)
}

#Preview("Rename sheet") {
    RenameRoomSheet(
        room: RoomSummary(id: UUID(), name: "Bedroom", kind: .bedroom, objectCount: 12),
        onSave: { _ in })
}
