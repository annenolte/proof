import AVKit
import SwiftUI

// The scripted investor demo.
//
//   tap  →  watch the walkthrough  →  confirm  →  reconstruction  →  explore  →  shake
//
// The reconstruction is pre-built: the apartment is authored geometry, not the output of
// a pipeline run on the phone. The progress steps below name the work a real pipeline
// would do, and the screen does not claim to be doing it live.

struct DemoFlowView: View {
    @State private var model = DemoRoomModel()
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            switch model.phase {
            case .intro:
                DemoIntroView { model.reviewScan() }
                    .transition(.opacity)
            case .reviewing:
                DemoScanReviewView(
                    onConfirm: { model.confirmScan() },
                    onRetake: { model.begin() }
                )
                .transition(.opacity)
            case .generating:
                DemoGeneratingView(
                    isRoomReady: model.isSceneReady,
                    onDone: { model.finishGenerating() }
                )
                .transition(.opacity)
            case .exploring, .shaking, .results:
                DemoExplorerView(model: model) { router.pop() }
                    .transition(.opacity)
            }
        }
        .animation(TremorMotion.sheet, value: model.phase)
        .toolbar(.hidden, for: .navigationBar)
        // Start building immediately. Rasterising the textures takes several seconds in a
        // debug build, and the only way the generating screen can be a short, honest
        // animation rather than a stall is if the work is already well under way by the
        // time the user reaches it.
        .task {
            if await model.applyLaunchOverride() { return }
            await model.prepareScene()
        }
    }
}

// MARK: - 1. Intro

private struct DemoIntroView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                Text("Scan a room")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.inkTertiary)

                Text("Walk your room once.\nWatch the earthquake.")
                    .tremorType(.displayM)
                    .foregroundStyle(TremorColor.ink)

                Text("Record a slow lap of the room on any phone. proof rebuilds it in 3D, then shakes it with a real earthquake record so you can see exactly what falls.")
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.inkSecondary)
            }

            Spacer(minLength: TremorSpacing.section)

            TremorButton("Start a scan", leadingIcon: "video.fill") { onStart() }
        }
        .tremorScreen()
        .background(TremorColor.canvas.ignoresSafeArea())
    }
}

// MARK: - 2. Review the capture

private struct DemoScanReviewView: View {
    var onConfirm: () -> Void
    var onRetake: () -> Void

