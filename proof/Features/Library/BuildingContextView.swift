//
//  BuildingContextView.swift
//  Tremor — Features / Library (S-07)
//
//  Three questions, asked once, before the camera ever opens.
//
//  They are here because they are the only inputs that change the physics and
//  that we cannot infer from a scan:
//
//    1. **What kind of room is it.** Sets the occupancy weight in the
//       consequence score (§6): a bookcase over a bed is not the same finding as
//       the same bookcase in a garage.
//    2. **Which floor, of how many.** Sets the ASCE 7-22 §13.3.1 amplification
//       H_f. On the third floor of a three-storey building the furniture feels
//       roughly twice the ground motion. Getting this wrong is the single
//       largest avoidable error in the whole app.
//    3. **What the floor is made of.** Sets the friction coefficient under every
//       free-standing object, which decides whether a thing slides (mostly
//       harmless) or tips (not).
//
//  Plus a soil class behind an "Advanced" disclosure — the one term here a
//  layperson will not know, so it is the one thing that is not on the surface,
//  and every option carries a plain-language line.
//
//  The screen has to feel like ten seconds of work, so every answer is a large
//  tappable card with an icon, every step has a sane default, and the last
//  answers are remembered. Nobody is ever blocked on a question.
//

import SwiftUI

// MARK: - Steps

/// The three questions, in order.
enum ScanSetupStep: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case room
    case floor
    case surface

    var id: Int { rawValue }

    var question: String {
        switch self {
        case .room: return "What kind of room is this?"
        case .floor: return "Where is it in the building?"
        case .surface: return "What's the floor made of?"
        }
    }

    var rationale: String {
        switch self {
        case .room:
            return "Rooms people sleep in score higher, because you can't get out of the way in your sleep."
        case .floor:
            return "Upper floors shake harder than the ground does. This is the biggest single correction we make."
        case .surface:
            return "Friction decides whether something slides — which is usually fine — or tips over, which usually isn't."
        }
    }

    /// 1-based, for "Step 2 of 3".
    var number: Int { rawValue + 1 }

    var progress: Double { Double(number) / Double(ScanSetupStep.allCases.count) }

    var next: ScanSetupStep? { ScanSetupStep(rawValue: rawValue + 1) }
    var previous: ScanSetupStep? { ScanSetupStep(rawValue: rawValue - 1) }
}

// MARK: - Building shape

/// A one-tap way to set the storey count, so most people never touch a stepper.
///
/// The bands are the ones that matter to the period estimate `T ≈ 0.0488·h^0.75`
/// — a house and a tower are genuinely different buildings, and a picker of
/// integers from 1 to 40 asks the user to do that reasoning themselves.
enum BuildingPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case house
    case lowRise
    case midRise
    case tower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .house: return "House"
        case .lowRise: return "Low-rise block"
        case .midRise: return "Mid-rise block"
        case .tower: return "Tower"
        }
    }

    var detail: String {
        switch self {
        case .house: return "1–2 floors"
        case .lowRise: return "3–5 floors"
        case .midRise: return "6–12 floors"
        case .tower: return "13 or more"
        }
    }

    var symbolName: String {
        switch self {
        case .house: return "house"
        case .lowRise: return "building"
        case .midRise: return "building.2"
        case .tower: return "building.columns"
        }
    }

    /// The storey count chosen when this preset is tapped.
    var defaultStoreys: Int {
        switch self {
        case .house: return 2
        case .lowRise: return 4
        case .midRise: return 8
        case .tower: return 16
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .house: return 1...2
        case .lowRise: return 3...5
        case .midRise: return 6...12
        case .tower: return 13...Int.max
        }
    }

    /// Which preset a given storey count falls in.
    static func matching(storeys: Int) -> BuildingPreset {
        allCases.first { $0.range.contains(max(1, storeys)) } ?? .tower
    }
}

// MARK: - Copy

/// The sentences S-07 puts on screen. Static so the tests can read them.
enum ScanSetupCopy {

