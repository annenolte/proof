import Combine
import RealityKit
import SwiftUI
import simd

// The room itself: a full-bleed graded 3D view with three camera modes and the earthquake.
//
// Two hosts drive this screen: the scripted demo (S-22), where the back chevron pops the
// navigation stack, and the consumer Add Room flow, where the room is the user's own and
// the quake is followed by a structured analysis. Everything the second host needs is a
// defaulted parameter, so the first one is untouched.

struct DemoExplorerView: View {
    @Bindable var model: DemoRoomModel
    var onExit: () -> Void

    /// What the capsule at the top of the screen calls this room. The demo apartment has a
    /// street address; a room the user just scanned has the name they typed.
    var roomTitle: String = DemoExplorerView.demoApartmentTitle

    /// Offered as the primary action on the results sheet when the host has an analysis to
    /// show. `nil` in the scripted demo, which ends at the results sheet.
    var onSeeAnalysis: (() -> Void)?

    @State private var padVector = CGSize.zero
    @State private var showsResults = false
    @State private var intensity: MercalliIntensity = .viii
    @State private var showsSite = false

    static let demoApartmentTitle = "Bristol Street · Unit 704"

    var body: some View {
        ZStack {
            // The room is cut open, so whatever sits behind it is visible. A soft studio
            // sweep reads as a presentation backdrop; a flat colour reads as a bug.
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.20, blue: 0.24),
                    Color(red: 0.44, green: 0.44, blue: 0.48),
                    Color(red: 0.30, green: 0.29, blue: 0.33)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            sceneLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if model.phase == .shaking {
                    shakeReadout
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, TremorSpacing.lg)
            .padding(.bottom, TremorSpacing.xl)
        }
        .animation(TremorMotion.change, value: model.phase)
        .sheet(isPresented: $showsResults) {
            DemoResultsSheet(
                quake: model.quake,
                clip: model.clip,
                intensity: $intensity,
                onSeeAnalysis: onSeeAnalysis.map { analysis in
                    {
                        showsResults = false
                        analysis()
                    }
                },
                onRunAgain: {
                    showsResults = false
                    // Put the furniture back before shaking it again, so the second run
                    // starts from the same room the first one did and the two are
                    // comparable. The reset needs a frame to land.
                    model.resetRoom()
                    Task {
                        try? await Task.sleep(for: .seconds(Self.rerunSettleSeconds))
                        model.startQuake(intensity: intensity)
                    }
                },
                onAftershock: {
                    showsResults = false
                    model.startAftershock()
                },
                onReset: {
                    showsResults = false
                    model.resetRoom()
                },
                onKeep: {
                    showsResults = false
                })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSite) {
            DemoSiteSheet(site: model.site) { event in
                showsSite = false
                // The intensity picker follows the event, so "Run again" afterwards stays
                // the same size of shaking.
                intensity = event.intensity
                model.startQuake(event: event)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: model.phase) { _, new in
            if new == .results { showsResults = true }
            // Whatever starts a shake — a button here, the site sheet, a launch argument —
            // the results of the last one must not sit over the room while it shakes.
            if new == .shaking { showsResults = false }
        }
    }

    // MARK: - Scene

    private var sceneLayer: some View {
        DemoRealityView(
            model: model,
            sceneReady: model.isSceneReady,
            settings: .off,
            onSimulate: applyPad
        )
    }

    /// Continuous walking, applied while the thumb rests on the pad.
    private func applyPad() {
        guard model.pose.mode == .walk, padVector != .zero else { return }
        let speed: Float = 0.030
        model.pose.moveWalker(
            forward: Float(-padVector.height) * speed * 0.06,
            strafe: Float(padVector.width) * speed * 0.06
        )
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .top) {
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TremorColor.inkInverse)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .accessibilityLabel("Back")

            Spacer()

