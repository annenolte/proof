//
//  IsometricRoomFigure.swift
//  Tremor — Scan flow (S-09 … S-11) / the shared room drawing
//
//  Three screens in a row have to show the same thing — "here is the room, as
//  far as we understand it" — and they have to show it while it is still
//  incomplete:
//
//    • S-09 draws it live, growing wall by wall as the user walks around.
//    • S-10 freezes it so someone can look at what was captured and judge it.
//    • S-11 fills it in step by step while the objects are being identified
//      (SPEC §1.4 S-11: "a 200 pt square isometric room render at the top that
//      fills in progressively — walls → floor → object silhouettes → labels").
//
//  So it is one drawing, not three. It is a `Canvas` rather than RealityKit for
//  four reasons that all matter during a capture: it costs no GPU warm-up while
//  ARKit owns the device, it renders identically in a `#Preview` and in a
//  snapshot test, it is a pure function of the room so it can be tested without
//  a window server, and a partial room — three walls and no floor — is a
//  perfectly ordinary input rather than a degenerate scene.
//
//  Every colour comes from `StagePalette.stage` and `StageMaterialFamily`, which
//  are the SPEC §2.7.12 stage tokens the RealityKit stage also uses. Nothing
//  here invents a colour, so the miniature and the real stage agree.
//

import SwiftUI
import simd

// MARK: - Projection

/// The isometric camera, as arithmetic.
///
/// Pure, `Equatable` and free of SwiftUI, so the framing can be unit-tested:
/// "does every corner of the room land inside the frame" is a question with an
/// answer, and it is the question that goes wrong first when a room is long and
/// thin.
struct IsometricRoomProjection: Equatable {

    /// Half the classic 2:1 isometric pair. `cos 30°` / `sin 30°` give the
    /// 30-degree true isometric that reads as an architect's model rather than
    /// as a game tile.
    private static let cosine: CGFloat = 0.866_025_4
    private static let sine: CGFloat = 0.5

    /// The point the room is rotated about — its own centre, so dragging
    /// spins the room rather than swinging it out of frame.
    let pivot: SIMD3<Float>
    /// Extra rotation about the world Y axis, radians. S-10's drag drives it.
    let azimuth: Double
    let scale: CGFloat
    let origin: CGPoint