    @State private var player: AVPlayer?
    @State private var hasWatched = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your walkthrough")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                Spacer()
                Text("0:10")
                    .tremorType(.footnote, numeric: true)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.bottom, TremorSpacing.md)

            ZStack {
                RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous)
                    .fill(TremorColor.ink)
                if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous))
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .padding(.horizontal, TremorSpacing.pageInset)
            .tremorShadow(.card)

            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Label("Good coverage — all four walls seen", systemImage: "checkmark.circle.fill")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.success)
                Label("Kitchen, dining and living areas detected", systemImage: "checkmark.circle.fill")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.success)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.lg)

            Spacer(minLength: TremorSpacing.lg)

            VStack(spacing: TremorSpacing.sm) {
                TremorButton("Use this scan", trailingIcon: "arrow.right") { onConfirm() }
                TremorButton("Record again", variant: .tertiary) { onRetake() }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .padding(.top, TremorSpacing.xl)
        .background(TremorColor.canvas.ignoresSafeArea())
        .task {
            guard player == nil,
                  let url = Bundle.main.url(forResource: "DemoRoomScan", withExtension: "mp4")
            else { return }
            let item = AVPlayer(url: url)
            item.isMuted = true
            player = item
            item.play()
            // Loop, so the clip is still moving whenever the presenter gets to it.
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item.currentItem, queue: .main
            ) { _ in
                item.seek(to: .zero)
                item.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - 3. Reconstruction

/// The reconstruction screen: a wireframe room assembling itself while a scripted
/// checklist names the work a real pipeline would do.
///
/// Shared by the scripted demo (S-22) and by the consumer Add Room flow, which is why it
/// owns no model. It knows two things — how long the script should take, and whether the
/// room has finished building — and it holds until **both** are satisfied. A room that
/// builds in three seconds still gets the full script, because a reconstruction that
/// finishes instantly reads as a stub rather than as work; and a script that finishes
/// first leaves its last step spinning rather than ticking it off, because a completed
/// checklist sitting on screen is the one thing here that would read as a hang.
///
/// It does not start the build. Whoever hosts it does that far earlier — while the user is
/// still filming — and only reports readiness here.
struct DemoGeneratingView: View {

    /// How long the scripted checklist takes end to end. The step cadence below is scaled
    /// to fit, so the rhythm is the same at 7 s and at 10 s.
    var totalSeconds: Double = DemoGeneratingView.defaultTotalSeconds
    /// True once the 3D room exists. The screen will not finish before this is true.
    var isRoomReady: Bool
    /// Copy under the title. The consumer flow names the room; the demo names the cloud.
    var subtitle: String = "This normally runs in the cloud in about a minute."
    var onDone: () -> Void

    @State private var stepIndex = 0
    @State private var scriptFinished = false
    @State private var hasFinished = false

    /// The default cadence, and the demo's original one.
    static let defaultTotalSeconds: Double = 7.0

    /// The steps a real reconstruction would run, with the relative cadence the demo plays
    /// them at. The weights sum to `defaultTotalSeconds`.
    private static let steps: [(String, String, Double)] = [
        ("Reading the walkthrough", "305 frames · 1080 × 1920", 1.0),
        ("Recovering camera poses", "Structure from motion", 1.3),
        ("Fitting Gaussian splats", "3D Gaussian splatting", 2.0),
        ("Segmenting with SAM 3", "\(ConceptCatalog.nounPhrases.count) concept prompts", 1.8),
        ("Lifting masks into 3D", "\(KitchenScene.bundled()?.objects.count ?? 0) objects found and placed", 1.2),
        ("Measuring reach and climb", "Floor, scale and surfaces", 0.9)
    ]

    private var isComplete: Bool { scriptFinished && isRoomReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Building your room")
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .padding(.bottom, TremorSpacing.xs)

            Text(subtitle)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)


            ReconstructionFigure(progress: progress)
                .frame(height: Self.figureHeight)
                .padding(.vertical, TremorSpacing.xl)

            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    GeneratingStepRow(
                        title: step.0,
                        detail: step.1,
                        state: index < stepIndex ? .done : (index == stepIndex ? .active : .pending),
                        isLast: index == Self.steps.count - 1
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .tremorScreen()
        .background(TremorColor.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Building your room")
        .accessibilityAddTraits(.updatesFrequently)
        .task { await runScript() }
        // Fires when the script lands and again when the room lands, in whichever order
        // they happen; `hasFinished` makes the second one a no-op.
        .onChange(of: isComplete, initial: true) { _, complete in
            guard complete, !hasFinished else { return }
            hasFinished = true
            Task { await finish() }
        }
    }

    private var progress: Double {
        Double(stepIndex) / Double(Self.steps.count)
    }

    private func runScript() async {
        let scale = totalSeconds / Self.steps.reduce(0) { $0 + $1.2 }
        for (index, step) in Self.steps.enumerated() {
            withAnimation(TremorMotion.change) { stepIndex = index }
            try? await Task.sleep(for: .seconds(step.2 * scale))
        }
        scriptFinished = true
    }

    /// Ticks the last step off, holds it just long enough to be read as completion rather
    /// than as a cut, and hands over.
    private func finish() async {
        withAnimation(TremorMotion.change) { stepIndex = Self.steps.count }
        try? await Task.sleep(for: .seconds(Self.completionHoldSeconds))
        onDone()
    }

    private static let figureHeight: CGFloat = 240
    private static let completionHoldSeconds: Double = 0.35
}

/// A wireframe room drawing itself in — vertices first, then edges, then surfaces.
struct ReconstructionFigure: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, size: size, time: t)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) * 0.42
        let spin = time * 0.28

        // An isometric box standing in for the apartment's proportions.
        let w: Double = 0.5, d: Double = 1.0, h: Double = 0.32
        let corners: [SIMD3<Double>] = [
            SIMD3(-w, 0, -d), SIMD3(w, 0, -d), SIMD3(w, 0, d), SIMD3(-w, 0, d),
            SIMD3(-w, h, -d), SIMD3(w, h, -d), SIMD3(w, h, d), SIMD3(-w, h, d)
        ]

        func project(_ p: SIMD3<Double>) -> CGPoint {
            let cs = cos(spin), sn = sin(spin)
            let x = p.x * cs - p.z * sn
            let z = p.x * sn + p.z * cs
            let iso = CGPoint(
                x: (x - z) * 0.86,
                y: (x + z) * 0.42 - p.y * 1.35
            )
            return CGPoint(x: centre.x + iso.x * scale, y: centre.y + iso.y * scale)
        }

        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]

        // Floor fill arrives last, once the "surfaces" step is under way.
        if progress > 0.5 {
            var floor = Path()
            floor.move(to: project(corners[0]))
            for i in [1, 2, 3] { floor.addLine(to: project(corners[i])) }
            floor.closeSubpath()
            context.fill(floor, with: .color(TremorColor.primary.opacity(0.10 * min((progress - 0.5) * 4, 1))))
        }

        let edgeReveal = min(progress * 1.8, 1)
        for (index, edge) in edges.enumerated() {
            guard Double(index) / Double(edges.count) < edgeReveal else { continue }
            var path = Path()
            path.move(to: project(corners[edge.0]))
            path.addLine(to: project(corners[edge.1]))
            context.stroke(
                path,
                with: .color(TremorColor.primary.opacity(0.75)),
                lineWidth: 1.5
            )
        }

        // Seeded so the animation is the same every run.
        var seed: UInt64 = 0x9E37_79B9
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 100_000) / 100_000
        }

        let steps = 6.0
        let splat = min(max((progress * steps - 2) , 0), 1)   // step 3: Gaussian splatting
        let masks = min(max((progress * steps - 3), 0), 1)    // step 4: SAM 3
        let stars = min(max((progress * steps - 4), 0), 1)    // step 5: lifted to 3D

        // Sparse points while the poses are recovered, then soft Gaussians filling in.
        let palette: [Color] = [
            Color(red: 0.78, green: 0.64, blue: 0.48), Color(red: 0.92, green: 0.91, blue: 0.88),
            Color(red: 0.55, green: 0.53, blue: 0.56), Color(red: 0.36, green: 0.27, blue: 0.22),
            TremorColor.primarySoft
        ]
        let pointCount = Int(90 * min(progress * 3, 1)) + Int(260 * splat)
        for i in 0..<pointCount {
            let px = (next() - 0.5) * 2 * w
            let py = next() * h * (next() < 0.6 ? 0.25 : 1)
            let pz = (next() - 0.5) * 2 * d
            let colour = palette[Int(next() * Double(palette.count)) % palette.count]
            let point = project(SIMD3(px, py, pz))
            if i < 90 {
                let twinkle = 0.35 + 0.4 * sin(time * 3 + Double(i))
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)),
                    with: .color(TremorColor.accent.opacity(twinkle * (1 - splat * 0.7))))
            } else {
                let rx = 3 + next() * 7, ry = 2 + next() * 4
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - rx, y: point.y - ry, width: rx * 2, height: ry * 2)),
                    with: .radialGradient(Gradient(colors: [colour.opacity(0.55), colour.opacity(0)]),
                                          center: point, startRadius: 0, endRadius: max(rx, ry)))
            }
        }

        // SAM 3 masks: one tinted box per concept, outlined as it is found.
        let objects: [(String, SIMD3<Double>, SIMD3<Double>, Bool)] = [
            ("counter", SIMD3(-0.50, 0, -1.0), SIMD3(-0.32, 0.12, 0.15), false),
            ("stove", SIMD3(-0.50, 0, -0.55), SIMD3(-0.32, 0.125, -0.30), true),
            ("kitchen island", SIMD3(-0.08, 0, -0.55), SIMD3(0.16, 0.12, -0.05), false),
            ("bar stool", SIMD3(0.22, 0, -0.38), SIMD3(0.32, 0.15, -0.26), true),
            ("dining table", SIMD3(-0.10, 0, 0.32), SIMD3(0.16, 0.09, 0.62), true),
            ("shelf", SIMD3(0.38, 0, 0.42), SIMD3(0.50, 0.30, 0.70), true),
        ]
        for (index, object) in objects.enumerated() {
            let reveal = min(max(masks * Double(objects.count) - Double(index), 0), 1)
            guard reveal > 0 else { continue }
            let (lo, hi) = (object.1, object.2)
            let top = [SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)]
            let front = [SIMD3(lo.x, 0, hi.z), SIMD3(hi.x, 0, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)]
            let side = [SIMD3(hi.x, 0, lo.z), SIMD3(hi.x, 0, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(hi.x, hi.y, lo.z)]
            let tint = object.3 ? TremorColor.accent : TremorColor.primarySoft
            for face in [side, front, top] {
                var path = Path()
                path.move(to: project(face[0]))
                for corner in face.dropFirst() { path.addLine(to: project(corner)) }
                path.closeSubpath()
                context.fill(path, with: .color(tint.opacity(0.28 * reveal)))
                context.stroke(path, with: .color(TremorColor.primary.opacity(0.9 * reveal)), lineWidth: 1)
            }
            let current = min(Int(masks * Double(objects.count)), objects.count - 1)
            if index == current && stars == 0 {
                let label = context.resolve(Text(object.0).font(TremorFont.font(.caption)).foregroundStyle(TremorColor.ink))
                let anchor = project(SIMD3((lo.x + hi.x) / 2, hi.y + 0.05, (lo.z + hi.z) / 2))
                context.opacity = reveal
                context.draw(label, at: CGPoint(x: anchor.x, y: anchor.y - 8))
                context.opacity = 1
            }
        }

        // Lifted into 3D: each object becomes a star, and the climb lines appear.
        guard stars > 0 else { return }
        let starPoints = objects.map { o in
            project(SIMD3((o.1.x + o.2.x) / 2, o.2.y + 0.04, (o.1.z + o.2.z) / 2))
        }
        context.opacity = stars
        var line = Path()
        line.move(to: starPoints[3]); line.addLine(to: starPoints[2])
        line.move(to: starPoints[4]); line.addLine(to: starPoints[5])
        context.stroke(line, with: .color(TremorColor.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 1.25, dash: [3, 3]))
        for (index, point) in starPoints.enumerated() {
            let tint = objects[index].3 ? TremorColor.accent : TremorColor.primarySoft
            let r = 3.5 + 1.2 * sin(time * 2.4 + Double(index))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(0.7), tint.opacity(0)]),
                                               center: point, startRadius: 0, endRadius: 10))
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(tint))
            context.stroke(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                           with: .color(TremorColor.ink.opacity(0.6)), lineWidth: 0.75)
        }
        context.opacity = 1
    }
}

private struct GeneratingStepRow: View {
    enum State { case pending, active, done }

    let title: String
    let detail: String
    let state: State
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(state == .pending ? TremorColor.surfaceSunken : TremorColor.primary)
                        .frame(width: 22, height: 22)
                    switch state {
                    case .done:
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TremorColor.onPrimary)
                    case .active:
                        ProgressView()
                            .controlSize(.mini)
                            .tint(TremorColor.onPrimary)
                    case .pending:
                        EmptyView()
                    }
                }
                if !isLast {
                    Rectangle()
                        .fill(state == .pending ? TremorColor.divider : TremorColor.primary.opacity(0.4))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .tremorType(state == .pending ? .body : .bodyEmphasis)
                    .foregroundStyle(state == .pending ? TremorColor.inkTertiary : TremorColor.ink)
                Text(detail)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            .padding(.bottom, isLast ? 0 : TremorSpacing.md)

            Spacer(minLength: 0)
        }
    }
}
