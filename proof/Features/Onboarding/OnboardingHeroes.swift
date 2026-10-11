//
//  OnboardingHeroes.swift
//  proof — Features / Onboarding
//
//  The three hero artifacts of SPEC §1.4 S-02. They are the reason the carousel
//  works: a static icon cannot say "your furniture falls over", and a stock
//  illustration would be a promise the app has to keep. These are drawn from the
//  same geometry the app actually simulates — the isometric room is the shape of
//  `RoomFixtures.dangerousBedroom` at its real dimensions in metres, and the
//  bookcase topples about its front bottom edge the way the rigid-block solver
//  says it does.
//
//  Every hero is a pure function of one number, `phase` ∈ [0, 1). No timers, no
//  state, no animation modifiers. `LoopingIllustration` supplies the phase and is
//  the only thing that knows about time — which is what makes Reduce Motion a
//  one-line concern (freeze the phase) rather than a rewrite.
//

import SwiftUI

// MARK: - Geometry

/// A point in the illustration's own coordinate space.
///
/// Deliberately `Double` rather than `CGPoint`: every one of these is the result
/// of trigonometry on a phase, and mixing `CGFloat` into those expressions costs
/// readability for nothing. It converts at the one place it has to — the `Path`.
private struct P {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    var cg: CGPoint { CGPoint(x: x, y: y) }

    /// Clockwise on screen, which is how a body falls to the right.
    func rotated(about pivot: P, by radians: Double) -> P {
        let dx = x - pivot.x
        let dy = y - pivot.y
        let c = cos(radians), s = sin(radians)
        return P(pivot.x + dx * c - dy * s, pivot.y + dx * s + dy * c)
    }
}

/// The 30° isometric used by the room hero.
///
/// x runs right-and-down, z runs left-and-down, y runs straight up — the same
/// projection the room viewer's overview camera uses, so the onboarding and the
/// app agree about what a room looks like.
private struct IsometricProjection {
    let scale: Double
    let originX: Double
    let originY: Double

    private static let cos30 = 0.866_025_4
    private static let sin30 = 0.5

    func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let sx = (x - z) * Self.cos30
        let sy = (x + z) * Self.sin30 - y
        return CGPoint(x: originX + sx * scale, y: originY + sy * scale)
    }
}

private extension Path {

    /// A polyline drawn only `progress` of the way along its own length, so a
    /// shape can appear to be *drawn* rather than to appear.
    static func partial(_ points: [CGPoint], closed: Bool, progress: Double) -> Path {
        var path = Path()
        guard points.count > 1, progress > 0 else { return path }

        var segments = Array(zip(points, points.dropFirst()))
        if closed, let first = points.first, let last = points.last {
            segments.append((last, first))
        }

        let lengths = segments.map { hypot(Double($1.x - $0.x), Double($1.y - $0.y)) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return path }

        let target = total * min(1, progress)
        var travelled = 0.0

        path.move(to: points[0])
        for (index, segment) in segments.enumerated() {
            let length = lengths[index]
            if travelled + length <= target {
                path.addLine(to: segment.1)
                travelled += length
            } else {
                let remaining = max(0, target - travelled)
                let fraction = length > 0 ? remaining / length : 0
                let x = Double(segment.0.x) + Double(segment.1.x - segment.0.x) * fraction
                let y = Double(segment.0.y) + Double(segment.1.y - segment.0.y) * fraction
                path.addLine(to: CGPoint(x: x, y: y))
                break
            }
        }
        return path
    }

    static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.addLine(to: d)
        path.closeSubpath()
        return path
    }

    static func quad(_ a: P, _ b: P, _ c: P, _ d: P) -> Path {
        quad(a.cg, b.cg, c.cg, d.cg)
    }
}

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * min(1, max(0, t))
}

// MARK: - Hero 1 — the room assembling itself

/// A wireframe room that builds itself: the floor outline draws, the two far
/// walls rise, a LiDAR sweep crosses the space, and the furniture grows up out
/// of the floor one piece at a time.
///
/// The furniture is the bedroom fixture's real footprint — bed, tall bookcase,
/// nightstand, dresser, floor lamp — at its real size in metres.
struct RoomAssemblyHero: View {

