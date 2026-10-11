import Foundation
import RealityKit
import simd

// Procedural mesh authoring for the investor demo room.
//
// The stage engine in Features/Simulate can only make boxes, which is correct for the
// safety product — a box is an honest representation of a scanned bounding volume. The
// demo room has the opposite goal: it must look like a photograph of one specific
// apartment. So it gets its own geometry toolkit and never touches SceneBuilder.
//
// Everything here builds an indexed triangle mesh in a `MeshAccumulator`, which is a
// plain value type. Accumulators compose — you build a chair leg once and append it four
// times under different transforms — and only the final accumulator is turned into a
// `MeshResource`. That keeps draw calls down: one entity per *object*, not per part.
//
// Conventions:
//   • Right-handed, Y-up, metres. Same as Core/Model, so numbers are comparable.
//   • Front faces are counter-clockwise when viewed from outside.
//   • UVs are metre-scaled by default, so a wood texture tiles at real-world size
//     regardless of how big the surface is.

// MARK: - Accumulator

struct MeshAccumulator {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var normals: [SIMD3<Float>] = []
    private(set) var uvs: [SIMD2<Float>] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    init() {}

    init(reservingVertices vertices: Int, triangles: Int) {
        positions.reserveCapacity(vertices)
        normals.reserveCapacity(vertices)
        uvs.reserveCapacity(vertices)
        indices.reserveCapacity(triangles * 3)
    }

    @discardableResult
    mutating func addVertex(_ position: SIMD3<Float>, normal: SIMD3<Float>, uv: SIMD2<Float>) -> UInt32 {
        let index = UInt32(positions.count)
        positions.append(position)
        normals.append(normalise(normal))
        uvs.append(uv)
        return index
    }

    mutating func addTriangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        indices.append(contentsOf: [a, b, c])
    }

    /// Adds a quad wound counter-clockwise as seen from the front face.
    mutating func addQuad(
        _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
        normal: SIMD3<Float>? = nil,
        uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)
        )
    ) {
        let n = normal ?? normalise(cross(b - a, d - a))
        let ia = addVertex(a, normal: n, uv: uv.0)
        let ib = addVertex(b, normal: n, uv: uv.1)
        let ic = addVertex(c, normal: n, uv: uv.2)
        let id = addVertex(d, normal: n, uv: uv.3)
        addTriangle(ia, ib, ic)
        addTriangle(ia, ic, id)
    }

    /// Merges another accumulator, optionally transformed.
    mutating func append(_ other: MeshAccumulator, transform: simd_float4x4 = matrix_identity_float4x4) {
        guard !other.positions.isEmpty else { return }
        let offset = UInt32(positions.count)
        let isIdentity = transform == matrix_identity_float4x4

        if isIdentity {
            positions.append(contentsOf: other.positions)
            normals.append(contentsOf: other.normals)
        } else {
            // Normals need the inverse transpose so non-uniform scale does not skew them.
            let linear = simd_float3x3(
                SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            )
            let normalMatrix = linear.inverse.transpose
            for p in other.positions {
                let v = transform * SIMD4(p, 1)
                positions.append(SIMD3(v.x, v.y, v.z))
            }
            for n in other.normals {
                normals.append(normalise(normalMatrix * n))
            }
        }

        uvs.append(contentsOf: other.uvs)
        indices.append(contentsOf: other.indices.map { $0 + offset })
    }

    /// Convenience for repeating a part at several transforms.
    mutating func append(_ other: MeshAccumulator, at transforms: [simd_float4x4]) {
        for t in transforms { append(other, transform: t) }
    }

    func transformed(by transform: simd_float4x4) -> MeshAccumulator {
        var out = MeshAccumulator()
        out.append(self, transform: transform)
        return out
    }

    /// Axis-aligned bounds in local space. Used to place objects on surfaces.
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = positions.first else { return (.zero, .zero) }
        var lo = first, hi = first
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    @MainActor
    func resource(named name: String = "mesh") throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

private func normalise(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = simd_length(v)
    return len > 1e-6 ? v / len : SIMD3(0, 1, 0)
}