    /// "Ground floor", "1st floor", … Never a bare integer, never "storey 0".
    static func floorLabel(_ floor: Int) -> String {
        switch floor {
        case 0: return "Ground"
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(floor)th"
        }
    }

    /// The persuasive line. This is the number that makes people care about the
    /// question, so it is stated in multiples, not in symbols.
    static func amplification(_ building: BuildingContext) -> String {
        let factor = building.floorAmplification
        if factor <= 1.02 {
            return "At ground level, your furniture feels the ground motion as it is."
        }
        return String(
            format: "Your floor shakes about %.1f× as hard as the ground does.",
            factor)
    }

    /// The honest caveat under the amplification line.
    static func amplificationDetail(_ building: BuildingContext) -> String {
        building.floor == 0
            ? "Nothing is added, and nothing is taken away."
            : "ASCE 7-22 §13.3.1, using the period estimate for a typical residential frame."
    }

    /// What a floor surface means for the things standing on it.
    static func surfaceDetail(_ surface: FloorSurface) -> String {
        switch surface {
        case .carpet: return "Grippy. Things tip rather than slide."
        case .hardwood: return "Middling. Some sliding, some tipping."
        case .laminate: return "Slippery. Furniture walks across the room."
        case .tile: return "Slippery and hard. Anything that falls, breaks."
        case .concrete: return "Grippy but unforgiving."
        case .rug: return "The rug itself can slide, taking everything with it."
        case .woodShelf, .glassShelf, .stoneCounter: return surface.displayName
        }
    }

    static func surfaceSymbol(_ surface: FloorSurface) -> String {
        switch surface {
        case .carpet: return "square.grid.3x3.square"
        case .hardwood: return "rectangle.split.3x1"
        case .laminate: return "rectangle.grid.1x2"
        case .tile: return "square.grid.2x2"
        case .concrete: return "square.dashed"
        case .rug: return "circle.grid.cross"
        case .woodShelf, .glassShelf, .stoneCounter: return "square"
        }
    }

    /// The floor surfaces a room's floor can actually be, in the order they are
    /// offered.
    static let floorSurfaces: [FloorSurface] = FloorSurface.allCases.filter(\.isFloorType)
}

// MARK: - Screen