            VStack(spacing: 2) {
                Text(roomTitle)
                    .tremorType(.captionEmphasis)
                    .foregroundStyle(TremorColor.inkInverse)
                if let id = model.selectedPropID,
                   let prop = model.scene?.props[id] {
                    Text(prop.name)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.accent)
                } else {
                    Text(model.modeHint)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkInverse.opacity(0.62))
                }
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.xs)
            .background(Capsule().fill(.ultraThinMaterial))

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, TremorSpacing.xs)
    }

    private var controls: some View {
        VStack(spacing: TremorSpacing.md) {
            if model.pose.mode == .walk {
                HStack {
                    MovementPad(vector: $padVector)
                    Spacer()
                }
            }

            modePicker
            siteChip
            IntensityPicker(selection: $intensity, onDarkScene: true)

            TremorButton(
                "Simulate earthquake",
                variant: .primary,
                leadingIcon: "waveform.path.ecg"
            ) {
                model.startQuake(intensity: intensity)
            }
        }
    }

    /// One line of chrome for the whole location feature: where the room is and the fault
    /// that matters. Everything else waits behind the tap, so the controls over the room
    /// stay as sparse as they were.
    private var siteChip: some View {
        Button {
            TremorHaptic.light.play()
            showsSite = true
        } label: {
            HStack(spacing: TremorSpacing.xs) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TremorColor.accent)
                Text(model.site.summary)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkInverse)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.62))
            }
            .padding(.horizontal, TremorSpacing.md)
            .padding(.vertical, TremorSpacing.xs)
            .background(Capsule().fill(.ultraThinMaterial))
        }
        .accessibilityLabel("Site: \(model.site.summary)")
        .accessibilityHint("Shows the real earthquakes for this location")
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(DemoCameraMode.allCases) { mode in
                Button {
                    TremorHaptic.light.play()
                    model.setMode(mode)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(mode.title)
                            .tremorType(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TremorSpacing.xs)
                    .foregroundStyle(
                        model.pose.mode == mode
                            ? TremorColor.ink
                            : TremorColor.inkInverse.opacity(0.72)
                    )
                    .background {
                        if model.pose.mode == mode {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(TremorColor.inkInverse)
                        }
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var shakeReadout: some View {
        VStack(spacing: TremorSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.quake.title)
                    .tremorType(.headline)
                    .foregroundStyle(TremorColor.inkInverse)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(String(format: "%.2f g", model.quake.currentAccelerationG))
                    .tremorType(.headline, numeric: true)
                    .foregroundStyle(TremorColor.accent)
            }

            AccelerationMeter(
                value: model.quake.currentAccelerationG,
                peak: model.quake.peakAccelerationG
            )

            if !model.quake.displaced.isEmpty {
                HStack(spacing: TremorSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(latestFailureText)
                        .tremorType(.caption)
                        .lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(TremorColor.accent)
                .transition(.opacity)
            }

            TremorButton("Stop", variant: .secondary, size: .medium) {
                model.stopQuake()
            }
        }
        .padding(TremorSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var latestFailureText: String {
        guard let last = model.quake.displaced.last else { return "" }
        return "\(last.name) \(last.kind.rawValue)"
    }

    /// A reset re-parents every prop and clears the solver state; starting the next quake
    /// in the same runloop turn would sample transforms that are on their way back.
    private static let rerunSettleSeconds: Double = 0.35
}

// MARK: - Intensity picker

/// Four intensities from "you would feel it" to "unreinforced masonry fails". Showing the
/// peak ground acceleration alongside the roman numeral is what turns this from a
/// difficulty slider into the actual USGS scale the report cites.
///
/// Used twice: floating over the 3D room before the first run, and on the results sheet so
/// the second run can be a different size without leaving the results.
private struct IntensityPicker: View {
    @Binding var selection: MercalliIntensity
    /// True over the graded 3D scene, where the unselected labels have to be light and the
    /// track is glass; false on the app's canvas, where they are ink and the track is
    /// sunken surface.
    var onDarkScene: Bool

    private static let intensities: [MercalliIntensity] = [.vi, .vii, .viii, .ix]

    var body: some View {
        HStack(spacing: TremorSpacing.xxs) {
            ForEach(Self.intensities, id: \.self) { option in
                Button {
                    TremorHaptic.light.play()
                    selection = option
                } label: {
                    VStack(spacing: TremorSpacing.hair / 2) {
                        Text(option.roman)
                            .tremorType(.captionEmphasis)
                        // Same notation as the results sheet and the report — see
                        // `RoomAnalysisView.gForce`.
                        Text(String(format: "%.2f g", option.representativePGAInG))
                            .tremorType(.caption, numeric: true)
                            .opacity(Self.pgaOpacity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TremorSpacing.xxs)
                    .foregroundStyle(foreground(for: option))
                    .background {
                        if selection == option {
                            RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
                                .fill(onDarkScene ? TremorColor.accent : TremorColor.ink)
                        }
                    }
                }
                .accessibilityLabel("Intensity \(option.roman)")
                .accessibilityValue(String(format: "%.2f g", option.representativePGAInG))
                .accessibilityAddTraits(selection == option ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(TremorSpacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: TremorRadius.input, style: .continuous)
                .fill(onDarkScene ? AnyShapeStyle(.ultraThinMaterial)
                                  : AnyShapeStyle(TremorColor.surfaceSunken))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Earthquake intensity")
    }

    private func foreground(for option: MercalliIntensity) -> Color {
        if selection == option { return onDarkScene ? TremorColor.ink : TremorColor.inkInverse }
        return onDarkScene ? TremorColor.inkInverse.opacity(Self.restingOpacity) : TremorColor.inkSecondary
    }

    private static let pgaOpacity: Double = 0.7
    private static let restingOpacity: Double = 0.7
}

// MARK: - Movement pad

/// A thumbstick for the walkthrough mode. Deliberately small and bottom-left, so the
/// right hand stays free to look around.
struct MovementPad: View {
    @Binding var vector: CGSize
    private let radius: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(TremorColor.inkInverse.opacity(0.22), lineWidth: 1))
            Circle()
                .fill(TremorColor.inkInverse.opacity(0.9))
                .frame(width: 34, height: 34)
                .offset(x: vector.width * 0.5, y: vector.height * 0.5)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TremorColor.ink.opacity(0.55))
                .offset(x: vector.width * 0.5, y: vector.height * 0.5)
        }
        .frame(width: radius * 2, height: radius * 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let length = sqrt(dx * dx + dy * dy)
                    let limit = radius
                    if length > limit {
                        vector = CGSize(width: dx / length * limit, height: dy / length * limit)
                    } else {
                        vector = CGSize(width: dx, height: dy)
                    }
                }
                .onEnded { _ in
                    withAnimation(TremorMotion.release) { vector = .zero }
                }
        )
        .accessibilityLabel("Move")
    }
}

// MARK: - Acceleration meter

private struct AccelerationMeter: View {
    let value: Double
    let peak: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // 1.2 g full scale covers everything up to MMI X.
            let fraction = min(value / 1.2, 1)
            let peakFraction = min(peak / 1.2, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TremorColor.inkInverse.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [TremorColor.accent, TremorColor.riskHighMark],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: width * fraction)
                Rectangle()
                    .fill(TremorColor.inkInverse.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: width * peakFraction - 1)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Results

/// What the earthquake did, and the three things a user wants next: the full analysis, a
/// second run at a different size, or the room put back.
private struct DemoResultsSheet: View {
    let quake: DemoQuake
    let clip: DemoClipRecorder
    /// The size the *next* run will be. Bound to the explorer so the picker on the sheet
    /// and the picker over the room are the same control.
    @Binding var intensity: MercalliIntensity
    /// Absent in the scripted demo, which has no analysis screen behind it.
    var onSeeAnalysis: (() -> Void)?

    /// Outcome glyphs. Breakage is the burst, matching the analysis screen, because a
    /// broken object is not a moved object and the two must never share a mark.
    static func glyph(for kind: DemoQuake.Displacement.Kind) -> String {
        switch kind {
        case .toppled: return "arrow.down.forward.circle.fill"
        case .slid: return "arrow.left.and.right.circle.fill"
        case .broke: return "burst.fill"
        }
    }

    /// "toppled at 3.1 s", or "toppled in aftershock 1, at 2.4 s".
    static func when(_ item: DemoQuake.Displacement) -> String {
        let time = String(format: "%.1f", item.time)
        guard item.shock > 0 else { return "\(item.kind.rawValue) at \(time) s" }
        return "\(item.kind.rawValue) in aftershock \(item.shock), at \(time) s"
    }

    static func tint(for kind: DemoQuake.Displacement.Kind) -> Color {
        switch kind {
        case .toppled: return TremorColor.riskHighMark
        case .slid: return TremorColor.riskModerateMark
        case .broke: return TremorColor.riskSevereMark
        }
    }

    var onRunAgain: () -> Void
    var onAftershock: () -> Void
    var onReset: () -> Void
    var onKeep: () -> Void

    /// "About M5.7 and 0.21 g here. It hits the room as it is now — nothing is put back."
    static func aftershockCaption(_ next: (number: Int, magnitude: Double?, pgaInG: Double)) -> String {
        let size = next.magnitude.map { String(format: "About M%.1f and ", $0) } ?? "About "
        let lead = next.number == 1
            ? "The largest aftershock is typically 1.2 magnitudes smaller. "
            : "Later aftershocks are smaller again. "
        return lead + size + String(format: "%.2f g here. ", next.pgaInG)
            + "It hits the room as it is now — nothing is put back."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    Text("\(quake.title) — \(quake.intensity.shakingLabel)")
                        .tremorType(.overline)
                        .foregroundStyle(TremorColor.inkTertiary)
                    Text(quake.summary)
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.ink)
                    Text("Peak ground acceleration \(String(format: "%.2f", quake.peakAccelerationG)) g")
                        .tremorType(.footnote, numeric: true)
                        .foregroundStyle(TremorColor.inkSecondary)
                    if quake.event != nil || quake.shock > 0 {
                        Label(quake.provenance,
                              systemImage: quake.isRecorded ? "waveform" : "waveform.path")
                            .tremorType(.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                    }
                }

                // Up here rather than after the list: at MMI VIII the list runs to thirty
                // rows, and a button below it is a button nobody finds.
                ClipButton(clip: clip)

                if !quake.displaced.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        TremorSectionHeader("What moved")
                        ForEach(quake.displaced) { item in
                            HStack(spacing: TremorSpacing.sm) {
                                // One glyph per outcome, including breakage. The headline
                                // above says "8 objects broke" and nothing in this list
                                // used to mark a single one of them — every row wore the
                                // amber "slid" arrows, so the list contradicted its own
                                // summary.
                                Image(systemName: Self.glyph(for: item.kind))
                                    .foregroundStyle(Self.tint(for: item.kind))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).tremorType(.body)
                                    Text(Self.when(item))
                                        .tremorType(.caption, numeric: true)
                                        .foregroundStyle(TremorColor.inkTertiary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, TremorSpacing.xs)
                            TremorRowDivider()
                        }
                    }
                }

                if let onSeeAnalysis {
                    TremorButton(
                        "See full analysis",
                        variant: .primary,
                        trailingIcon: "arrow.right",
                        hint: "What is dangerous, what to move, and this room's score"
                    ) { onSeeAnalysis() }
                }

                if let next = quake.nextAftershock {
                    VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                        TremorSectionHeader("Aftershock")
                        Text(Self.aftershockCaption(next))
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TremorButton(
                            next.number == 1 ? "Run the aftershock" : "Run aftershock \(next.number)",
                            variant: .secondary,
                            leadingIcon: "waveform.path.ecg"
                        ) { onAftershock() }
                    }
                }

                // Re-running at a different size is the point of the simulator, not an
                // afterthought: MMI VI and MMI IX are different rooms afterwards. The
                // picker lives here so the second run never costs a trip back out.
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    TremorSectionHeader("Try another size")
                    IntensityPicker(selection: $intensity, onDarkScene: false)
                    TremorButton(
                        "Run again at \(intensity.roman)",
                        variant: onSeeAnalysis == nil ? .primary : .secondary,
                        leadingIcon: "arrow.clockwise"
                    ) { onRunAgain() }
                }

                VStack(spacing: TremorSpacing.sm) {
                    TremorButton("Reset the room", variant: .tertiary) { onReset() }
                    TremorButton("Leave it as it fell", variant: .tertiary) { onKeep() }
                }
            }
            .padding(TremorSpacing.pageInset)
        }
        .background(TremorColor.canvas)
    }
}


