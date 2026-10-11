//
//  RoomCard.swift
//  Tremor — Features / Library (S-06)
//
//  One room, as a row in the library.
//
//  The thumbnail is the interesting part. SPEC S-06 asks for "an isometric
//  render of the room's floor plan, generated at save time" — and a room that
//  has one gets it, straight from the package. A room that does not (every
//  bundled fixture, every room scanned before the renderer existed) gets a
//  *drawn* isometric plate instead: the same 2:1 projection, tinted by the
//  room's risk band, with a block for roughly every four objects in it, laid out
//  deterministically from the room's identifier so a given room always looks
//  like itself.
//
//  That is deliberately not a grey placeholder. A library of grey squares reads
//  as broken; a library of tinted isometric plates reads as a set of rooms, and
//  the tint means the list is already a risk list before a single word is read.
//

import SwiftUI
import UIKit

// MARK: - Isometric plate

/// A procedural isometric room tile: a floor diamond and a few extruded blocks.
///
/// Pure geometry, no assets, no randomness at render time — `seed` fixes the
/// layout, so the same room draws identically on every launch and in every
/// snapshot.
struct RoomIsometricGlyph: View {

    /// Colours the plate. `nil` uses the brand lavender, for a room that has
    /// never been simulated.
    var band: RiskBand?
    /// How many objects the room holds; sets how many blocks are drawn.
    var objectCount: Int
    /// Fixes the layout. The room's identifier in practice.
    var seed: UInt64

    private var mark: Color { band.map(LibraryBandPalette.mark) ?? TremorColor.primary }
    private var fill: Color { band.map(LibraryBandPalette.surface) ?? TremorColor.primarySoft }