/// S-07 — the three-step building context form.
struct BuildingContextView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Self.lastKindKey) private var lastKindRaw: String = RoomKind.bedroom.rawValue

    @State private var step: ScanSetupStep = .room
    @State private var kind: RoomKind = .bedroom
    @State private var building = BuildingContext()
    @State private var showsAdvanced = false
    @State private var didLoadDefaults = false

    /// The `@AppStorage` key for the last room kind. Namespaced like every other
    /// Tremor default.
    static let lastKindKey = "com.annenolte.proof.lastRoomKind"

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "New scan",
                subtitle: "Step \(step.number) of \(ScanSetupStep.allCases.count)",
                leading: TremorNavBarItem(
                    systemImage: "chevron.left",
                    label: step == .room ? "Back to your rooms" : "Back a step",
                    action: goBack))

            TremorProgressBar(value: step.progress)
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.sm)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step.number) of \(ScanSetupStep.allCases.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    header

                    switch step {
                    case .room: roomStep
                    case .floor: floorStep
                    case .surface: surfaceStep
                    }
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion), value: step)
        .task { loadDefaults() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text(step.question)
                .tremorType(.title1)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: TremorSpacing.xxs) {
                Text(step.rationale)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TremorInfoButton(about: "why these three questions") { router.openMethod() }
                    .padding(.top, -TremorSpacing.sm)
                    .padding(.trailing, -TremorSpacing.sm)
            }
        }
        .padding(.top, TremorSpacing.xs)
    }

    // MARK: Step 1 — room kind

    private var roomStep: some View {
        OptionGrid(RoomKind.allCases) { option in
            OptionCard(
                title: option.displayName,
                symbolName: option.symbolName,
                isSelected: kind == option,
                accessibilityHint: option == .bedroom
                    ? "Bedrooms score highest, because people are asleep in them"
                    : nil
            ) {
                kind = option
            }
        }
    }

    // MARK: Step 2 — floor

    private var floorStep: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.lg) {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("What kind of building?")
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.ink)

                OptionGrid(BuildingPreset.allCases) { preset in
                    OptionCard(
                        title: preset.title,
                        detail: preset.detail,
                        symbolName: preset.symbolName,
                        isSelected: BuildingPreset.matching(storeys: building.totalStoreys) == preset
                    ) {
                        building = BuildingContext(
                            floor: min(building.floor, preset.defaultStoreys - 1),
                            totalStoreys: preset.defaultStoreys,
                            soil: building.soil,
                            floorSurface: building.floorSurface)
                    }
                }
            }

            TremorCard(padding: TremorSpacing.md) {
                VStack(spacing: TremorSpacing.sm) {
                    TremorStepper(
                        "Which floor",
                        value: floorBinding,
                        in: 0...(max(1, building.totalStoreys) - 1),
                        format: { ScanSetupCopy.floorLabel($0) })

                    TremorRowDivider(leadingInset: 0)

                    TremorStepper(
                        "Floors in total",
                        value: storeysBinding,
                        in: 1...Metric.maximumStoreys)
                }
            }

            amplificationCard
        }
    }

    private var amplificationCard: some View {
        TremorCard(padding: TremorSpacing.md, fill: TremorColor.primarySoft, shadow: nil) {
            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                FloorDiagram(floor: building.floor, totalStoreys: building.totalStoreys)

                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(ScanSetupCopy.amplification(building))
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ScanSetupCopy.amplificationDetail(building))
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 3 — surface and soil

    private var surfaceStep: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.lg) {
            OptionGrid(ScanSetupCopy.floorSurfaces) { surface in
                OptionCard(
                    title: surface.displayName,
                    detail: ScanSetupCopy.surfaceDetail(surface),
                    symbolName: ScanSetupCopy.surfaceSymbol(surface),
                    isSelected: building.floorSurface == surface
                ) {
                    building.floorSurface = surface
                }
            }

            advancedDisclosure
        }
    }

    private var advancedDisclosure: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Button {
                withAnimation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion)) {
                    showsAdvanced.toggle()
                }
            } label: {
                HStack(spacing: TremorSpacing.xs) {
                    Text("Advanced")
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.primary)
                    Image(systemName: showsAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                        .foregroundStyle(TremorColor.primary)
                    Spacer(minLength: 0)
                    if !showsAdvanced {
                        Text(building.soil.displayName)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                    }
                }
                .frame(minHeight: TremorSize.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced settings")
            .accessibilityValue(showsAdvanced ? "Expanded" : "Collapsed. Ground is \(building.soil.displayName)")
            .accessibilityAddTraits(.isButton)

            if showsAdvanced {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    Text("What's the building standing on?")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TremorCard(padding: 0, shadow: .card) {
                        VStack(spacing: 0) {
                            ForEach(Array(SoilClass.allCases.enumerated()), id: \.element) { index, soil in
                                if index > 0 { TremorRowDivider() }
                                TremorListRow(
                                    title: soil.displayName,
                                    subtitle: soil.detail,
                                    leading: .iconWell("mountain.2"),
                                    accessory: building.soil == soil ? .custom(AnyView(selectedTick)) : .none,
                                    isSelected: building.soil == soil,
                                    accessibilityHint: soil == .firm ? "The usual answer for a house" : nil
                                ) {
                                    building.soil = soil
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
                    }

                    Text("If you don't know, leave it on stiff soil — that's the code's own default and what most homes sit on.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
    }

    private var selectedTick: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: TremorControlMetrics.glyphMedium, weight: .semibold))
            .foregroundStyle(TremorColor.primary)
            .accessibilityHidden(true)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: TremorSpacing.xs) {
            TremorButton(primaryTitle, hint: primaryHint, action: advance)

            if step == .surface, !tremor.capabilities.supportsRoomScanning {
                Text("This iPhone has no LiDAR scanner, so we'll use a room we prepared. Everything after the scan is the real thing.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TremorSpacing.pageInset)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background {
            TremorColor.canvas
                .ignoresSafeArea()
                .tremorShadow(.lifted)
        }
    }

    private var primaryTitle: String {
        guard step == .surface else { return "Next" }
        return tremor.capabilities.supportsRoomScanning ? "Start scanning" : "Pick a demo room"
    }

    private var primaryHint: String {
        guard step == .surface else { return "Goes to step \(step.number + 1)" }
        return tremor.capabilities.supportsRoomScanning
            ? "Opens the camera and starts the room scan"
            : "Opens the demo rooms"
    }

    // MARK: Bindings

    private var floorBinding: Binding<Int> {
        Binding(
            get: { building.floor },
            set: { building = BuildingContext(
                floor: $0,
                totalStoreys: max(building.totalStoreys, $0 + 1),
                soil: building.soil,
                floorSurface: building.floorSurface) })
    }

    private var storeysBinding: Binding<Int> {
        Binding(
            get: { building.totalStoreys },
            set: { building = BuildingContext(
                floor: min(building.floor, max(0, $0 - 1)),
                totalStoreys: $0,
                soil: building.soil,
                floorSurface: building.floorSurface) })
    }

    // MARK: Actions

    /// Seeds from the last scan's answers, or from the profile's home building,
    /// so the third room in the same flat is one tap per step.
    private func loadDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        kind = RoomKind(rawValue: lastKindRaw) ?? .bedroom
        if let draft = appState.draft {
            building = draft.building
            kind = draft.kind
        } else {
            building = tremor.account.profile?.homeBuilding ?? tremor.settings.defaultBuilding
        }
    }

    private func goBack() {
        if let previous = step.previous {
            step = previous
        } else {
            appState.cancelScan()
            router.pop()
        }
    }

    private func advance() {
        if let next = step.next {
            step = next
            return
        }
        finish()
    }

    /// Writes the answers into the draft and the user's defaults, then hands off
    /// to the scanner (or to the demo rooms on a phone without LiDAR).
    private func finish() {
        let canScan = tremor.capabilities.supportsRoomScanning

        lastKindRaw = kind.rawValue
        tremor.settings.defaultBuilding = building

        if appState.draft == nil {
            appState.beginScan(kind: kind, isDemo: !canScan)
        }
        appState.updateDraft { draft in
            draft.kind = kind
            draft.building = building
            draft.isDemo = !canScan
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || RoomKind.allCases.contains(where: { $0.displayName == draft.name }) {
                draft.name = ScanDraft.defaultName(for: kind)
            }
        }

        if canScan {
            router.beginCapture()
        } else {
            router.useDemoRoom()
        }
    }

    private enum Metric {
        /// Tall enough for any residential building anyone will scan a bedroom
        /// in, and short enough that the stepper is not a scroll wheel.
        static let maximumStoreys = 60
    }
}

// MARK: - Option grid

/// Two columns of equal-height option cards. Collapses to one column at
/// accessibility sizes, where two columns cannot hold a wrapped title.
struct OptionGrid<Item: Identifiable, Card: View>: View {

    private let items: [Item]
    private let card: (Item) -> Card

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.card = card
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: TremorSpacing.xs), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: TremorSpacing.xs) {
            ForEach(items) { item in
                card(item)
            }
        }
    }
}

