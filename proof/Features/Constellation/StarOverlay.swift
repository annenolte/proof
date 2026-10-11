//
//  StarOverlay.swift
//  proof — Features / Constellation
//
//  The sky drawn over the room: a star per object, lines for relationships, and a lit
//  chain that draws itself up from the floor.
//
//  The visual language — kept deliberately small, because a busy sky reads as noise:
//
//    bright lime star   — a hazard a child could reach only by climbing (the insight)
//    lavender star      — a step on one of those climbing paths
//    small white dot    — any other flag within reach
//    nothing            — out of reach at this stage, or not a hazard
//
//  Lines are off until asked for: the lit path draws itself up from the floor, and a
//  selected point shows only its own measured links.
//
//  Drawn in a `Canvas` from projected screen points the renderer hands over each frame.
//  The canvas takes no touches; the points' tap targets are separate, so dragging anywhere
//  else still orbits the room.
//

import SwiftUI

struct StarOverlay: View {

    let sky: ConstellationModel
    var onTapStar: (String) -> Void

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas(rendersAsynchronously: false) { context, size in
                    let elapsed = timeline.date.timeIntervalSince(sky.litChainStartedAt)
                    if sky.mode == .constellation && sky.litChainID == nil {
                        drawSky(&context, since: timeline.date.timeIntervalSince(sky.modeChangedAt))
                    } else {
                        draw(&context, size: size, elapsed: elapsed)
                    }
                }
            }
            .allowsHitTesting(false)

            ForEach(sky.visibleStars) { star in
                if let point = sky.projected[star.id] {
                    Button {
                        onTapStar(star.id)
                    } label: {
                        Color.clear.frame(width: 30, height: 30).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(point)
                    .accessibilityLabel(star.label)
                    .accessibilityHint("Shows what proof flagged here")
                }
            }
        }
    }

    // MARK: The whole sky

    /// Every flag a star, every measured step or reach a line, every fix plan a named
    /// constellation. The stars fade in one by one across the room, then the lines join
    /// them, then the caregiver's constellations draw over the top.
    private func drawSky(_ context: inout GraphicsContext, since: TimeInterval) {
        let p = sky.projected
        // Sweep across the room, so the arrival reads as a sky coming out.
        let stars = sky.stars.sorted { ($0.centroid.x + $0.centroid.z) < ($1.centroid.x + $1.centroid.z) }
        var order: [String: Int] = [:]
        for (i, star) in stars.enumerated() { order[star.id] = i }
        func starAlpha(_ id: String) -> Double {
            let delay = 0.25 + Double(order[id] ?? 0) * 0.022
            return min(1, max(0, (since - delay) / 0.35))
        }
        let lineAlpha = min(1, max(0, (since - 1.4) / 0.7))
        let planAlpha = min(1, max(0, (since - 2.0) / 0.7))

        // Measured links.
        if lineAlpha > 0 {
            for relation in sky.analysis.relations {
                guard let from = relation.fromID, from != relation.toID,
                      let a = p[from], let b = p[relation.toID] else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                switch relation.kind {
                case .climbStep:
                    context.stroke(path, with: .color(TremorColor.primarySoft.opacity(0.55 * lineAlpha)),
                                   style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                case .reach:
                    context.stroke(path, with: .color(TremorColor.accent.opacity(0.65 * lineAlpha)),
                                   style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [3, 4]))
                case .cluster:
                    // Hazards close together — the faint web that makes it read as a sky.
                    context.stroke(path, with: .color(TremorColor.inkInverse.opacity(0.38 * lineAlpha)),
                                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                case .userLink:
                    context.stroke(path, with: .color(TremorColor.inkInverse.opacity(0.95 * lineAlpha)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                }
            }
        }

        // The caregiver's constellations: their stars joined in order, with the name.
        if planAlpha > 0 {
            for plan in sky.constellations {
                let points = plan.starIDs.compactMap { p[$0] }
                guard points.count > 1 else { continue }
                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                let tint = plan.status == .done ? TremorColor.success : TremorColor.inkInverse
                context.stroke(path, with: .color(tint.opacity(0.35 * planAlpha)),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(tint.opacity(0.95 * planAlpha)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // Named at its last star — the hazard end — so plans that share a first step
                // do not stack their names on top of each other.
                let end = points[points.count - 1]
                let saved = context.opacity
                context.opacity = planAlpha
                drawLabel((plan.status == .done ? "✓ " : "✦ ") + plan.name,
                          at: CGPoint(x: end.x, y: end.y - 10), in: &context)
                context.opacity = saved
            }
        }

        // A pending link follows from its first point.
        if sky.isLinking, let start = sky.linkStartID, let a = p[start] {
            context.stroke(Path(ellipseIn: CGRect(x: a.x - 16, y: a.y - 16, width: 32, height: 32)),
                           with: .color(TremorColor.inkInverse),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }

        // Stars: lime for hazards, lavender for things a child climbs.
        for star in stars {
            guard let point = p[star.id] else { continue }
            let alpha = starAlpha(star.id)
            guard alpha > 0 else { continue }
            let tone: ConstellationModel.Tone = star.role.isHazard ? .pathHazard : .pathStep
            context.opacity = alpha
            drawStar(star, tone: tone, at: point, emphasised: star.id == sky.selectedID,
                     dimmed: false, elapsed: since, in: &context, breathes: false,
                     scale: 0.8 + 0.4 * (1 - alpha) + (alpha < 1 ? 0.3 * sin(alpha * .pi) : 0))
            context.opacity = 1
        }

        if let selected = sky.selectedID, let point = p[selected], let star = sky.analysis.object(selected) {
            drawLabel(star.label, at: point, in: &context)
        }
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let p = sky.projected
        let selected = sky.selectedID
        let lit = sky.litIDs

        // Only the selected point's own measured links — never the whole web at once.
        if let selected, sky.litChainID == nil {
            for relation in sky.analysis.relations where relation.fromID == selected || relation.toID == selected {
                guard let from = relation.fromID, from != relation.toID,
                      let a = p[from], let b = p[relation.toID] else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                switch relation.kind {
                case .climbStep:
                    context.stroke(path, with: .color(TremorColor.primarySoft.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                case .reach:
                    context.stroke(path, with: .color(TremorColor.accent.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                case .userLink:
                    context.stroke(path, with: .color(TremorColor.inkInverse.opacity(0.95)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                case .cluster:
                    break
                }
            }
        }

        if let chain = sky.litChain {
            drawChain(chain, in: &context, elapsed: elapsed)
        }

        // A pending link follows from its first point.
        if sky.isLinking, let start = sky.linkStartID, let a = p[start] {
            context.stroke(Path(ellipseIn: CGRect(x: a.x - 16, y: a.y - 16, width: 32, height: 32)),
                           with: .color(TremorColor.inkInverse),
                           style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }

        // Quiet dots first, so the bright ones always sit on top.
        let stars = sky.visibleStars.sorted { rank(sky.tone(of: $0)) < rank(sky.tone(of: $1)) }
        for star in stars {
            guard let point = p[star.id] else { continue }
            let dimmed = sky.litChainID != nil && !lit.contains(star.id)
            drawStar(star, tone: sky.tone(of: star), at: point,
                     emphasised: star.id == selected || lit.contains(star.id),
                     dimmed: dimmed, elapsed: elapsed, in: &context)
        }

        if let selected, let point = p[selected], let star = sky.analysis.object(selected) {
            drawLabel(star.label, at: point, in: &context)
        }
    }

    private func rank(_ tone: ConstellationModel.Tone) -> Int {
        switch tone {
        case .hidden: return 0
        case .flag: return 1
        case .pathStep: return 2
        case .pathHazard: return 3
        }
    }

    private func drawStar(_ star: SceneObject, tone: ConstellationModel.Tone, at point: CGPoint,
                          emphasised: Bool, dimmed: Bool, elapsed: TimeInterval,
                          in context: inout GraphicsContext, breathes: Bool = true, scale: CGFloat = 1) {
        let entry = context.opacity
        context.opacity = entry * (dimmed ? 0.3 : 1)

        switch tone {
        case .flag, .hidden:
            // A quiet flag: a small soft dot, no glow, no twinkle.
            let r: CGFloat = emphasised ? 4.5 : 2.6
            let dot = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            context.fill(dot, with: .color(TremorColor.inkInverse.opacity(emphasised ? 1 : 0.75)))
            context.stroke(dot, with: .color(TremorColor.ink.opacity(0.4)), lineWidth: 0.5)

        case .pathStep, .pathHazard:
            let core: Color = tone == .pathHazard ? TremorColor.accent : TremorColor.primarySoft
            // Path hazards breathe slowly, so the eye finds them without being told.
            let breath = tone == .pathHazard && breathes ? 0.5 + 0.5 * sin(Date().timeIntervalSinceReferenceDate * 2.2) : 0
            let radius: CGFloat = (emphasised ? 6 : 4.5) * (breathes ? 1 : 0.85) * scale
            let glow: CGFloat = ((emphasised ? 22 : 15) + CGFloat(breath) * 4) * scale
            let halo = Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2))
            context.fill(halo, with: .radialGradient(
                Gradient(colors: [core.opacity(0.6), core.opacity(0)]),
                center: point, startRadius: 0, endRadius: glow))

            var spark = Path()
            let arm = radius * 2.4
            spark.move(to: CGPoint(x: point.x - arm, y: point.y))
            spark.addLine(to: CGPoint(x: point.x + arm, y: point.y))
            spark.move(to: CGPoint(x: point.x, y: point.y - arm))
            spark.addLine(to: CGPoint(x: point.x, y: point.y + arm))
            context.stroke(spark, with: .color(core.opacity(0.85)), lineWidth: 1)

            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(core))
            context.stroke(dot, with: .color(TremorColor.ink.opacity(0.55)), lineWidth: 0.75)
        }

        if star.source == .userAdded {
            let ring = Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
            context.stroke(ring, with: .color(TremorColor.inkInverse.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        if star.id == sky.selectedID {
            let ring = Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28))
            context.stroke(ring, with: .color(TremorColor.inkInverse), lineWidth: 2)
        }
        context.opacity = entry
    }

    /// The chain draws itself from the floor upward over `drawSeconds`, then a pulse keeps
    /// travelling along it so it reads as a path rather than as a shape.
    private func drawChain(_ chain: Chain, in context: inout GraphicsContext, elapsed: TimeInterval) {
        let p = sky.projected
        guard let first = chain.nodeIDs.first, let floor = sky.projectedFloor[first] else { return }
        var points = [floor]
        points += chain.nodeIDs.compactMap { p[$0] }
        guard points.count > 1 else { return }

        let drawSeconds = 1.4
        let progress = min(1, max(0, elapsed / drawSeconds))
        let eased = 1 - pow(1 - progress, 3)

        let segments = zip(points, points.dropFirst()).map { ($0, $1) }
        let lengths = segments.map { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return }

        var drawn = Path()
        drawn.move(to: points[0])
        var remaining = total * eased
        for (index, segment) in segments.enumerated() {
            let length = lengths[index]
            if remaining >= length {
                drawn.addLine(to: segment.1)
                remaining -= length
            } else {
                let f = length > 0 ? remaining / length : 0
                drawn.addLine(to: CGPoint(x: segment.0.x + (segment.1.x - segment.0.x) * f,
                                          y: segment.0.y + (segment.1.y - segment.0.y) * f))
                break
            }
        }

        context.stroke(drawn, with: .color(TremorColor.accent.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        context.stroke(drawn, with: .color(TremorColor.accent),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // The floor: a short horizon tick and a label, so "from the floor" is visible.
        var tick = Path()
        tick.move(to: CGPoint(x: floor.x - 14, y: floor.y))
        tick.addLine(to: CGPoint(x: floor.x + 14, y: floor.y))
        context.stroke(tick, with: .color(TremorColor.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        drawLabel("Floor", at: CGPoint(x: floor.x, y: floor.y + 30), in: &context)

        if progress >= 1 {
            let t = (elapsed - drawSeconds).truncatingRemainder(dividingBy: 2.0) / 2.0
            var target = total * t
            for (index, segment) in segments.enumerated() {
                let length = lengths[index]
                if target <= length {
                    let f = length > 0 ? target / length : 0
                    let q = CGPoint(x: segment.0.x + (segment.1.x - segment.0.x) * f,
                                    y: segment.0.y + (segment.1.y - segment.0.y) * f)
                    let r: CGFloat = 6
                    context.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                                 with: .color(TremorColor.inkInverse))
                    break
                }
                target -= length
            }

            // Just the hazard's name once the line arrives; the card says the rest.
            if let point = p[chain.hazardID], let hazard = sky.analysis.object(chain.hazardID) {
                let name = ConstellationModel.plain(hazard.label)
                drawLabel(name.prefix(1).uppercased() + name.dropFirst(), at: point, in: &context)
            }
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint, in context: inout GraphicsContext) {
        let label = Text(text)
            .font(TremorFont.font(.captionEmphasis))
            .foregroundStyle(TremorColor.ink)
        let resolved = context.resolve(label)
        let size = resolved.measure(in: CGSize(width: 260, height: 40))
        var rect = CGRect(x: point.x - size.width / 2 - 8, y: point.y - 34,
                          width: size.width + 16, height: size.height + 8)
        // Keep every label on screen, whatever the camera is doing.
        let bounds = context.clipBoundingRect.insetBy(dx: 8, dy: 8)
        if bounds.width > rect.width {
            rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        }
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
                     with: .color(TremorColor.inkInverse.opacity(0.94)))
        context.draw(resolved, in: rect.insetBy(dx: 8, dy: 4))
    }
}