// MARK: - Save clip

/// One button that follows the recording through its life: preparing while the file closes,
/// then save, then a quiet confirmation. It never offers a clip that does not exist.
private struct ClipButton: View {
    let clip: DemoClipRecorder

    private enum SaveState: Equatable { case none, saving, saved, denied, failed }
    @State private var saveState: SaveState = .none

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            switch clip.state {
            case .idle, .failed:
                EmptyView()
            case .recording, .finishing:
                TremorButton("Preparing clip…", variant: .secondary, leadingIcon: "video") {}
                    .disabled(true)
            case .ready(let url):
                TremorButton(
                    title,
                    variant: .secondary,
                    leadingIcon: saveState == .saved ? "checkmark.circle.fill" : "square.and.arrow.down"
                ) {
                    guard saveState != .saving, saveState != .saved else { return }
                    saveState = .saving
                    Task {
                        do {
                            try await DemoClipSaver.save(url)
                            saveState = .saved
                            TremorHaptic.light.play()
                        } catch DemoClipSaver.Failure.notAllowed {
                            saveState = .denied
                        } catch {
                            saveState = .failed
                        }
                    }
                }
                .disabled(saveState == .saving || saveState == .saved)

                if let note {
                    Text(note)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }
        }
        // A new run is a new clip; whatever happened to the last one no longer applies.
        .onChange(of: clip.state) { _, _ in saveState = .none }
    }

    private var title: String {
        switch saveState {
        case .saving: return "Saving…"
        case .saved: return "Saved to Photos"
        default: return "Save clip to Photos"
        }
    }

    private var note: String? {
        switch saveState {
        case .denied: return "proof needs permission to add to Photos. Turn it on in Settings › proof."
        case .failed: return "The clip could not be saved. Try again."
        default: return nil
        }
    }
}