/// A large tappable answer: icon, title, an optional line of why-it-matters.
///
/// Selection is **ink** — a 1.5pt aubergine border and a lavender wash — plus a
/// checkmark, because a border alone is not enough in bright sun or greyscale.
struct OptionCard: View {

    var title: String
    var detail: String?
    var symbolName: String
    var isSelected: Bool
    var accessibilityHint: String?
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String,
         detail: String? = nil,
         symbolName: String,
         isSelected: Bool,
         accessibilityHint: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.isSelected = isSelected
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Button {
            TremorHaptic.selection.play()
            action()
        } label: {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                HStack(alignment: .top, spacing: TremorSpacing.xxs) {
                    Image(systemName: symbolName)
                        .font(.system(size: TremorControlMetrics.glyphLarge, weight: .regular))
                        .foregroundStyle(isSelected ? TremorColor.primary : TremorColor.inkSecondary)
                        .frame(width: TremorControlMetrics.glyphLarge,
                               height: TremorControlMetrics.glyphLarge)

                    Spacer(minLength: 0)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: TremorControlMetrics.glyphMedium, weight: .semibold))
                        .foregroundStyle(TremorColor.primary)
                        .opacity(isSelected ? 1 : 0)
                }

                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let detail {
                    Text(detail)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(TremorSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: Metric.minimumHeight, alignment: .topLeading)
            .background(isSelected ? TremorColor.primarySoft : TremorColor.surface,
                        in: RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? TremorColor.ink : TremorColor.stroke,
                                  lineWidth: isSelected ? TremorSize.strokeEmphasis : TremorSize.hairline)
            }
            .animation(TremorMotion.resolved(TremorMotion.colorShift, reduceMotion: reduceMotion),
                       value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private enum Metric {
        /// 88pt — the rich-row height, reused so a grid of answers has the same
        /// rhythm as a list of rooms.
        static let minimumHeight: CGFloat = TremorSize.rowRich
    }
}

