//
//  ConstellationExplorerView.swift
//  proof — Features / Constellation
//
//  The kitchen in 3D with its flags over it. Same room, camera and chrome as the Tremor
//  explorer it replaces. Written for a three-minute demo: the room opens calm, the first
//  climbing path plays by itself with a plain sentence, and every card has one obvious
//  next step.
//
//    no selection  → legend, stage, "show climbing paths", the checklist
//    a lit path    → one sentence, its numbers, next path, make a fix plan
//    a flag        → what it is and why, one main action, the rest in a menu
//    a non-flag    → add it as a flag
//

import RealityKit
import SwiftUI

struct ConstellationExplorerView: View {

    @Bindable var model: DemoRoomModel
    let sky: ConstellationModel
    var roomTitle: String
    var onExit: () -> Void
    var onOpenChecklist: () -> Void

    @State private var padVector = CGSize.zero
    @State private var dimsRoom = true
    @State private var showsNewPlan = false
    @State private var newPlanName = ""
    @State private var pendingPlanStars: [String] = []
    @State private var pull = PullTest()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.20, blue: 0.24),
                    Color(red: 0.44, green: 0.44, blue: 0.48),
                    Color(red: 0.30, green: 0.29, blue: 0.33)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            DemoRealityView(
                model: model, sceneReady: model.isSceneReady, settings: .off, onSimulate: applyPad)
                .ignoresSafeArea()

            // Night falls over the room so the sky reads. The room stays visible beneath.
            TremorColor.ink.opacity(dimsRoom && !pull.isActive ? 0.42 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(TremorMotion.change, value: dimsRoom)

            // Stars sit where objects were measured. While things are moving, or after
            // they have fallen, those positions are wrong — so the sky steps aside.
            if !pull.isActive {
                StarOverlay(sky: sky) { id in tapStar(id) }
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottom
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .padding(.horizontal, TremorSpacing.lg)
            .padding(.bottom, TremorSpacing.xl)
        }
        .animation(TremorMotion.change, value: sky.selectedID)
        .animation(TremorMotion.change, value: sky.litChainID)
        .onAppear(perform: connect)
        .onChange(of: sky.litChainID) { _, _ in frameLitChain() }
        .onChange(of: model.isSceneReady) { _, _ in connect() }
        .onChange(of: model.selectedPropID) { _, id in
            guard let id else { return }
            tapStar(id)
            model.selectedPropID = nil
        }
        .alert("Name this fix plan", isPresented: $showsNewPlan) {
            TextField("Fix plan name", text: $newPlanName)
            Button("Create") {
                sky.createConstellation(name: newPlanName, starIDs: pendingPlanStars)
                newPlanName = ""
            }
            Button("Cancel", role: .cancel) { newPlanName = "" }
        } message: {
            Text("Groups \(pendingPlanStars.count) flag\(pendingPlanStars.count == 1 ? "" : "s") into one plan. proof drafts the steps from the measurements; you mark it done in the checklist.")
        }
    }

    // MARK: Wiring

    private func connect() {
        guard model.isSceneReady, let scene = model.scene else { return }
        if model.frameHandler == nil {
            sky.attach(scene: scene)
            model.frameHandler = { [weak sky] view in sky?.project(in: view) }
            model.physicsHandler = { [weak pull] dt in pull?.step(deltaTime: dt) }
            // The room opens on the whole sky, fading in.
            sky.replayArrival()
            applyLaunchOverride()
        }
    }

    /// Brings a newly lit chain into view, above the card that describes it.
    private func frameLitChain() {
        guard let chain = sky.litChain else { return }
        let points = chain.nodeIDs.compactMap { sky.analysis.object($0)?.starPosition }
        guard !points.isEmpty else { return }
        let centre = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        model.userTookCamera()
        switch model.pose.mode {
        case .orbit:
            // Lowering the target lifts the chain up the screen, clear of the card.
            model.pose.target = SIMD3(centre.x, max(0, centre.y - 0.9), centre.z)
            model.pose.distance = min(model.pose.distance, 9.5)
        case .plan:
            // Screen-up is −z in plan, so moving the centre +z lifts the chain.
            model.pose.planCentre = SIMD2(centre.x, centre.z + 1.6)
        case .walk:
            break
        }
    }

    /// `-proofLightChain` lights the first chain; `-proofSelect <id>` selects a star. Debug
    /// only — for rehearsing and screenshots. Returns true if any override applied.
    @discardableResult
    private func applyLaunchOverride() -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let used = ["-proofLightChain", "-proofPull", "-proofSelect", "-proofMode", "-proofPaths", "-proofResetCraft", "-proofKeepSuggestion"].contains(where: arguments.contains)
        if arguments.contains("-proofPaths") { showPaths() }
        if arguments.contains("-proofResetCraft") { sky.resetCraft() }
        if arguments.contains("-proofKeepSuggestion"), let first = sky.suggestions.first { sky.keep(first) }
        if arguments.contains("-proofLightChain") { sky.setMode(.paths); sky.lightNextChain() }
        if let i = arguments.firstIndex(of: "-proofPull"), i + 1 < arguments.count {
            let anchored = arguments.contains("-proofAnchored")
            Task {
                try? await Task.sleep(for: .seconds(4))   // let the room settle first
                startPull(arguments[i + 1], anchored: anchored)
            }
        }
        if let i = arguments.firstIndex(of: "-proofSelect"), i + 1 < arguments.count {
            sky.selectedID = arguments[i + 1]
        }
        if let i = arguments.firstIndex(of: "-proofMode"), i + 1 < arguments.count,
           let mode = DemoCameraMode(rawValue: arguments[i + 1]) {
            model.setMode(mode)
            model.isIdleOrbiting = false
        }
        return used
        #else
        return false
        #endif
    }

    /// Into the climbing-paths view; the first time, the clearest path plays by itself.
    private func showPaths() {
        sky.setMode(.paths)
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            sky.introduceIfNeeded()
        }
    }

    private func startPull(_ id: String, anchored: Bool) {
        guard let scene = model.scene else { return }
        sky.selectedID = nil
        sky.light(nil)
        if let object = sky.analysis.object(id) ?? sky.package?.object(id) {
            frame(on: object.aabb.centre, height: object.aabb.max.y)
        }
        pull.start(objectID: id, reachHeight: sky.analysis.parameters.reachHeight.value,
                   scene: scene, audio: model.audio, anchored: anchored)
    }

    private func frame(on centre: SIMD3<Float>, height: Float) {
        model.userTookCamera()
        if model.pose.mode == .orbit {
            // Aim past the object into the room it falls into, from far enough back to
            // see the whole fall, and lifted so it clears the card.
            let room = SIMD3<Float>(Plan.width / 2, 0, Plan.length / 2)
            let into = centre + (room - centre) * 0.35
            model.pose.target = SIMD3(into.x, max(0, height * 0.25 - 0.4), into.z)
            model.pose.distance = 10
        } else if model.pose.mode == .plan {
            model.pose.planCentre = SIMD2(centre.x, centre.z + 1.4)
        }
    }

    private func tapStar(_ id: String) {
        TremorHaptic.light.play()
        if sky.isLinking {
            sky.completeLink(to: id)
            sky.selectedID = id
            return
        }
        sky.selectedID = sky.selectedID == id ? nil : id
    }

    private func applyPad() {
        guard model.pose.mode == .walk, padVector != .zero else { return }
        let speed: Float = 0.030
        model.pose.moveWalker(
            forward: Float(-padVector.height) * speed * 0.06,
            strafe: Float(padVector.width) * speed * 0.06)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .top, spacing: TremorSpacing.xs) {
            glassButton("chevron.left", label: "Back", action: onExit)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(roomTitle)
                    .tremorType(.captionEmphasis)
                    .foregroundStyle(TremorColor.inkInverse)
                Text(sky.isLinking ? "Tap a second flag to link"
                     : sky.mode == .constellation ? "Constellation view" : "Climbing paths")
                    .tremorType(.caption)
                    .foregroundStyle(sky.isLinking ? TremorColor.accent : TremorColor.inkInverse.opacity(0.7))
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.xs)
            .background(Capsule().fill(.ultraThinMaterial))
            Spacer(minLength: 0)
            modeToggle
            moreMenu
        }
        .padding(.top, TremorSpacing.xs)
    }

    /// The small switch between the whole sky and the calm paths view.
    private var modeToggle: some View {
        let toPaths = sky.mode == .constellation
        return Button {
            TremorHaptic.light.play()
            if toPaths { showPaths() } else { sky.setMode(.constellation) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: toPaths ? "figure.climbing" : "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text(toPaths ? "Paths" : "Sky")
                    .tremorType(.captionEmphasis)
            }
            .foregroundStyle(TremorColor.ink)
            .padding(.horizontal, TremorSpacing.sm)
            .frame(height: 40)
            .background(Capsule().fill(toPaths ? TremorColor.accent : TremorColor.primarySoft))
        }
        .accessibilityLabel(toPaths ? "Show climbing paths" : "Show the constellation")
    }

    private func glassButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TremorColor.inkInverse)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .accessibilityLabel(label)
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottom: some View {
        if pull.isActive {
            pullCard
        } else if let id = sky.selectedID {
            StarCard(
                id: id, sky: sky, scene: model.scene,
                onClose: { sky.selectedID = nil },
                onPull: { startPull(id, anchored: false) },
                onNewPlan: { stars in
                    pendingPlanStars = stars
                    showsNewPlan = true
                })
        } else if let chain = sky.litChain {
            chainCard(chain)
        } else if sky.mode == .constellation {
            constellationCard
        } else {
            controls
        }
    }

    private var controls: some View {
        VStack(spacing: TremorSpacing.sm) {
            if model.pose.mode == .walk {
                HStack {
                    MovementPad(vector: $padVector)
                    Spacer()
                }
            }

            legend

            stagePicker

            TremorButton(
                sky.analysis.chains.isEmpty
                    ? "No climbing paths for \(ConstellationModel.who(sky.stage).lowercased())"
                    : "Show climbing paths · \(sky.analysis.chains.count)",
                variant: .accent,
                leadingIcon: "figure.climbing"
            ) { sky.lightNextChain() }
            .disabled(sky.analysis.chains.isEmpty)

            TremorButton(
                "Checklist · \(sky.doneCount) of \(sky.analysis.flags.count) done",
                variant: .secondary,
                size: .medium,
                leadingIcon: "checklist"
            ) { onOpenChecklist() }

            Text("Flags to check, not a safety guarantee.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkInverse.opacity(0.7))
        }
    }

    /// What the opening view is, in one sentence, and the way into the simpler view.
    private var constellationCard: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text("Your kitchen as a constellation")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            Text("Every flag is a star. Every measured link is a line.")
                .tremorType(.headline)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(sky.stars.count) stars · \(sky.linkCount) measured links · \(sky.constellations.count) fix plan\(sky.constellations.count == 1 ? "" : "s") you've drawn")
                .tremorType(.footnote, numeric: true)
                .foregroundStyle(TremorColor.inkSecondary)
            HStack(spacing: TremorSpacing.md) {
                skyKey(TremorColor.accent, "Hazard")
                skyKey(TremorColor.primarySoft, "Climbable")
                HStack(spacing: 5) {
                    Capsule().fill(TremorColor.ink.opacity(0.75)).frame(width: 14, height: 3)
                    Text("Your fix plan").tremorType(.caption).foregroundStyle(TremorColor.inkSecondary)
                }
            }
            HStack(spacing: TremorSpacing.xs) {
                TremorButton("Show paths", variant: .accent, size: .medium) {
                    showPaths()
                }
                TremorButton("Checklist", variant: .secondary, size: .medium) {
                    onOpenChecklist()
                }
            }
        }
        .padding(TremorSpacing.lg)
        .background(RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous).fill(TremorColor.surface))
    }

    private func skyKey(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color)
                .overlay(Circle().stroke(TremorColor.ink.opacity(0.45), lineWidth: 0.75))
                .frame(width: 9, height: 9)
            Text(title).tremorType(.caption).foregroundStyle(TremorColor.inkSecondary)
        }
    }

    /// Three marks, three meanings. Small enough to read in a glance.
    private var legend: some View {
        HStack(spacing: TremorSpacing.md) {
            legendItem(TremorColor.accent, glow: true, "Reachable by climbing")
            legendItem(TremorColor.primarySoft, glow: true, "A step up")
            legendItem(TremorColor.inkInverse.opacity(0.8), glow: false, "Other flags")
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.vertical, TremorSpacing.xs)
        .background(Capsule().fill(.ultraThinMaterial))
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ color: Color, glow: Bool, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: glow ? 9 : 6, height: glow ? 9 : 6)
                .shadow(color: glow ? color : .clear, radius: 4)
            Text(title)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkInverse)
                .lineLimit(1)
        }
    }

    /// Camera and lighting — useful, but not something a first-time viewer needs to see.
    private var moreMenu: some View {
        Menu {
            Section("Camera") {
                ForEach(DemoCameraMode.allCases) { mode in
                    Button {
                        model.setMode(mode)
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            }
            Button {
                dimsRoom.toggle()
            } label: {
                Label(dimsRoom ? "Brighten the room" : "Dim the room",
                      systemImage: dimsRoom ? "sun.max" : "moon.stars")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TremorColor.inkInverse)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .accessibilityLabel("More")
    }

    private var stagePicker: some View {
        HStack(spacing: 4) {
            ForEach(AgeStage.allCases) { stage in
                Button {
                    TremorHaptic.light.play()
                    sky.setStage(stage)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: stage.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(stage.title).tremorType(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TremorSpacing.xs)
                    .foregroundStyle(sky.stage == stage ? TremorColor.ink : TremorColor.inkInverse.opacity(0.72))
                    .background {
                        if sky.stage == stage {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TremorColor.inkInverse)
                        }
                    }
                }
                .accessibilityAddTraits(sky.stage == stage ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Age stage")
    }

    private var pullCard: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Illustrative, not a prediction")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)
                Spacer()
                if case .running = pull.phase {
                    ProgressView().controlSize(.small)
                }
            }

            switch pull.phase {
            case .running:
                Text(pull.assumptions?.anchored == true
                     ? "The same pull, with it anchored…"
                     : "A child pulls on the \(pull.assumptions?.objectName.lowercased() ?? "object")…")
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.ink)
            case .finished(let outcome):
                outcomeText(outcome)
            case .idle:
                EmptyView()
            }

            if let a = pull.assumptions {
                Text(String(format: "Assumed: a hand at %.2f m pulling up to %.0f N, no faster than %.1f m/s, over %.0f cm · %@ %.0f kg (model's estimate)%@",
                            a.pullHeight, a.pullNewtons, a.handSpeed, a.handTravel * 100,
                            a.objectName.lowercased(), a.massKg,
                            a.anchored ? " · held fixed as if anchored" : " · not anchored"))
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("A real-time physics sketch on the model's shapes. It does not change any flag.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if case .finished(let outcome) = pull.phase, let id = pull.targetID, let a = pull.assumptions {
                HStack(spacing: TremorSpacing.xs) {
                    // The anchored rerun only means something as a contrast to a fall.
                    if a.anchored || outcome.tipped {
                        TremorButton(a.anchored ? "Unanchor" : "Anchor it",
                                     variant: .secondary, size: .medium) {
                            startPull(id, anchored: !a.anchored)
                        }
                    }
                    TremorButton("Reset", variant: .primary, size: .medium) {
                        pull.reset()
                    }
                }
            }
        }
        .padding(TremorSpacing.lg)
        .background(RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous).fill(TremorColor.surface))
    }

    @ViewBuilder
    private func outcomeText(_ outcome: PullTest.Outcome) -> some View {
        let anchored = pull.assumptions?.anchored == true
        let name = pull.assumptions?.objectName ?? "It"
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(anchored
                 ? (outcome.tipped ? "\(name) still tipped" : "Anchored, it stayed put")
                 : (outcome.tipped ? "\(name) tipped over" : String(format: "It rocked %.0f° but didn't tip", outcome.peakLean)))
                .tremorType(.title3)
                .foregroundStyle(TremorColor.ink)
            if !outcome.fellNames.isEmpty || !outcome.brokeNames.isEmpty {
                Text(summary(outcome))
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !anchored && outcome.tipped {
                Label("Consider: anchor furniture to the wall", systemImage: "link")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.primary)
            }
        }
    }

    private func summary(_ outcome: PullTest.Outcome) -> String {
        var parts: [String] = []
        if !outcome.fellNames.isEmpty {
            parts.append("\(outcome.fellNames.count) thing\(outcome.fellNames.count == 1 ? "" : "s") came down")
        }
        if !outcome.brokeNames.isEmpty {
            parts.append("\(outcome.brokeNames.count) broke")
        }
        return parts.joined(separator: " · ") + "."
    }

    private func chainCard(_ chain: Chain) -> some View {
        let index = (sky.paths.firstIndex { $0.id == chain.id } ?? 0) + 1
        let count = sky.paths.count
        return VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            HStack {
                Text("Climbing path \(index) of \(count)")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)
                Spacer()
                Button { sky.light(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TremorColor.inkSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close")
            }
            Text(sky.sentence(for: chain))
                .tremorType(.title3)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Measured: " + sky.measurements(for: chain) + ". Not reachable from the floor alone.")
                .tremorType(.footnote, numeric: true)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TremorSpacing.xs) {
                if count > 1 {
                    TremorButton("Next path", variant: .secondary, size: .medium) {
                        sky.lightNextChain()
                    }
                }
                TremorButton("Fix plan", variant: .primary, size: .medium, leadingIcon: "plus") {
                    pendingPlanStars = chain.nodeIDs
                    newPlanName = "Move the \(ConstellationModel.plain(sky.analysis.object(chain.nodeIDs.first ?? "")?.label ?? "furniture"))"
                    showsNewPlan = true
                }
            }
        }
        .padding(TremorSpacing.lg)
        .background(RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous).fill(TremorColor.surface))
    }
}