    init(bounds: (min: SIMD3<Float>, max: SIMD3<Float>),
         size: CGSize,
         padding: CGFloat = 0,
         azimuth: Double = 0) {
        self.pivot = (bounds.min + bounds.max) / 2
        self.azimuth = azimuth

        // Fit by measuring: project the eight corners of the room's box, take
        // the bounding rectangle of the result, and scale that to the frame.
        // Deriving the scale from the extents directly is what produces the
        // classic bug where a rotated room clips its own corners.
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for xs in [bounds.min.x, bounds.max.x] {
            for ys in [bounds.min.y, bounds.max.y] {
                for zs in [bounds.min.z, bounds.max.z] {
                    let p = Self.flatten(
                        Self.rotate(SIMD3(xs, ys, zs) - pivot, by: azimuth))
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }

        let usableWidth = max(size.width - padding * 2, 1)
        let usableHeight = max(size.height - padding * 2, 1)
        let spanX = max(maxX - minX, 0.001)
        let spanY = max(maxY - minY, 0.001)
        let scale = min(usableWidth / spanX, usableHeight / spanY)
        self.scale = scale
        self.origin = CGPoint(
            x: size.width / 2 - (minX + maxX) / 2 * scale,
            y: size.height / 2 - (minY + maxY) / 2 * scale)
    }

    private static func rotate(_ p: SIMD3<Float>, by azimuth: Double) -> SIMD3<Float> {
        guard azimuth != 0 else { return p }
        let c = Float(cos(azimuth)), s = Float(sin(azimuth))
        return SIMD3(p.x * c - p.z * s, p.y, p.x * s + p.z * c)
    }

    private static func flatten(_ p: SIMD3<Float>) -> CGPoint {
        CGPoint(
            x: (CGFloat(p.x) - CGFloat(p.z)) * cosine,
            y: (CGFloat(p.x) + CGFloat(p.z)) * sine - CGFloat(p.y))
    }

    /// A world point in view coordinates.
    func point(_ world: SIMD3<Float>) -> CGPoint {
        let local = Self.flatten(Self.rotate(world - pivot, by: azimuth))
        return CGPoint(x: origin.x + local.x * scale, y: origin.y + local.y * scale)
    }

    /// Painter's-algorithm sort key. Larger is nearer the viewer, so drawables
    /// are drawn in ascending order and near things land on top of far ones.
    func depth(_ world: SIMD3<Float>) -> Float {
        let local = Self.rotate(world - pivot, by: azimuth)
        return local.x + local.z
    }
}

// MARK: - Geometry helpers

/// The room, reduced to the handful of shapes the drawing needs.
enum IsometricRoomGeometry {

    /// A box in the room, ready to be projected: eight corners and a centre.
    struct Box {
        var centre: SIMD3<Float>
        var axisX: SIMD3<Float>
        var axisZ: SIMD3<Float>
        var half: SIMD3<Float>

        init(placement: Placement, extents: Extents) {
            self.centre = placement.centre
            let c = cos(placement.yaw), s = sin(placement.yaw)
            self.axisX = SIMD3(c, 0, -s)
            self.axisZ = SIMD3(s, 0, c)
            self.half = SIMD3(extents.width, extents.height, extents.depth) / 2
        }

        func corner(_ sx: Float, _ sy: Float, _ sz: Float) -> SIMD3<Float> {
            centre
                + axisX * (half.x * sx)
                + SIMD3(0, half.y * sy, 0)
                + axisZ * (half.z * sz)
        }

        /// The four corners of the +Y face.
        var topFace: [SIMD3<Float>] {
            [corner(-1, 1, -1), corner(1, 1, -1), corner(1, 1, 1), corner(-1, 1, 1)]
        }

        /// The face whose outward normal is `sign · axisX`.
        func faceAlongX(_ sign: Float) -> [SIMD3<Float>] {
            [corner(sign, 1, -1), corner(sign, 1, 1), corner(sign, -1, 1), corner(sign, -1, -1)]
        }

        /// The face whose outward normal is `sign · axisZ`.
        func faceAlongZ(_ sign: Float) -> [SIMD3<Float>] {
            [corner(-1, 1, sign), corner(1, 1, sign), corner(1, -1, sign), corner(-1, -1, sign)]
        }
    }

    /// The room's axis-aligned bounds, from whatever geometry exists.
    ///
    /// Falls back to a plausible 4 × 2.5 × 4 m box for an empty room, so the
    /// very first frame of a scan — before any wall has landed — still draws a
    /// stable, correctly-framed floor rather than dividing by zero.
    static func bounds(of room: ScannedRoom?) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let fallback = (min: SIMD3<Float>(-2, 0, -2), max: SIMD3<Float>(2, 2.5, 2))
        guard let room, !(room.surfaces.isEmpty && room.objects.isEmpty) else { return fallback }

        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        func absorb(_ box: Box) {
            for sx in [Float(-1), 1] {
                for sy in [Float(-1), 1] {
                    for sz in [Float(-1), 1] {
                        let p = box.corner(sx, sy, sz)
                        lo = simd_min(lo, p)
                        hi = simd_max(hi, p)
                    }
                }
            }
        }
        for surface in room.surfaces {
            absorb(Box(placement: surface.placement, extents: surface.extents))
        }
        for object in room.objects {
            absorb(Box(placement: object.placement, extents: object.extents))
        }
        guard lo.x < hi.x else { return fallback }

        // A room with only a floor has no height at all, which projects to a
        // zero-height rectangle. Give it a storey so the framing is stable from
        // the first wall to the last.
        if hi.y - lo.y < 0.5 { hi.y = lo.y + 2.5 }
        return (lo, hi)
    }
}

// MARK: - Colour bridging

private extension Color {
    /// `StageColor` is deliberately UIKit-free floats; this is the one place it
    /// becomes a SwiftUI colour.
    init(stage: StageColor) {
        self.init(.sRGB,
                  red: Double(stage.red),
                  green: Double(stage.green),
                  blue: Double(stage.blue),
                  opacity: Double(stage.alpha))
    }
}

private extension StageColor {
    static let lit = StageColor(red: 1, green: 1, blue: 1)