    let phase: Double

    /// Footprints in metres: centre (x, z), then width, height, depth, with the
    /// fixture's yaw already applied.
    private static let furniture: [(x: Double, z: Double, w: Double, h: Double, d: Double)] = [
        (-1.70, -1.40, 0.70, 1.82, 0.70),   // refrigerator
        (0.15, -1.50, 2.90, 0.92, 0.60),    // counter run
        (0.10, -0.05, 1.70, 0.92, 0.90),    // island
        (-0.45, 0.75, 0.45, 0.68, 0.45),    // counter stool
        (0.45, 0.75, 0.45, 0.68, 0.45),     // counter stool
        (1.80, 1.00, 0.35, 1.90, 0.90),     // ladder shelf
    ]

    /// Which pieces are hazards (lime star) rather than climbables (lavender star).
    private static let isHazard: [Bool] = [false, true, false, true, true, true]

    private static let roomWidth = 4.2
    private static let roomDepth = 3.6
    private static let roomHeight = 2.45

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let veil = Ease.loopVeil(phase, headEnd: 0.05, tailStart: 0.94)
            guard veil > 0.001, size.width > 0, size.height > 0 else { return }

            let width = Double(size.width)
            let height = Double(size.height)
            // The projected room is ~6.8 units wide and ~6.4 tall. Fitting it
            // inside the canvas leaves a dead band under the headline on a tall
            // phone, so it is fitted to a *narrower* box than the canvas and
            // allowed to bleed off the sides — which is the Zip pattern anyway.
            let iso = IsometricProjection(
                scale: min(width / 6.2, height / 6.5),
                originX: width / 2,
                originY: height * 0.56)