// MARK: - Chain steps

/// The measured steps of one chain, as a vertical list a person can check with a tape.
struct ChainSteps: View {
    let chain: Chain
    let analysis: SafetyAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            row(symbol: "square.bottomhalf.filled", title: "Floor", detail: nil)
            ForEach(Array(chain.relations.enumerated()), id: \.offset) { _, relation in
                let name = analysis.object(relation.toID)?.label ?? relation.toID
                if relation.kind == .climbStep {
                    row(symbol: "arrow.up.right", title: name,
                        detail: String(format: "stand at %.2f m · step %.2f m%@",
                                       relation.surfaceHeight ?? 0, relation.rise ?? 0,
                                       gapText(relation.gap)))
                } else {
                    row(symbol: "hand.point.up.left.fill", title: name,
                        detail: String(format: "%.2f m above%@ · in reach",
                                       relation.rise ?? 0, gapText(relation.gap)))
                }
            }
        }
    }

    private func gapText(_ gap: Float?) -> String {
        guard let gap, gap > 0.005 else { return "" }
        return String(format: ", %.2f m across", gap)
    }

    private func row(symbol: String, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TremorColor.primary)
                .frame(width: 18)
            Text(title).tremorType(.subheadline).foregroundStyle(TremorColor.ink)
            if let detail {
                Text(detail).tremorType(.caption, numeric: true).foregroundStyle(TremorColor.inkTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Star card

/// What was flagged on one star, and what the caregiver can do about it.
private struct StarCard: View {
    let id: String
    let sky: ConstellationModel
    let scene: ApartmentScene?
    var onClose: () -> Void
    var onPull: () -> Void
    var onNewPlan: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            if let object = sky.analysis.object(id) {
                starContent(object)
            } else if sky.removedObjects.contains(where: { $0.id == id }) {
                removedContent
            } else {
                addContent
            }
        }
        .padding(TremorSpacing.lg)
        .background(RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous).fill(TremorColor.surface))
    }

    private func header(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle).tremorType(.overline).foregroundStyle(TremorColor.inkTertiary)
                Text(title).tremorType(.title3).foregroundStyle(TremorColor.ink)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TremorColor.inkSecondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private func starContent(_ object: SceneObject) -> some View {
        let flags = sky.analysis.flags(for: object.id)
        let chains = sky.analysis.chains(through: object.id)
        let kinds = flags.map(\.kind).reduce(into: [HazardKind]()) { if !$0.contains($1) { $0.append($1) } }

        header(object.label, subtitle: sky.reachPhrase(object))

        // What it is and what to do, in one or two plain lines.
        if kinds.isEmpty {
            Text(String(format: "A child can stand on it at %.2f m. On its own it isn't a hazard — it's a step.",
                        SafetyEngine.standableSurfaces(of: object).last ?? object.topHeight))
                .tremorType(.footnote).foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                ForEach(kinds.prefix(2)) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.ink)
                }
                if let fix = kinds.first?.fixTypes.first {
                    Text("Consider: \(fix.lowercased()).")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                }
            }
        }

        // One obvious next step.
        if let chain = chains.first {
            TremorButton("Show the climbing path", variant: .accent, size: .medium,
                         leadingIcon: "figure.climbing") {
                sky.setMode(.paths)
                sky.light(chain.id)
            }
        }
        if PullTest.canPull(object.id, in: scene) {
            TremorButton("What if a child pulls on it?",
                         variant: chains.isEmpty ? .accent : .secondary, size: .medium,
                         leadingIcon: "hand.raised.fill",
                         hint: "Runs an illustrative physics sketch of a pull") {
                onPull()
            }
        }

        HStack(spacing: TremorSpacing.xs) {
            if !flags.isEmpty {
                let done = sky.isObjectDone(object.id)
                Button {
                    sky.toggleObjectDone(object.id)
                } label: {
                    Label(done ? "Done" : "Mark done", systemImage: done ? "checkmark.circle.fill" : "circle")
                        .tremorType(.subheadline)
                        .foregroundStyle(done ? TremorColor.success : TremorColor.primary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("New fix plan with this…") { onNewPlan([object.id] + linkedIDs(object.id)) }
                if !sky.constellations.isEmpty {
                    Menu("Add to a fix plan") {
                        ForEach(sky.constellations) { constellation in
                            Button(constellation.name) { sky.addStar(object.id, toConstellation: constellation.id) }
                        }
                    }
                }
                Button("Link to another flag") {
                    sky.beginLink(from: object.id)
                    sky.selectedID = nil
                }
                Divider()
                Button("Not a hazard — remove", role: .destructive) { sky.remove(object.id) }
                if object.source != .userAdded {
                    Text("Found by SAM 3 as “\(object.concept)”")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.inkSecondary)
            }
        }
    }

    /// Stars this one is linked to by hand — grouped together when it starts a plan.
    private func linkedIDs(_ id: String) -> [String] {
        sky.analysis.relations.filter { $0.kind == .userLink }.compactMap { link in
            if link.fromID == id { return link.toID }
            if link.toID == id { return link.fromID }
            return nil
        }
    }

    @ViewBuilder
    private var removedContent: some View {
        let label = sky.removedObjects.first { $0.id == id }?.label ?? "This object"
        header(label, subtitle: "Removed by you")
        Text("You said this isn't a hazard. Its flags no longer count.")
            .tremorType(.footnote).foregroundStyle(TremorColor.inkSecondary)
        TremorButton("Put it back", variant: .secondary, size: .medium, leadingIcon: "arrow.uturn.backward") {
            sky.restore(id)
        }
    }

    @ViewBuilder
    private var addContent: some View {
        let found = sky.bounds(forProp: id, in: scene)
        header(found?.label ?? "Object", subtitle: "Not flagged")
        Text("proof did not flag this. If it matters for your child, add it — you know the room better than the scan does.")
            .tremorType(.footnote).foregroundStyle(TremorColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if let found {
            Menu {
                ForEach(HazardKind.allCases) { kind in
                    Button {
                        sky.addStar(objectID: id, label: found.label, hazard: kind, aabb: found.aabb)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label("Flag it", systemImage: "plus")
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: TremorSize.buttonMedium)
                    .background(Capsule().fill(TremorColor.primary))
            }
        }
    }
}

/// A small rounded tag.
struct Badge: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(title).tremorType(.caption)
        }
        .foregroundStyle(TremorColor.inkSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(TremorColor.surfaceSunken))
    }
}
