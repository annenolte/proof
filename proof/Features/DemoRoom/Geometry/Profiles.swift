import Foundation
import simd

// Closed 2D outlines, used as input to `Mesh.extrude` and `Mesh.lathe`.
//
// Points are counter-clockwise. For extrusion they are read as (x, z) in the floor plane;
// for lathing they are read as (radius, y).

enum Outline {
    /// A circle, counter-clockwise from +X.
    static func circle(radius: Float, segments: Int = 48) -> [SIMD2<Float>] {
        (0..<segments).map { i in
            let t = Float(i) / Float(segments) * 2 * .pi
            return SIMD2(cos(t) * radius, sin(t) * radius)
        }
    }

    /// An ellipse — the round dining table top and most cushions read better slightly oval.
    static func ellipse(radiusX: Float, radiusY: Float, segments: Int = 48) -> [SIMD2<Float>] {
        (0..<segments).map { i in
            let t = Float(i) / Float(segments) * 2 * .pi
            return SIMD2(cos(t) * radiusX, sin(t) * radiusY)
        }
    }

    /// A rectangle with rounded corners, centred on the origin.
    static func roundedRect(
        width: Float, depth: Float, cornerRadius: Float, cornerSegments: Int = 8
    ) -> [SIMD2<Float>] {
        let hw = width / 2, hd = depth / 2
        let r = min(cornerRadius, min(hw, hd) - 0.0005)
        guard r > 0.0005 else {
            return [SIMD2(hw, -hd), SIMD2(hw, hd), SIMD2(-hw, hd), SIMD2(-hw, -hd)]
        }

        var points = [SIMD2<Float>]()
        // Corner centres, counter-clockwise starting bottom-right.
        let corners: [(SIMD2<Float>, Float)] = [
            (SIMD2(hw - r, -hd + r), -.pi / 2),
            (SIMD2(hw - r, hd - r), 0),
            (SIMD2(-hw + r, hd - r), .pi / 2),
            (SIMD2(-hw + r, -hd + r), .pi)
        ]
        for (centre, startAngle) in corners {
            for s in 0...cornerSegments {
                let t = startAngle + Float(s) / Float(cornerSegments) * (.pi / 2)
                points.append(centre + SIMD2(cos(t) * r, sin(t) * r))
            }
        }
        return points
    }

    /// A superellipse — the squircle silhouette used for the soft-edged upholstery.
    static func superellipse(
        width: Float, depth: Float, exponent: Float = 4, segments: Int = 64
    ) -> [SIMD2<Float>] {
        let a = width / 2, b = depth / 2
        return (0..<segments).map { i in
            let t = Float(i) / Float(segments) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = a * copysign(pow(abs(ct), 2 / exponent), ct)
            let y = b * copysign(pow(abs(st), 2 / exponent), st)
            return SIMD2(x, y)
        }
    }

    /// A smooth closed curve through the given control points, via Catmull-Rom.
    ///
    /// The living room's coffee table is an organic pebble form — two lobes with a soft
    /// waist. That shape has no analytic description, so it is drawn as control points
    /// and smoothed here.
    static func smoothClosed(
        through controlPoints: [SIMD2<Float>], subdivisions: Int = 12
    ) -> [SIMD2<Float>] {
        let n = controlPoints.count
        guard n >= 3 else { return controlPoints }
        var out = [SIMD2<Float>]()
        out.reserveCapacity(n * subdivisions)

        for i in 0..<n {
            let p0 = controlPoints[(i + n - 1) % n]
            let p1 = controlPoints[i]
            let p2 = controlPoints[(i + 1) % n]
            let p3 = controlPoints[(i + 2) % n]
            for s in 0..<subdivisions {
                let t = Float(s) / Float(subdivisions)
                let t2: Float = t * t
                let t3: Float = t2 * t
                // Catmull-Rom basis. Every scalar multiply is its own typed
                // statement and every sum is binary: folding the `c` and `d`
                // terms into one expression each exceeds the type-checker's
                // budget on Xcode 26.3 ("unable to type-check in reasonable
                // time"), because each `SIMD2<Float> * <integer literal>` is
                // an overload set the solver has to explore.
                let a: SIMD2<Float> = p1 * 2
                let b: SIMD2<Float> = (p2 - p0) * t

                let c0: SIMD2<Float> = p0 * 2
                let c1: SIMD2<Float> = p1 * 5
                let c2: SIMD2<Float> = p2 * 4
                var cSum: SIMD2<Float> = c0 - c1
                cSum += c2
                cSum -= p3
                let c: SIMD2<Float> = cSum * t2

                let d0: SIMD2<Float> = p1 * 3
                let d1: SIMD2<Float> = p2 * 3
                var dSum: SIMD2<Float> = d0 - p0
                dSum -= d1
                dSum += p3
                let d: SIMD2<Float> = dSum * t3

                var sum: SIMD2<Float> = a + b
                sum += c
                sum += d
                out.append(sum * 0.5)
            }
        }
        return out
    }

    /// The specific pebble outline of the living room coffee table, at unit scale.
    /// Multiply by the real half-extents to size it.
    static func pebble(width: Float, depth: Float, segments: Int = 10) -> [SIMD2<Float>] {
        let a = width / 2, b = depth / 2
        // Asymmetric lobes with a gentle pinch on one side, matching the reference.
        let control: [SIMD2<Float>] = [
            SIMD2(a * 1.00, b * 0.10),
            SIMD2(a * 0.86, b * 0.66),
            SIMD2(a * 0.38, b * 1.00),
            SIMD2(-a * 0.14, b * 0.82),
            SIMD2(-a * 0.58, b * 0.94),
            SIMD2(-a * 0.98, b * 0.42),
            SIMD2(-a * 0.92, -b * 0.34),
            SIMD2(-a * 0.44, -b * 0.92),
            SIMD2(a * 0.22, -b * 1.00),
            SIMD2(a * 0.80, -b * 0.70)
        ]
        return smoothClosed(through: control, subdivisions: segments)
    }

    /// Scales a profile in place — handy for reusing one outline at several sizes.
    static func scaled(_ profile: [SIMD2<Float>], _ sx: Float, _ sy: Float) -> [SIMD2<Float>] {
        profile.map { SIMD2($0.x * sx, $0.y * sy) }
    }

    static func offset(_ profile: [SIMD2<Float>], _ dx: Float, _ dy: Float) -> [SIMD2<Float>] {
        profile.map { SIMD2($0.x + dx, $0.y + dy) }
    }
}