// MARK: - Floor diagram

/// A small stack of storeys with the user's one highlighted. It is the fastest
/// way to confirm "yes, that's where I am" without reading a number.
struct FloorDiagram: View {

    var floor: Int
    var totalStoreys: Int

    /// At most six drawn storeys — beyond that the stack becomes a texture and
    /// stops communicating. The highlighted band keeps its relative position.
    private var drawn: Int { min(max(totalStoreys, 1), 6) }

    private var highlighted: Int {
        guard totalStoreys > 1 else { return 0 }
        let ratio = Double(min(floor, totalStoreys - 1)) / Double(totalStoreys - 1)
        return Int((ratio * Double(drawn - 1)).rounded())
    }

    var body: some View {
        VStack(spacing: TremorSize.hairline) {
            ForEach(0..<drawn, id: \.self) { index in
                let level = drawn - 1 - index
                RoundedRectangle(cornerRadius: TremorRadius.xs / 2, style: .continuous)
                    .fill(level == highlighted ? TremorColor.primary : TremorColor.primary.opacity(0.22))
                    .frame(height: Metric.storeyHeight)
            }
        }
        .frame(width: Metric.width)
        .accessibilityHidden(true)
    }

    private enum Metric {
        static let width: CGFloat = TremorSpacing.xxl
        static let storeyHeight: CGFloat = TremorSpacing.xs
    }
}

// MARK: - Previews

#Preview("S-07 — step 1") {
    RootPreviewHost(env: .makePreview(), phase: .ready, path: [.scanSetup])
}

#Preview("S-07 — no LiDAR") {
    RootPreviewHost(env: .makePreview(capabilities: .scanIncapable),
                    phase: .ready, path: [.scanSetup])
}

#Preview("S-07 — accessibility 3") {
    RootPreviewHost(env: .makePreview(), phase: .ready, path: [.scanSetup])
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Option cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            OptionGrid(Array(RoomKind.allCases.prefix(4))) { kind in
                OptionCard(title: kind.displayName,
                           symbolName: kind.symbolName,
                           isSelected: kind == .bedroom) {}
            }
            OptionGrid(BuildingPreset.allCases) { preset in
                OptionCard(title: preset.title,
                           detail: preset.detail,
                           symbolName: preset.symbolName,
                           isSelected: preset == .lowRise) {}
            }
        }
        .padding(TremorSpacing.pageInset)
    }
    .tremorScreen(inset: 0)
}

#Preview("Floor diagram") {
    HStack(spacing: TremorSpacing.xl) {
        ForEach([0, 1, 3, 7], id: \.self) { floor in
            VStack(spacing: TremorSpacing.xs) {
                FloorDiagram(floor: floor, totalStoreys: 8)
                Text(ScanSetupCopy.floorLabel(floor))
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkSecondary)
            }
        }
    }
    .padding(TremorSpacing.xl)
    .tremorScreen()
}