            context.opacity = veil
            draw(in: &context, iso: iso, veil: veil)
        }
    }

    private func draw(in context: inout GraphicsContext, iso: IsometricProjection, veil: Double) {
        let hw = Self.roomWidth / 2
        let hd = Self.roomDepth / 2

        let floorProgress = Ease.out(Ease.ramp(phase, 0.03, 0.26))
        let wallProgress = Ease.out(Ease.ramp(phase, 0.20, 0.44))

        // ── Floor plate ─────────────────────────────────────────────────
        let corners = [
            iso.point(-hw, 0, -hd), iso.point(hw, 0, -hd),
            iso.point(hw, 0, hd), iso.point(-hw, 0, hd),
        ]
        if floorProgress >= 1 {
            context.fill(Path.quad(corners[0], corners[1], corners[2], corners[3]),
                         with: .color(TremorColor.primary.opacity(0.16)))
        }
        context.stroke(Path.partial(corners, closed: true, progress: floorProgress),
                       with: .color(TremorColor.primarySoft.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // A half-metre grid, so the plate reads as measured rather than drawn.
        if floorProgress > 0.6 {
            var grid = Path()
            var offset = -hw + 0.7
            while offset < hw {
                grid.move(to: iso.point(offset, 0, -hd))
                grid.addLine(to: iso.point(offset, 0, hd))
                offset += 0.7
            }
            offset = -hd + 0.7
            while offset < hd {
                grid.move(to: iso.point(-hw, 0, offset))
                grid.addLine(to: iso.point(hw, 0, offset))
                offset += 0.7
            }
            context.stroke(grid,
                           with: .color(TremorColor.primarySoft.opacity(0.16 * floorProgress)),
                           lineWidth: 0.75)
        }

        // ── The two far walls ───────────────────────────────────────────
        if wallProgress > 0 {
            let top = Self.roomHeight * wallProgress
            let north = Path.quad(iso.point(-hw, 0, -hd), iso.point(hw, 0, -hd),
                                  iso.point(hw, top, -hd), iso.point(-hw, top, -hd))
            let west = Path.quad(iso.point(-hw, 0, -hd), iso.point(-hw, 0, hd),
                                 iso.point(-hw, top, hd), iso.point(-hw, top, -hd))
            context.fill(north, with: .color(TremorColor.primary.opacity(0.22)))
            context.fill(west, with: .color(TremorColor.primary.opacity(0.15)))
            context.stroke(north, with: .color(TremorColor.primarySoft.opacity(0.7)), lineWidth: 1)
            context.stroke(west, with: .color(TremorColor.primarySoft.opacity(0.7)), lineWidth: 1)
        }

        // ── The LiDAR sweep ─────────────────────────────────────────────
        let sweep = Ease.ramp(phase, 0.10, 0.56)
        if sweep > 0, sweep < 1 {
            let x = lerp(-hw, hw, sweep)
            let fade = sin(sweep * .pi)
            let top = Self.roomHeight * max(wallProgress, 0.15)
            let plane = Path.quad(iso.point(x, 0, -hd), iso.point(x, 0, hd),
                                  iso.point(x, top, hd), iso.point(x, top, -hd))
            // Outline only. A lime fill at any alpha over the ink field reads as
            // a murky brown panel rather than as a beam of light.
            context.stroke(plane, with: .color(TremorColor.accent.opacity(0.8 * fade)), lineWidth: 1.5)
        }

        // ── Furniture, back to front ────────────────────────────────────
        for (index, piece) in Self.furniture.enumerated() {
            let start = 0.36 + Double(index) * 0.06
            let appear = Ease.out(Ease.ramp(phase, start, start + 0.16))
            guard appear > 0.001 else { continue }
            drawBox(in: &context, iso: iso, piece: piece, appear: appear, veil: veil)
        }

        // ── Each object becomes a star ──────────────────────────────────
        for (index, piece) in Self.furniture.enumerated() {
            let start = 0.74 + Double(index) * 0.025
            let shine = Ease.out(Ease.ramp(phase, start, start + 0.06))
            guard shine > 0.001 else { continue }
            let point = iso.point(piece.x, piece.h + 0.12, piece.z)
            let tint = Self.isHazard[index] ? TremorColor.accent : TremorColor.primarySoft
            let glow = 16 * shine
            context.opacity = veil * shine
            context.fill(Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(0.7), tint.opacity(0)]),
                                               center: point, startRadius: 0, endRadius: glow))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                         with: .color(tint))
            context.opacity = veil
        }
    }

    private func drawBox(
        in context: inout GraphicsContext,
        iso: IsometricProjection,
        piece: (x: Double, z: Double, w: Double, h: Double, d: Double),
        appear: Double,
        veil: Double
    ) {
        let x0 = piece.x - piece.w / 2, x1 = piece.x + piece.w / 2
        let z0 = piece.z - piece.d / 2, z1 = piece.z + piece.d / 2
        let top = piece.h * appear

        let right = Path.quad(iso.point(x1, 0, z0), iso.point(x1, 0, z1),
                              iso.point(x1, top, z1), iso.point(x1, top, z0))
        let front = Path.quad(iso.point(x0, 0, z1), iso.point(x1, 0, z1),
                              iso.point(x1, top, z1), iso.point(x0, top, z1))
        let lid = Path.quad(iso.point(x0, top, z0), iso.point(x1, top, z0),
                            iso.point(x1, top, z1), iso.point(x0, top, z1))

        // The veil has to be reapplied rather than overwritten — the loop's fade
        // is a property of the whole frame, the appearance is a property of this
        // one box.
        context.opacity = veil * appear
        context.fill(right, with: .color(TremorColor.primary.opacity(0.60)))
        context.fill(front, with: .color(TremorColor.primary.opacity(0.45)))
        context.fill(lid, with: .color(TremorColor.primarySoft.opacity(0.32)))
        for face in [right, front, lid] {
            context.stroke(face, with: .color(TremorColor.primarySoft.opacity(0.9)), lineWidth: 1)
        }
        context.opacity = veil
    }
}

// MARK: - Hero 2 — the path up

/// A side view of the example kitchen's first chain, at its measured heights: from the
/// floor onto a counter stool's footrail (0.20 m), and from there within reach of a glass
/// on the breakfast bar (0.92 m). The path draws itself from the floor, then the stars
/// along it light, then the glass pulses.
struct ChainHero: View {