// MARK: - Transform helpers

enum Xf {
    static func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    static func translate(_ v: SIMD3<Float>) -> simd_float4x4 { translate(v.x, v.y, v.z) }

    static func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.0.x = x
        m.columns.1.y = y
        m.columns.2.z = z
        return m
    }

    static func scale(_ s: Float) -> simd_float4x4 { scale(s, s, s) }

    static func rotateY(_ radians: Float) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: radians, axis: SIMD3(0, 1, 0)))
    }

    static func rotateX(_ radians: Float) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: radians, axis: SIMD3(1, 0, 0)))
    }

    static func rotateZ(_ radians: Float) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: radians, axis: SIMD3(0, 0, 1)))
    }

    /// Translation composed with a yaw, the combination used for nearly every prop.
    static func place(_ x: Float, _ y: Float, _ z: Float, yaw: Float = 0) -> simd_float4x4 {
        translate(x, y, z) * rotateY(yaw)
    }
}

// MARK: - Primitives

enum Mesh {
    /// A box centred on the origin with per-face, metre-scaled UVs.
    ///
    /// `generateBox` exists, but its UVs are normalised per face, so a 3 m counter and a
    /// 0.3 m drawer front would show the same number of wood grain repeats. These UVs are
    /// in metres, which is what makes tiled textures read at a believable scale.
    static func box(_ size: SIMD3<Float>, uvScale: Float = 1) -> MeshAccumulator {
        let h = size / 2
        var m = MeshAccumulator(reservingVertices: 24, triangles: 12)
        let s = uvScale

        func face(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
            _ n: SIMD3<Float>, _ w: Float, _ hgt: Float
        ) {
            m.addQuad(a, b, c, d, normal: n, uv: (
                SIMD2(0, 0), SIMD2(w * s, 0), SIMD2(w * s, hgt * s), SIMD2(0, hgt * s)
            ))
        }

        // +Z front
        face(SIMD3(-h.x, -h.y, h.z), SIMD3(h.x, -h.y, h.z), SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z),
             SIMD3(0, 0, 1), size.x, size.y)
        // -Z back
        face(SIMD3(h.x, -h.y, -h.z), SIMD3(-h.x, -h.y, -h.z), SIMD3(-h.x, h.y, -h.z), SIMD3(h.x, h.y, -h.z),
             SIMD3(0, 0, -1), size.x, size.y)
        // +X right
        face(SIMD3(h.x, -h.y, h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, h.y, -h.z), SIMD3(h.x, h.y, h.z),
             SIMD3(1, 0, 0), size.z, size.y)
        // -X left
        face(SIMD3(-h.x, -h.y, -h.z), SIMD3(-h.x, -h.y, h.z), SIMD3(-h.x, h.y, h.z), SIMD3(-h.x, h.y, -h.z),
             SIMD3(-1, 0, 0), size.z, size.y)
        // +Y top
        face(SIMD3(-h.x, h.y, h.z), SIMD3(h.x, h.y, h.z), SIMD3(h.x, h.y, -h.z), SIMD3(-h.x, h.y, -h.z),
             SIMD3(0, 1, 0), size.x, size.z)
        // -Y bottom
        face(SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, -h.y, h.z), SIMD3(-h.x, -h.y, h.z),
             SIMD3(0, -1, 0), size.x, size.z)

        return m
    }

    /// A box sitting on y = 0 rather than centred, which is how furniture is placed.
    static func boxOnFloor(_ size: SIMD3<Float>, uvScale: Float = 1) -> MeshAccumulator {
        box(size, uvScale: uvScale).transformed(by: Xf.translate(0, size.y / 2, 0))
    }

    /// A single flat quad in the XZ plane facing +Y, centred on the origin.
    static func floorPlane(width: Float, depth: Float, uvScale: Float = 1) -> MeshAccumulator {
        var m = MeshAccumulator(reservingVertices: 4, triangles: 2)
        let w = width / 2, d = depth / 2
        let u = width * uvScale, v = depth * uvScale
        m.addQuad(
            SIMD3(-w, 0, d), SIMD3(w, 0, d), SIMD3(w, 0, -d), SIMD3(-w, 0, -d),
            normal: SIMD3(0, 1, 0),
            uv: (SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0))
        )
        return m
    }

    /// A flat quad in the XY plane facing +Z, centred on the origin. Art, window glass, screens.
    static func wallPlane(width: Float, height: Float, uvScale: Float = 1) -> MeshAccumulator {
        var m = MeshAccumulator(reservingVertices: 4, triangles: 2)
        let w = width / 2, h = height / 2
        let u = uvScale == 1 ? 1 : width * uvScale
        let v = uvScale == 1 ? 1 : height * uvScale
        m.addQuad(
            SIMD3(-w, -h, 0), SIMD3(w, -h, 0), SIMD3(w, h, 0), SIMD3(-w, h, 0),
            normal: SIMD3(0, 0, 1),
            uv: (SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0))
        )
        return m
    }

    /// Revolves a profile around the Y axis.
    ///
    /// `profile` is a list of `(radius, y)` pairs ordered bottom to top. This is how every
    /// turned or moulded form in the room is made: lamp shades, the vase, the dining table's
    /// cone pedestal, the candle, the armchair's disc base.
    static func lathe(
        profile: [SIMD2<Float>],
        segments: Int = 48,
        capBottom: Bool = true,
        capTop: Bool = true,
        uvScale: Float = 1
    ) -> MeshAccumulator {
        guard profile.count >= 2, segments >= 3 else { return MeshAccumulator() }
        var m = MeshAccumulator(
            reservingVertices: (segments + 1) * profile.count + 2 * segments,
            triangles: segments * (profile.count - 1) * 2 + 2 * segments
        )

        // Profile-space normals: perpendicular to each segment, pointing outward.
        var profileNormals = [SIMD2<Float>](repeating: SIMD2(1, 0), count: profile.count)
        for i in 0..<profile.count {
            let prev = profile[max(i - 1, 0)]
            let next = profile[min(i + 1, profile.count - 1)]
            let tangent = next - prev
            var n = SIMD2(tangent.y, -tangent.x)
            let len = simd_length(n)
            n = len > 1e-6 ? n / len : SIMD2(1, 0)
            profileNormals[i] = n
        }

        // Cumulative arc length gives a non-stretched V coordinate.
        var arc = [Float](repeating: 0, count: profile.count)
        for i in 1..<profile.count {
            arc[i] = arc[i - 1] + simd_distance(profile[i], profile[i - 1])
        }
        let totalArc = max(arc.last ?? 1, 1e-5)

        var ring = [[UInt32]]()
        ring.reserveCapacity(profile.count)
        for (i, point) in profile.enumerated() {
            var row = [UInt32]()
            row.reserveCapacity(segments + 1)
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let ct = cos(theta), st = sin(theta)
                let position = SIMD3(point.x * ct, point.y, point.x * st)
                let normal = SIMD3(profileNormals[i].x * ct, profileNormals[i].y, profileNormals[i].x * st)
                let uv = SIMD2(Float(s) / Float(segments) * uvScale, (arc[i] / totalArc) * uvScale)
                row.append(m.addVertex(position, normal: normal, uv: uv))
            }
            ring.append(row)
        }

        for i in 0..<(profile.count - 1) {
            for s in 0..<segments {
                let a = ring[i][s], b = ring[i][s + 1]
                let c = ring[i + 1][s + 1], d = ring[i + 1][s]
                m.addTriangle(a, b, c)
                m.addTriangle(a, c, d)
            }
        }

        if capBottom, profile[0].x > 1e-5 {
            let y = profile[0].y
            let centre = m.addVertex(SIMD3(0, y, 0), normal: SIMD3(0, -1, 0), uv: SIMD2(0.5, 0.5))
            var rim = [UInt32]()
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                rim.append(m.addVertex(
                    SIMD3(profile[0].x * cos(theta), y, profile[0].x * sin(theta)),
                    normal: SIMD3(0, -1, 0),
                    uv: SIMD2(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta))
                ))
            }
            for s in 0..<segments { m.addTriangle(centre, rim[s + 1], rim[s]) }
        }

        if capTop, let top = profile.last, top.x > 1e-5 {
            let y = top.y
            let centre = m.addVertex(SIMD3(0, y, 0), normal: SIMD3(0, 1, 0), uv: SIMD2(0.5, 0.5))
            var rim = [UInt32]()
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                rim.append(m.addVertex(
                    SIMD3(top.x * cos(theta), y, top.x * sin(theta)),
                    normal: SIMD3(0, 1, 0),
                    uv: SIMD2(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta))
                ))
            }
            for s in 0..<segments { m.addTriangle(centre, rim[s], rim[s + 1]) }
        }

        return m
    }

    /// Extrudes a closed polygon (given in the XZ plane, counter-clockwise seen from +Y)
    /// vertically from `bottom` to `top`, with flat caps.
    ///
    /// This is what makes the organic blob coffee table and the shaped rug possible.
    static func extrude(
        polygon: [SIMD2<Float>],
        bottom: Float,
        top: Float,
        uvScale: Float = 1,
        capBottom: Bool = true,
        capTop: Bool = true
    ) -> MeshAccumulator {
        guard polygon.count >= 3 else { return MeshAccumulator() }
        var m = MeshAccumulator()
        let n = polygon.count

        // Side wall: one quad per edge, normal perpendicular to that edge.
        var u: Float = 0
        for i in 0..<n {
            let p0 = polygon[i]
            let p1 = polygon[(i + 1) % n]
            let edge = p1 - p0
            let len = simd_length(edge)
            guard len > 1e-6 else { continue }
            let normal = SIMD3(edge.y / len, 0, -edge.x / len)
            let uNext = u + len * uvScale
            let vLo: Float = 0, vHi = (top - bottom) * uvScale
            m.addQuad(
                SIMD3(p0.x, bottom, p0.y), SIMD3(p1.x, bottom, p1.y),
                SIMD3(p1.x, top, p1.y), SIMD3(p0.x, top, p0.y),
                normal: normal,
                uv: (SIMD2(u, vLo), SIMD2(uNext, vLo), SIMD2(uNext, vHi), SIMD2(u, vHi))
            )
            u = uNext
        }

        guard capBottom || capTop else { return m }
        let triangles = Triangulator.earClip(polygon)

        if capTop {
            var map = [UInt32](repeating: 0, count: n)
            for (i, p) in polygon.enumerated() {
                map[i] = m.addVertex(
                    SIMD3(p.x, top, p.y), normal: SIMD3(0, 1, 0),
                    uv: SIMD2(p.x * uvScale, p.y * uvScale)
                )
            }
            for t in triangles { m.addTriangle(map[Int(t.0)], map[Int(t.2)], map[Int(t.1)]) }
        }

        if capBottom {
            var map = [UInt32](repeating: 0, count: n)
            for (i, p) in polygon.enumerated() {
                map[i] = m.addVertex(
                    SIMD3(p.x, bottom, p.y), normal: SIMD3(0, -1, 0),
                    uv: SIMD2(p.x * uvScale, p.y * uvScale)
                )
            }
            for t in triangles { m.addTriangle(map[Int(t.0)], map[Int(t.1)], map[Int(t.2)]) }
        }

        return m
    }

    /// A rectangular frame (four mitred-looking bars) in the XY plane, facing +Z.
    /// Picture frames and window mullions.
    static func frame(
        outerWidth: Float, outerHeight: Float,
        thickness: Float, depth: Float
    ) -> MeshAccumulator {
        var m = MeshAccumulator()
        let hw = outerWidth / 2, hh = outerHeight / 2
        let innerW = max(outerWidth - 2 * thickness, 0.001)
        // Top and bottom run the full width; sides fill between them.
        m.append(box(SIMD3(outerWidth, thickness, depth)),
                 transform: Xf.translate(0, hh - thickness / 2, 0))
        m.append(box(SIMD3(outerWidth, thickness, depth)),
                 transform: Xf.translate(0, -hh + thickness / 2, 0))
        let sideHeight = max(outerHeight - 2 * thickness, 0.001)
        m.append(box(SIMD3(thickness, sideHeight, depth)),
                 transform: Xf.translate(-hw + thickness / 2, 0, 0))
        m.append(box(SIMD3(thickness, sideHeight, depth)),
                 transform: Xf.translate(hw - thickness / 2, 0, 0))
        _ = innerW
        return m
    }

    /// A cylinder standing on y = 0, aligned to Y.
    static func cylinder(radius: Float, height: Float, segments: Int = 32) -> MeshAccumulator {
        lathe(profile: [SIMD2(radius, 0), SIMD2(radius, height)], segments: segments)
    }

    /// A tapered cylinder — table legs, lamp stems, the dining pedestal.
    static func taper(
        bottomRadius: Float, topRadius: Float, height: Float, segments: Int = 32
    ) -> MeshAccumulator {
        lathe(profile: [SIMD2(bottomRadius, 0), SIMD2(topRadius, height)], segments: segments)
    }

    /// A hollow ring lying in the XZ plane — the brass base rims and shelf uprights.
    static func tube(
        outerRadius: Float, innerRadius: Float, height: Float, segments: Int = 32
    ) -> MeshAccumulator {
        lathe(
            profile: [
                SIMD2(innerRadius, 0), SIMD2(outerRadius, 0),
                SIMD2(outerRadius, height), SIMD2(innerRadius, height)
            ],
            segments: segments, capBottom: false, capTop: false
        )
    }
}

