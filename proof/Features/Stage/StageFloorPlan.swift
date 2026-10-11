//
//  StageFloorPlan.swift
//  Tremor — the S-12 fallback when meshes cannot be built
//
//  SPEC §1.4 S-12 *Error*: "mesh generation failure falls back to a flat
//  floor-plan 2D view with a `warning` banner. The report is unaffected."
//
//  So this is a real screen, not a placeholder: it is drawn from the same
//  parametric room the 3D stage would have used, it is selectable, and every
//  object is an accessibility element with its name and its verdict — which is
//  more than the `RealityView` can offer VoiceOver anyway.
//

import SwiftUI
import simd

struct StageFloorPlan: View {

    let room: ScannedRoom?
    let selection: UUID?
    let assessment: RoomAssessment?
    let onSelect: (UUID?) -> Void

    var body: some View {
        GeometryReader { geometry in
            let plan = StagePlanGeometry(room: room, size: geometry.size)
            ZStack {
                Color.clear.contentShape(Rectangle()).onTapGesture { onSelect(nil) }

                ForEach(walls) { wall in
                    let rect = plan.rect(centre: wall.placement.centre,
                                         width: wall.extents.width,
                                         depth: max(wall.extents.depth, 0.08))
                    Rectangle()
                        .fill(TremorColor.inkInverse.opacity(0.22))
                        .frame(width: rect.width, height: rect.height)
                        .rotationEffect(.radians(Double(-wall.placement.yaw)))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityHidden(true)
                }

                ForEach(objects) { object in
                    objectShape(object, plan: plan)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floor plan of your room")
    }

    private var walls: [RoomSurface] { room?.walls ?? [] }
    private var objects: [ScannedObject] { room?.objects ?? [] }

    private func objectShape(_ object: ScannedObject, plan: StagePlanGeometry) -> some View {
        let rect = plan.rect(centre: object.placement.centre,
                             width: object.extents.width,
                             depth: object.extents.depth)
        let band = assessment?.risk(for: object.id)?.band
        let isSelected = object.id == selection
        return RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
            .fill(band?.stageSurface.opacity(0.9) ?? TremorColor.primarySoft.opacity(0.55))
            .overlay {
                RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
                    .strokeBorder(
                        isSelected ? TremorColor.primary : (band?.stageMark ?? TremorColor.primary).opacity(0.5),
                        lineWidth: isSelected ? TremorSize.strokeEmphasis : TremorSize.hairline)
            }
            .frame(width: max(rect.width, TremorSpacing.xs),
                   height: max(rect.height, TremorSpacing.xs))
            .rotationEffect(.radians(Double(-object.placement.yaw)))
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(isSelected ? nil : object.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(object.type.displayName)
            .accessibilityValue(spokenValue(for: object))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func spokenValue(for object: ScannedObject) -> String {
        guard let risk = assessment?.risk(for: object.id) else {
            return "Not simulated yet"
        }
        return "\(risk.band.displayName) risk, \(Int(risk.score.rounded())) out of 100"
    }
}

// MARK: - Plan geometry

/// Maps room metres (x, z) onto view points, preserving aspect and leaving a
/// margin. A struct so the mapping is testable without a view.
struct StagePlanGeometry {

    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat

    init(room: ScannedRoom?, size: CGSize, margin: CGFloat = TremorSpacing.section) {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude

        func include(_ centre: SIMD3<Float>, _ width: Float, _ depth: Float) {
            let reach = max(width, depth) / 2
            minX = min(minX, centre.x - reach)
            maxX = max(maxX, centre.x + reach)
            minZ = min(minZ, centre.z - reach)
            maxZ = max(maxZ, centre.z + reach)
        }

        for surface in room?.surfaces ?? [] {
            include(surface.placement.centre, surface.extents.width, max(surface.extents.depth, 0.1))
        }
        for object in room?.objects ?? [] {
            include(object.placement.centre, object.extents.width, object.extents.depth)
        }

        guard minX < maxX, minZ < maxZ else {
            scale = 1
            offsetX = size.width / 2
            offsetY = size.height / 2
            return
        }

        let spanX = CGFloat(maxX - minX)
        let spanZ = CGFloat(maxZ - minZ)
        let usableWidth = max(size.width - margin * 2, 1)
        let usableHeight = max(size.height - margin * 2, 1)
        let fit = min(usableWidth / max(spanX, 0.001), usableHeight / max(spanZ, 0.001))

        scale = fit
        offsetX = size.width / 2 - CGFloat(minX + maxX) / 2 * fit
        offsetY = size.height / 2 - CGFloat(minZ + maxZ) / 2 * fit
    }

    func point(x: Float, z: Float) -> CGPoint {
        CGPoint(x: CGFloat(x) * scale + offsetX, y: CGFloat(z) * scale + offsetY)
    }

    func rect(centre: SIMD3<Float>, width: Float, depth: Float) -> CGRect {
        let origin = point(x: centre.x, z: centre.z)
        let w = CGFloat(width) * scale
        let h = CGFloat(depth) * scale
        return CGRect(x: origin.x - w / 2, y: origin.y - h / 2, width: w, height: h)
    }
}

// MARK: - Previews

#Preview("Floor plan fallback") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        StageFloorPlan(
            room: RoomFixtures.dangerousBedroom,
            selection: RoomFixtures.dangerousBedroom.objects.first?.id,
            assessment: RiskEngine(ensembleSize: 3).assess(
                room: RoomFixtures.dangerousBedroom, intensity: .viii),
            onSelect: { _ in })
    }
}

#Preview("Floor plan — no room") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        StageFloorPlan(room: nil, selection: nil, assessment: nil, onSelect: { _ in })
    }
}