    let phase: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let veil = Ease.loopVeil(phase, headEnd: 0.05, tailStart: 0.94)
            guard veil > 0.001, size.width > 0, size.height > 0 else { return }
            context.opacity = veil
            draw(in: &context, width: Double(size.width), height: Double(size.height))
        }
    }

    private func draw(in context: inout GraphicsContext, width w: Double, height h: Double) {
        let s = min(w / 2.7, h / 1.55)                  // pixels per metre
        let floorY = h * 0.66
        let left = (w - 2.5 * s) / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: left + x * s, y: floorY - y * s) }

        let line = TremorColor.primarySoft.opacity(0.85)
        let fill = TremorColor.primary.opacity(0.35)

        // Floor
        var floor = Path()
        floor.move(to: CGPoint(x: 0, y: floorY))
        floor.addLine(to: CGPoint(x: w, y: floorY))
        context.stroke(floor, with: .color(line), lineWidth: 1.5)

        // Breakfast bar: slab at 0.92 m, base below.
        let slab = Path(CGRect(origin: pt(1.15, 0.92), size: CGSize(width: 1.25 * s, height: 0.05 * s)))
        let base = Path(CGRect(origin: pt(1.30, 0.87), size: CGSize(width: 1.0 * s, height: 0.87 * s)))
        context.fill(base, with: .color(fill.opacity(0.6)))
        context.stroke(base, with: .color(line), lineWidth: 1)
        context.fill(slab, with: .color(fill))
        context.stroke(slab, with: .color(line), lineWidth: 1.25)

        // Glass on the bar.
        var glass = Path()
        glass.move(to: pt(1.60, 0.92)); glass.addLine(to: pt(1.70, 0.92))
        glass.move(to: pt(1.65, 0.92)); glass.addLine(to: pt(1.65, 1.03))
        glass.addEllipse(in: CGRect(origin: pt(1.60, 1.13), size: CGSize(width: 0.10 * s, height: 0.10 * s)))
        context.stroke(glass, with: .color(line), lineWidth: 1.25)

        // Counter stool: legs, footrail at 0.20 m, seat at 0.68 m, backrest.
        var stool = Path()
        stool.move(to: pt(0.55, 0)); stool.addLine(to: pt(0.60, 0.66))
        stool.move(to: pt(1.00, 0)); stool.addLine(to: pt(0.95, 0.66))
        stool.move(to: pt(0.57, 0.20)); stool.addLine(to: pt(0.98, 0.20))
        stool.move(to: pt(0.57, 0.68)); stool.addLine(to: pt(0.58, 1.01))
        context.stroke(stool, with: .color(line), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        let seat = Path(roundedRect: CGRect(origin: pt(0.55, 0.70), size: CGSize(width: 0.47 * s, height: 0.04 * s)),
                        cornerRadius: 3)
        context.fill(seat, with: .color(fill))
        context.stroke(seat, with: .color(line), lineWidth: 1.25)

        // The chain: floor → footrail (step) → glass (reach).
        let floorStar = pt(0.40, 0.0)
        let railStar = pt(0.78, 0.20)
        let glassStar = pt(1.65, 1.08)
        let climb = Ease.out(Ease.ramp(phase, 0.12, 0.34))
        let reach = Ease.out(Ease.ramp(phase, 0.38, 0.62))

        func segment(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> Path {
            var p = Path()
            p.move(to: a)
            p.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            return p
        }
        if climb > 0 {
            let path = segment(floorStar, railStar, climb)
            context.stroke(path, with: .color(TremorColor.accent.opacity(0.3)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            context.stroke(path, with: .color(TremorColor.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if reach > 0 {
            context.stroke(segment(railStar, glassStar, reach), with: .color(TremorColor.accent),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
        }

        func star(_ p: CGPoint, _ tint: Color, _ on: Double, pulse: Double = 0) {
            guard on > 0 else { return }
            let glow = (14 + 8 * pulse) * on
            context.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(0.75), tint.opacity(0)]),
                                               center: p, startRadius: 0, endRadius: glow))
            let r = 4.5 * on
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(tint))
        }
        star(floorStar, TremorColor.primarySoft, Ease.ramp(phase, 0.06, 0.12))
        star(railStar, TremorColor.primarySoft, Ease.ramp(phase, 0.30, 0.36))
        let pulse = phase > 0.62 ? 0.5 + 0.5 * sin((phase - 0.62) * 40) : 0
        star(glassStar, TremorColor.accent, Ease.ramp(phase, 0.58, 0.64), pulse: pulse)

        // Measured labels, once each part has arrived.
        func label(_ text: String, at p: CGPoint, _ on: Double) {
            guard on > 0 else { return }
            let resolved = context.resolve(Text(text).font(TremorFont.font(.captionEmphasis))
                .foregroundStyle(TremorColor.ink))
            let size = resolved.measure(in: CGSize(width: 200, height: 30))
            let rect = CGRect(x: p.x - size.width / 2 - 7, y: p.y - size.height / 2 - 3,
                              width: size.width + 14, height: size.height + 6)
            let saved = context.opacity
            context.opacity = saved * on
            context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(TremorColor.accent))
            context.draw(resolved, in: rect.insetBy(dx: 7, dy: 3))
            context.opacity = saved
        }
        label("step 0.20 m", at: CGPoint(x: railStar.x - 0.42 * s, y: railStar.y - 0.12 * s), Ease.ramp(phase, 0.34, 0.40))
        label("reach 0.72 m", at: CGPoint(x: (railStar.x + glassStar.x) / 2 + 0.30 * s,
                                          y: (railStar.y + glassStar.y) / 2 + 0.05 * s), Ease.ramp(phase, 0.62, 0.68))
    }
}