    /// The top face catches the key light; the two visible sides fall away from
    /// it. One base colour, three shades — the whole reason the drawing reads as
    /// solid rather than as flat tiles.
    var topShade: StageColor { blended(with: .lit, amount: 0.16) }
    func sideShade(in palette: StagePalette) -> StageColor {
        blended(with: palette.background, amount: 0.34)
    }
}

// MARK: - The figure

/// The room, drawn.
///
/// Everything is optional on purpose: a nil room, a room with no floor, a room
/// whose objects have not been identified yet and a finished room are all
/// ordinary inputs, because during a scan they are all real states.
struct IsometricRoomFigure: View {

    /// The room to draw. Nil renders the empty stage, which is what S-09 shows
    /// in the second before the first wall arrives.
    var room: ScannedRoom?
    /// Which objects to draw. Nil means all of them; a set is how S-11 reveals
    /// furniture one piece at a time as it is identified.
    var revealedObjectIDs: Set<UUID>?
    /// Objects to name on the drawing. Only the most recent is drawn, because
    /// a 200 pt square cannot hold fourteen labels and pretending otherwise
    /// produces a pile of overlapping text.
    var labelledObjectIDs: [UUID] = []
    /// Drawn with the selection outline (SPEC §2.7.12: 2 pt `fearless`).
    var highlightedObjectID: UUID?
    /// Rotation about Y in radians. S-10 lets the user drag this.
    var azimuth: Double = 0
    var padding: CGFloat = TremorSpacing.md
    /// Overridden by S-11, which needs the floor to arrive after the walls.
    var showsFloor: Bool = true
    /// Replaces the assembled geometry description for VoiceOver.
    var accessibilityDescription: String?

    private let palette = StagePalette.stage