// MARK: - Triangulation

/// Ear-clipping triangulation for simple (non-self-intersecting) polygons.
/// Only used at load time on polygons of a few dozen points, so the O(n²) is irrelevant.
enum Triangulator {
    static func earClip(_ polygon: [SIMD2<Float>]) -> [(UInt32, UInt32, UInt32)] {
        let n = polygon.count
        guard n >= 3 else { return [] }
        if n == 3 { return [(0, 1, 2)] }

        var indices = Array(0..<n)
        // Work counter-clockwise regardless of input winding.
        if signedArea(polygon) < 0 { indices.reverse() }

        var result = [(UInt32, UInt32, UInt32)]()
        result.reserveCapacity(n - 2)
        var guardCounter = 0

        while indices.count > 3 && guardCounter < n * n {
            guardCounter += 1
            var clipped = false
            for i in 0..<indices.count {
                let iPrev = indices[(i + indices.count - 1) % indices.count]
                let iCurr = indices[i]
                let iNext = indices[(i + 1) % indices.count]
                let a = polygon[iPrev], b = polygon[iCurr], c = polygon[iNext]

                // Reflex vertices cannot be ears.
                guard cross2(b - a, c - b) > 1e-9 else { continue }

                // No other vertex may fall inside the candidate ear.
                var contains = false
                for j in indices where j != iPrev && j != iCurr && j != iNext {
                    if pointInTriangle(polygon[j], a, b, c) { contains = true; break }
                }
                guard !contains else { continue }

                result.append((UInt32(iPrev), UInt32(iCurr), UInt32(iNext)))
                indices.remove(at: i)
                clipped = true
                break
            }
            // Degenerate input — bail out with a fan so we still render something.
            if !clipped { break }
        }

        if indices.count == 3 {
            result.append((UInt32(indices[0]), UInt32(indices[1]), UInt32(indices[2])))
        } else if indices.count > 3 {
            for i in 1..<(indices.count - 1) {
                result.append((UInt32(indices[0]), UInt32(indices[i]), UInt32(indices[i + 1])))
            }
        }
        return result
    }

    private static func signedArea(_ p: [SIMD2<Float>]) -> Float {
        var sum: Float = 0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }

    private static func pointInTriangle(
        _ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>
    ) -> Bool {
        let d1 = cross2(b - a, p - a)
        let d2 = cross2(c - b, p - b)
        let d3 = cross2(a - c, p - c)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }
}