// MARK: - Hero 3 — the anchor bracket

/// An exploded L-bracket: the wall, the bookcase, the bracket and two screws
/// separate, hold apart long enough to read, then come together and lock.
///
/// It is the same hardware the fix-it plan specifies — a stud-mounted L-bracket
/// with two lag screws — so the picture is a promise the app keeps.
struct AnchorBracketHero: View {

    let phase: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let veil = Ease.loopVeil(phase, headEnd: 0.04, tailStart: 0.96)
            guard veil > 0.001, size.width > 0, size.height > 0 else { return }
            context.opacity = veil

            // Same fixed-aspect stage as the toppling hero, for the same reason.
            let width = Double(size.width)
            let height = Double(size.height)
            let stageWidth = min(width * 1.02, height * 1.60)
            let stageHeight = stageWidth / 1.60
            context.translateBy(x: (width - stageWidth) / 2,
                                y: (height - stageHeight) / 2)
            draw(in: &context, width: stageWidth, height: stageHeight)
        }
    }

    private func draw(in context: inout GraphicsContext, width w: Double, height h: Double) {

        // 0 = assembled, 1 = fully exploded.
        let separation = Ease.smooth(phase, 0.03, 0.30) - Ease.smooth(phase, 0.54, 0.82)
        let assembled = 1 - separation

        let wallX = w * 0.24
        let floorY = h * 0.90
        let caseTop = h * 0.20
        let caseLeft = wallX + w * 0.015 + separation * w * 0.10
        let caseRight = caseLeft + w * 0.36

        // ── Wall ────────────────────────────────────────────────────────
        let wall = Path(CGRect(x: wallX - w * 0.055, y: h * 0.05,
                               width: w * 0.055, height: floorY - h * 0.05))
        context.fill(wall, with: .color(TremorColor.primary.opacity(0.28)))
        context.stroke(wall, with: .color(TremorColor.primarySoft.opacity(0.7)), lineWidth: 1.25)

        var hatch = Path()
        var y = h * 0.09
        while y < floorY {
            hatch.move(to: P(wallX - w * 0.055, y).cg)
            hatch.addLine(to: P(wallX, y - h * 0.02).cg)
            y += h * 0.055
        }
        context.stroke(hatch, with: .color(TremorColor.primarySoft.opacity(0.26)), lineWidth: 1)

        // ── Floor ───────────────────────────────────────────────────────
        var floor = Path()
        floor.move(to: P(0, floorY).cg)
        floor.addLine(to: P(w, floorY).cg)
        context.stroke(floor, with: .color(TremorColor.primarySoft.opacity(0.45)), lineWidth: 1.5)

        // ── Bookcase ────────────────────────────────────────────────────
        let carcass = Path(CGRect(x: caseLeft, y: caseTop,
                                  width: caseRight - caseLeft, height: floorY - caseTop))
        context.fill(carcass, with: .color(TremorColor.primary.opacity(0.30)))
        context.stroke(carcass, with: .color(TremorColor.primarySoft.opacity(0.85)), lineWidth: 1.5)

        var shelves = Path()
        for index in 1...3 {
            let shelfY = caseTop + (floorY - caseTop) * Double(index) / 4
            shelves.move(to: P(caseLeft, shelfY).cg)
            shelves.addLine(to: P(caseRight, shelfY).cg)
        }
        context.stroke(shelves, with: .color(TremorColor.primarySoft.opacity(0.45)), lineWidth: 1)

        // ── The L-bracket ───────────────────────────────────────────────
        let armLength = w * 0.11
        let thickness = max(4.0, h * 0.030)
        let corner = P(caseLeft + separation * w * 0.14,
                       caseTop + h * 0.04 - separation * h * 0.14)

        var bracket = Path()
        bracket.move(to: P(corner.x - armLength, corner.y).cg)
        bracket.addLine(to: corner.cg)
        bracket.addLine(to: P(corner.x, corner.y + armLength).cg)
        context.stroke(bracket,
                       with: .color(TremorColor.accent),
                       style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))

        // ── Screws, with their alignment lines ──────────────────────────
        let screwRadius = max(2.5, h * 0.014)
        let seats = [P(corner.x - armLength * 0.55, corner.y),
                     P(corner.x, corner.y + armLength * 0.62)]
        let offsets = [P(0, -h * 0.24), P(w * 0.20, 0)]

        for (seat, offset) in zip(seats, offsets) {
            let position = P(seat.x + offset.x * separation, seat.y + offset.y * separation)
            if separation > 0.04 {
                var guideLine = Path()
                guideLine.move(to: position.cg)
                guideLine.addLine(to: seat.cg)
                context.stroke(guideLine,
                               with: .color(TremorColor.primarySoft.opacity(0.42 * separation)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            let head = Path(ellipseIn: CGRect(x: position.x - screwRadius,
                                              y: position.y - screwRadius,
                                              width: screwRadius * 2,
                                              height: screwRadius * 2))
            context.fill(head, with: .color(TremorColor.primarySoft))
        }

        // ── The lock-in tick ────────────────────────────────────────────
        let secured = Ease.out(Ease.ramp(phase, 0.84, 0.94)) * assembled
        if secured > 0.01 {
            let centre = P(caseRight + w * 0.09, caseTop + h * 0.05)
            let radius = w * 0.05 * secured
            let disc = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.fill(disc, with: .color(TremorColor.accent.opacity(0.92)))
            var tick = Path()
            tick.move(to: P(centre.x - radius * 0.42, centre.y).cg)
            tick.addLine(to: P(centre.x - radius * 0.08, centre.y + radius * 0.34).cg)
            tick.addLine(to: P(centre.x + radius * 0.44, centre.y - radius * 0.36).cg)
            context.stroke(tick,
                           with: .color(TremorColor.ink),
                           style: StrokeStyle(lineWidth: max(1.5, radius * 0.20),
                                              lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Previews

#Preview("Hero — room assembly") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        LoopingIllustration(duration: OnboardingPage.scan.heroDuration,
                            restPhase: OnboardingPage.scan.heroRestPhase) { phase in
            RoomAssemblyHero(phase: phase)
        }
        .frame(height: 380)
    }
}

#Preview("Hero — toppling") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        LoopingIllustration(duration: OnboardingPage.shake.heroDuration,
                            restPhase: OnboardingPage.shake.heroRestPhase) { phase in
            ChainHero(phase: phase)
        }
        .frame(height: 380)
    }
}

#Preview("Hero — anchor bracket") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        LoopingIllustration(duration: OnboardingPage.fix.heroDuration,
                            restPhase: OnboardingPage.fix.heroRestPhase) { phase in
            AnchorBracketHero(phase: phase)
        }
        .frame(height: 380)
    }
}

#Preview("Heroes — reduce motion (rest frames)") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        VStack(spacing: 0) {
            RoomAssemblyHero(phase: OnboardingPage.scan.heroRestPhase)
            ChainHero(phase: OnboardingPage.shake.heroRestPhase)
            AnchorBracketHero(phase: OnboardingPage.fix.heroRestPhase)
        }
    }
}