    var body: some View {
        GeometryReader { geometry in
            let bounds = IsometricRoomGeometry.bounds(of: room)
            let projection = IsometricRoomProjection(
                bounds: bounds, size: geometry.size, padding: padding, azimuth: azimuth)

            ZStack(alignment: .topLeading) {
                Canvas(opaque: false) { context, _ in
                    draw(in: &context, projection: projection, bounds: bounds)
                }
                labelLayer(projection: projection, size: geometry.size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room drawing")
        .accessibilityValue(accessibilityDescription ?? Self.describe(room))
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext,
                      projection: IsometricRoomProjection,
                      bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) {
        if showsFloor { drawFloor(&context, projection: projection, bounds: bounds) }
        guard let room else { return }

        // One painter's-algorithm pass over walls *and* furniture together.
        // Sorting them separately is the bug that puts a bookcase in front of
        // the wall it is standing against.
        enum Piece {
            case surface(RoomSurface)
            case object(ScannedObject)
        }
        var pieces: [(depth: Float, piece: Piece)] = []

        // Only the far half of the walls is drawn. A closed box seen from
        // outside is four grey rectangles and nothing else; dropping the near
        // walls is what turns it into a room you can see into.
        let midDepth = projection.depth((bounds.min + bounds.max) / 2)
        for surface in room.surfaces where surface.kind != .floor && surface.kind != .ceiling {
            let depth = projection.depth(surface.placement.centre)
            guard depth <= midDepth + 0.05 else { continue }
            pieces.append((depth, .surface(surface)))
        }
        for object in room.objects where isRevealed(object.id) {
            pieces.append((projection.depth(object.placement.centre), .object(object)))
        }
        pieces.sort { $0.depth < $1.depth }

        for entry in pieces {
            switch entry.piece {
            case .surface(let surface): draw(surface, in: &context, projection: projection)
            case .object(let object): draw(object, in: &context, projection: projection)
            }
        }
    }

    private func drawFloor(_ context: inout GraphicsContext,
                           projection: IsometricRoomProjection,
                           bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) {
        let y = bounds.min.y
        let corners = [
            SIMD3(bounds.min.x, y, bounds.min.z),
            SIMD3(bounds.max.x, y, bounds.min.z),
            SIMD3(bounds.max.x, y, bounds.max.z),
            SIMD3(bounds.min.x, y, bounds.max.z)
        ]
        let path = polygon(corners.map(projection.point))
        context.fill(path, with: .color(Color(stage: palette.floor)))

        // A one-metre grid. Without it the floor is an untextured lozenge and
        // the drawing reads as a solid lump rather than as a room with a size.
        var grid = Path()
        let gridColour = Color(stage: palette.grid).opacity(0.35)
        var x = bounds.min.x.rounded(.up)
        while x < bounds.max.x {
            grid.move(to: projection.point(SIMD3(x, y, bounds.min.z)))
            grid.addLine(to: projection.point(SIMD3(x, y, bounds.max.z)))
            x += 1
        }
        var z = bounds.min.z.rounded(.up)
        while z < bounds.max.z {
            grid.move(to: projection.point(SIMD3(bounds.min.x, y, z)))
            grid.addLine(to: projection.point(SIMD3(bounds.max.x, y, z)))
            z += 1
        }
        context.stroke(grid, with: .color(gridColour), lineWidth: TremorSize.hairline)

        context.stroke(path, with: .color(Color(stage: palette.grid).opacity(0.8)),
                       lineWidth: TremorSize.hairline)
    }

    private func draw(_ surface: RoomSurface,
                      in context: inout GraphicsContext,
                      projection: IsometricRoomProjection) {
        let box = IsometricRoomGeometry.Box(
            placement: surface.placement, extents: surface.extents)
        // A wall is a plane, so its two big faces are the same quad; drawing the
        // one facing the camera is the whole wall.
        let quad = box.faceAlongZ(1)
        let path = polygon(quad.map(projection.point))

        // The two visible walls meet at a corner, so they must not be the same
        // value or the corner disappears and the room reads as a flat lozenge.
        // Which of the two a wall belongs to depends on the current rotation,
        // so it is measured rather than assumed: a wall whose face moves the
        // projected point sideways is lit, one that moves it up the screen is
        // in shade.
        let centre = projection.point(surface.placement.centre)
        let outward = projection.point(surface.placement.centre + box.axisZ * 0.5)
        let isLit = abs(outward.x - centre.x) > abs(outward.y - centre.y)
        let base = colour(for: surface.kind)
        let shaded = surface.kind == .wall
            ? (isLit ? base.blended(with: .lit, amount: 0.10)
                     : base.blended(with: palette.background, amount: 0.22))
            : base

        context.fill(path, with: .color(Color(stage: shaded)))
        context.stroke(path, with: .color(Color(stage: palette.wallTrim)),
                       lineWidth: TremorSize.hairline)
    }

    private func colour(for kind: RoomSurface.Kind) -> StageColor {
        switch kind {
        case .wall: return palette.wall
        case .door, .opening: return palette.door
        case .window: return palette.window
        case .floor, .ceiling: return palette.floor
        }
    }

    private func draw(_ object: ScannedObject,
                      in context: inout GraphicsContext,
                      projection: IsometricRoomProjection) {
        let box = IsometricRoomGeometry.Box(
            placement: object.placement, extents: object.extents)
        let base = object.type.stageMaterialFamily.baseColor

        // Which two side faces the camera can see depends on the object's yaw
        // and on the current azimuth, so it is decided per object rather than
        // assumed. `depth` is monotonic in "towards the viewer", which makes
        // this a comparison rather than a dot product.
        let centreDepth = projection.depth(object.placement.centre)
        let xSign: Float = projection.depth(object.centreOffset(box.axisX, box.half.x)) > centreDepth ? 1 : -1
        let zSign: Float = projection.depth(object.centreOffset(box.axisZ, box.half.z)) > centreDepth ? 1 : -1

        let faces: [(points: [SIMD3<Float>], colour: StageColor)] = [
            (box.faceAlongX(xSign), base),
            (box.faceAlongZ(zSign), base.sideShade(in: palette)),
            (box.topFace, base.topShade)
        ]
        for face in faces {
            let path = polygon(face.points.map(projection.point))
            context.fill(path, with: .color(Color(stage: face.colour)))
        }

        if object.id == highlightedObjectID {
            let outline = polygon(box.topFace.map(projection.point))
            context.stroke(outline, with: .color(Color(stage: palette.selection)),
                           lineWidth: TremorSize.strokeEmphasis)
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func isRevealed(_ id: UUID) -> Bool {
        guard let revealedObjectIDs else { return true }
        return revealedObjectIDs.contains(id)
    }

    // MARK: Labels

    /// Names float above the drawing as real SwiftUI text rather than being
    /// painted into the canvas, so they scale with Dynamic Type and keep the
    /// design system's type ramp.
    @ViewBuilder
    private func labelLayer(projection: IsometricRoomProjection, size: CGSize) -> some View {
        // One at a time. Two labels on a 200 pt square collide the moment two
        // objects resolve in the same second, and a pile of overlapping text is
        // worse than no label at all.
        let names = labelledObjectIDs
            .suffix(1)
            .compactMap { id in room?.object(id: id) }
        ForEach(names, id: \.id) { object in
            let anchor = projection.point(
                object.placement.centre + SIMD3(0, object.extents.height / 2, 0))
            IsometricRoomLabel(text: object.type.displayName)
                .position(x: min(max(anchor.x, TremorSpacing.xxl), size.width - TremorSpacing.xxl),
                          y: max(anchor.y - TremorSpacing.md, TremorSpacing.sm))
                .transition(.opacity)
        }
    }

    // MARK: Accessibility

    static func describe(_ room: ScannedRoom?) -> String {
        guard let room else { return "Nothing captured yet" }
        var parts: [String] = []
        let walls = room.surfaces.filter { $0.kind == .wall }.count
        if walls > 0 { parts.append(walls == 1 ? "1 wall" : "\(walls) walls") }
        let objects = room.objects.count
        if objects > 0 { parts.append(objects == 1 ? "1 object" : "\(objects) objects") }
        return parts.isEmpty ? "Nothing captured yet" : parts.joined(separator: ", ")
    }
}

private extension ScannedObject {
    /// The centre pushed one half-extent along an axis — used to decide which
    /// side of a box faces the viewer.
    func centreOffset(_ axis: SIMD3<Float>, _ half: Float) -> SIMD3<Float> {
        placement.centre + axis * half
    }
}

/// The name tag drawn over an object on the miniature.
struct IsometricRoomLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .tremorType(.caption)
            .foregroundStyle(TremorColor.ink)
            .lineLimit(1)
            .padding(.horizontal, TremorSpacing.xs)
            .padding(.vertical, TremorSpacing.hair)
            .background(TremorColor.surfaceRaised, in: Capsule())
            .tremorShadow(.hairline)
            .accessibilityHidden(true)
    }
}

/// The dark plate the figure sits on. SPEC §2.7.12: the stage is always ink,
/// with a vignette, whatever the rest of the app is doing.
struct IsometricRoomPlate<Content: View>: View {

    var cornerRadius: CGFloat = TremorRadius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    Color(stage: StagePalette.stage.background)
                    RadialGradient(
                        colors: [.clear, Color(stage: StagePalette.stage.background)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Figure — complete room") {
    IsometricRoomPlate {
        IsometricRoomFigure(room: RoomFixtures.dangerousBedroom)
            .frame(height: 260)
    }
    .padding(TremorSpacing.md)
    .background(TremorColor.canvas)
}

#Preview("Figure — partial capture") {
    var partial = RoomFixtures.dangerousBedroom
    partial.surfaces = Array(partial.surfaces.prefix(2))
    partial.objects = Array(partial.objects.prefix(1))
    return IsometricRoomPlate {
        IsometricRoomFigure(room: partial)
            .frame(height: 260)
    }
    .padding(TremorSpacing.md)
    .background(TremorColor.canvas)
}

#Preview("Figure — nothing captured") {
    IsometricRoomPlate {
        IsometricRoomFigure(room: nil)
            .frame(height: 260)
    }
    .padding(TremorSpacing.md)
    .background(TremorColor.canvas)
}

#Preview("Figure — labelled and rotated") {
    let room = RoomFixtures.dangerousBedroom
    return IsometricRoomPlate {
        IsometricRoomFigure(
            room: room,
            labelledObjectIDs: room.objects.prefix(2).map(\.id),
            highlightedObjectID: room.objects.first?.id,
            azimuth: 0.6)
        .frame(height: 260)
    }
    .padding(TremorSpacing.md)
    .background(TremorColor.canvas)
}