    /// One block per four objects, one at minimum, three at most — a tile, not
    /// an inventory.
    private var blockCount: Int {
        min(3, max(1, (objectCount + 3) / 4))
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // 2:1 isometric: the plate is twice as wide as it is tall.
            let halfWidth = size * 0.40
            let halfHeight = halfWidth / 2
            let plate = IsoPlate(centre: centre, halfWidth: halfWidth, halfHeight: halfHeight)

            ZStack {
                plate.floorPath
                    .fill(mark.opacity(0.16))
                plate.floorPath
                    .stroke(mark.opacity(0.55), lineWidth: TremorSize.hairline)

                ForEach(Array(blocks(in: plate).enumerated()), id: \.offset) { _, block in
                    ZStack {
                        block.left.fill(mark.opacity(0.42))
                        block.right.fill(mark.opacity(0.62))
                        block.top.fill(mark.opacity(0.88))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(fill)
        .accessibilityHidden(true)
    }

    // MARK: Layout

    /// Three fixed footprints on the plate, so blocks never overlap badly; which
    /// ones are used, and how tall they are, comes from the seed.
    private func blocks(in plate: IsoPlate) -> [IsoBlock] {
        let slots: [(u: CGFloat, v: CGFloat, size: CGFloat)] = [
            (0.08, 0.10, 0.30),
            (0.58, 0.16, 0.26),
            (0.24, 0.62, 0.28),
        ]
        var generator = SplitMix(seed: seed)
        return (0..<blockCount).map { index in
            let slot = slots[index % slots.count]
            let height = 0.22 + CGFloat(generator.nextUnit()) * 0.30
            return plate.block(u: slot.u, v: slot.v, footprint: slot.size, height: height)
        }
    }
}

/// The isometric basis for one tile.
private struct IsoPlate {
    let centre: CGPoint
    let halfWidth: CGFloat
    let halfHeight: CGFloat

    /// Unit square (u, v) → screen point. `u` runs to the lower-right, `v` to
    /// the lower-left, which is the standard 2:1 game-art projection.
    func point(_ u: CGFloat, _ v: CGFloat, lift: CGFloat = 0) -> CGPoint {
        CGPoint(
            x: centre.x + (u - v) * halfWidth,
            y: centre.y + (u + v - 1) * halfHeight - lift * halfWidth)
    }

    var floorPath: Path {
        var path = Path()
        path.move(to: point(0, 0))
        path.addLine(to: point(1, 0))
        path.addLine(to: point(1, 1))
        path.addLine(to: point(0, 1))
        path.closeSubpath()
        return path
    }

    func block(u: CGFloat, v: CGFloat, footprint s: CGFloat, height: CGFloat) -> IsoBlock {
        // Only the three faces a 2:1 isometric viewer can see are built, so the
        // back-left base corner is never needed.
        let b10 = point(u + s, v)
        let b11 = point(u + s, v + s)
        let b01 = point(u, v + s)
        let t00 = point(u, v, lift: height)
        let t10 = point(u + s, v, lift: height)
        let t11 = point(u + s, v + s, lift: height)
        let t01 = point(u, v + s, lift: height)
        return IsoBlock(
            top: Path { $0.addLines([t00, t10, t11, t01]); $0.closeSubpath() },
            right: Path { $0.addLines([b10, b11, t11, t10]); $0.closeSubpath() },
            left: Path { $0.addLines([b01, b11, t11, t01]); $0.closeSubpath() })
    }
}

private struct IsoBlock {
    let top: Path
    let right: Path
    let left: Path
}

/// A tiny deterministic generator. Not for anything that needs real randomness —
/// only for making a decorative layout stable across launches.
private struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

extension UUID {
    /// A stable 64-bit seed, for anything decorative that must not change
    /// between launches.
    var glyphSeed: UInt64 {
        withUnsafeBytes(of: uuid) { raw in
            var value: UInt64 = 0xCBF29CE484222325
            for byte in raw {
                value = (value ^ UInt64(byte)) &* 0x100000001B3
            }
            return value
        }
    }
}

// MARK: - Thumbnail

/// The room's saved render if there is one, the drawn plate if there is not.
///
/// Loading is per-row and cancellable; a row that scrolls away before its
/// thumbnail arrives simply keeps the plate, which already looks finished.
struct RoomThumbnail: View {

    var room: RoomSummary
    var size: CGFloat = TremorSize.row

    @Environment(\.tremor) private var tremor
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoomIsometricGlyph(
                    band: room.latestAssessment?.band,
                    objectCount: room.objectCount,
                    seed: room.id.glyphSeed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                .strokeBorder(TremorColor.ink.opacity(0.06), lineWidth: TremorSize.hairline)
        }
        .accessibilityHidden(true)
        .task(id: room.id) {
            guard room.hasThumbnail else { return }
            let data = await tremor.rooms.loadThumbnail(for: room.id)
            guard !Task.isCancelled, let data else { return }
            image = UIImage(data: data)
        }
    }
}

// MARK: - Status pill

/// The trailing status. A band badge when the room has been shaken, a neutral
/// "Not shaken yet" pill when it has not, and a danger pill when the package is
/// unreadable. Never colour on its own — each one carries a word.
struct RoomStatusPill: View {

    var room: RoomSummary

    var body: some View {
        if room.isDamaged {
            pill("Damaged",
                 symbol: "exclamationmark.triangle.fill",
                 mark: TremorColor.danger,
                 fill: TremorColor.danger.opacity(0.12))
        } else if let assessment = room.latestAssessment {
            RiskBadge(assessment.band)
        } else {
            pill("Not shaken yet",
                 symbol: "circle.dashed",
                 mark: TremorColor.inkSecondary,
                 fill: TremorColor.surfaceSunken)
        }
    }

    private func pill(_ title: String, symbol: String, mark: Color, fill: Color) -> some View {
        HStack(spacing: TremorSpacing.xxs) {
            Image(systemName: symbol)
                .font(TremorFont.font(.captionEmphasis))
                .imageScale(.small)
            Text(title)
                .tremorType(.captionEmphasis)
                .lineLimit(1)
        }
        .foregroundStyle(mark)
        .padding(.horizontal, TremorSpacing.xs)
        .padding(.vertical, TremorSpacing.xxs)
        .background(fill, in: Capsule())
        .fixedSize()
    }
}

// MARK: - The card

/// One room in the library list: thumbnail, name, metadata, status, chevron.
///
/// The whole card is one button. Rename, duplicate, share and delete are offered
/// three ways — a swipe, the "more" control, and explicit VoiceOver actions — so
/// no one has to discover a gesture to manage their own library.
struct RoomCard: View {

    var room: RoomSummary
    var isEditing: Bool
    var onOpen: () -> Void
    var onMore: () -> Void
    var onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the thumbnail and the trailing block would squeeze
    /// the name to two characters, so the row stacks instead.
    private var isCompact: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // The delete control is a *sibling* of the card, never a button inside
        // one: a nested button inside another button's label does not reliably
        // receive its own taps, and a delete that sometimes opens the room
        // instead is worse than no delete at all.
        HStack(spacing: TremorSpacing.xs) {
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: TremorControlMetrics.glyphLarge, weight: .semibold))
                        .foregroundStyle(TremorColor.danger)
                        .frame(width: TremorSize.minimumTapTarget,
                               height: TremorSize.minimumTapTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(room.name)")
                .transition(.opacity)
            }

            card
        }
    }

    /// The band badge sits **under** the metadata rather than opposite it.
    ///
    /// SPEC's rich row puts it at the trailing edge, and on paper that is the
    /// tidier arrangement — but measured on a 393pt screen a 56pt plate, a
    /// badge and a chevron leave about 130pt for the text, and "12 objects ·
    /// shaken 4 Aug" needs 160. The trailing arrangement therefore wraps every
    /// subtitle onto two ragged lines. Stacking the badge under the metadata
    /// gives the text the full column, keeps the verdict at the same reading
    /// position for every row, and needs no separate branch at accessibility
    /// text sizes.
    private var card: some View {
        TremorCard.tappable(
            padding: TremorSpacing.sm,
            accessibilityLabel: room.name,
            accessibilityHint: room.isDamaged
                ? "Opens what we can still show of this room"
                : "Opens this room in 3D",
            action: onOpen
        ) {
            HStack(alignment: isCompact ? .top : .center, spacing: TremorSpacing.sm) {
                RoomThumbnail(room: room, size: Metric.plate)

                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(room.name)
                        .tremorType(.title3)
                        .foregroundStyle(TremorColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(LibraryFormatting.rowSubtitle(for: room))
                        .tremorType(.footnote)
                        .foregroundStyle(room.isDamaged ? TremorColor.danger : TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    RoomStatusPill(room: room)
                        .padding(.top, TremorSpacing.hair)
                }

                if !isCompact {
                    Image(systemName: "chevron.right")
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                        .foregroundStyle(TremorColor.inkTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityValue(LibraryFormatting.rowAccessibilityValue(for: room))
        .accessibilityAction(named: "More options", onMore)
        .accessibilityAction(named: "Delete", onDelete)
    }

    private enum Metric {
        /// 64pt — a touch larger than the Lyft rich-row 56, because the plate is
        /// the only picture of the room the library shows and it carries the
        /// band tint.
        static let plate: CGFloat = TremorSize.row + TremorSpacing.xs
    }
}

// MARK: - Previews

private func previewSummary(
    name: String,
    kind: RoomKind = .bedroom,
    objects: Int = 12,
    band: RiskBand? = .severe,
    score: Double = 84,
    damaged: Bool = false
) -> RoomSummary {
    RoomSummary(
        id: RoomFixtures.stableID(name),
        name: name,
        kind: kind,
        objectCount: objects,
        createdAt: Date().addingTimeInterval(-86_400 * 12),
        updatedAt: Date().addingTimeInterval(-86_400 * 2),
        isSample: false,
        hasThumbnail: false,
        isDamaged: damaged,
        latestAssessment: band.map {
            AssessmentSummary(
                id: UUID(), intensity: .viii, band: $0, score: score,
                createdAt: Date().addingTimeInterval(-86_400 * 2))
        })
}

#Preview("Room cards") {
    ScrollView {
        VStack(spacing: TremorSpacing.sm) {
            RoomCard(room: previewSummary(name: "Bedroom"),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "Living room", kind: .livingRoom,
                                          objects: 9, band: .moderate, score: 38),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "Nursery", kind: .nursery,
                                          objects: 5, band: .low, score: 12),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "Studio", kind: .other,
                                          objects: 21, band: nil),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "Garage", kind: .garage, damaged: true),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "Bedroom"),
                     isEditing: true, onOpen: {}, onMore: {}, onDelete: {})
        }
        .padding(TremorSpacing.md)
    }
    .tremorScreen(inset: 0)
}

#Preview("Room cards — accessibility 3") {
    ScrollView {
        VStack(spacing: TremorSpacing.sm) {
            RoomCard(room: previewSummary(name: "Bedroom"),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
            RoomCard(room: previewSummary(name: "A room with a very long name indeed",
                                          kind: .office, objects: 1, band: .high, score: 61),
                     isEditing: false, onOpen: {}, onMore: {}, onDelete: {})
        }
        .padding(TremorSpacing.md)
    }
    .tremorScreen(inset: 0)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Isometric plates") {
    HStack(spacing: TremorSpacing.md) {
        ForEach(RiskBand.allCases) { band in
            RoomIsometricGlyph(band: band, objectCount: 12, seed: UInt64(band.order &+ 7))
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
        }
    }
    .padding(TremorSpacing.xl)
    .tremorScreen()
}
