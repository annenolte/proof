//
//  ScanFlowChrome.swift
//  Tremor — Scan flow (S-09 … S-11) / shared pieces and shared words
//
//  The coverage bar, the coaching pill and the sentences the three screens say
//  about a scan. They live together because they have to agree: the bar's four
//  tracks, the "Done scanning" rule and S-10's checklist are three views of one
//  judgement — is this room good enough to build a report from — and if they
//  disagree the user is told two different things about the same scan.
//

import Foundation
import SwiftUI

// MARK: - Words

/// Every sentence the scan flow says about counts, coverage and quality.
///
/// Pure functions over the domain values, kept out of the views so the copy can
/// be tested. SPEC's rule for all of it: numbers carry units and context, and
/// nothing ever scolds.
enum ScanFlowCopy {

    /// "14 objects, 4 walls and 1 door" — the honest inventory S-10 leads with.
    static func inventory(_ quality: ScanQualityReport) -> String {
        var parts: [String] = []
        parts.append(count(quality.objectCount, "object", "objects"))
        parts.append(count(quality.wallCount, "wall", "walls"))
        if quality.openingCount > 0 {
            parts.append(count(quality.openingCount, "door or window", "doors or windows"))
        }
        return sentence(parts)
    }

    /// The same inventory for a room that has not been through the gate yet.
    static func inventory(_ room: ScannedRoom) -> String {
        var parts: [String] = []
        parts.append(count(room.objects.count, "object", "objects"))
        parts.append(count(room.surfaces.filter { $0.kind == .wall }.count, "wall", "walls"))
        let openings = room.surfaces.filter {
            $0.kind == .door || $0.kind == .window || $0.kind == .opening
        }.count
        if openings > 0 {
            parts.append(count(openings, "door or window", "doors or windows"))
        }
        return sentence(parts)
    }

    /// "about 12 m²", or nothing at all when the floor was never closed — an
    /// area of zero is not a fact worth stating.
    static func floorArea(_ squareMetres: Double, units: UnitSystem) -> String? {
        guard squareMetres > 0.5 else { return nil }
        switch units {
        case .metric:
            return "about \(Int(squareMetres.rounded())) m² of floor"
        case .imperial:
            return "about \(Int((squareMetres * 10.7639).rounded())) sq ft of floor"
        }
    }

    /// "2:14" — elapsed capture time, for the S-09 chip.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// What the "Done scanning" button says it still needs. Nil once it is
    /// enabled, so the caption disappears the moment it stops being true.
    static func doneRequirement(_ progress: ScanProgress) -> String? {
        guard !progress.isReadyToFinish else { return nil }
        return "Point at the walls and the floor — three walls is enough to start."
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// "a, b and c" — an Oxford-comma-free list, because this is a sentence a
    /// person reads aloud in their head.
    static func sentence(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}

// MARK: - Quality checks, as rows

/// One row of S-10's quality checklist: a check that either passed or did not,
/// with copy for both outcomes.
struct ScanQualityCheck: Identifiable, Hashable {
    var issue: ScanQualityReport.Issue
    var passed: Bool
    /// What we found, either way. The pass line is not a tick with no words —
    /// "All four walls closed" is more reassuring than a green check.
    var detail: String

    var id: String { issue.rawValue }
    var title: String { issue.title }
    var symbolName: String { passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    var tint: Color { passed ? TremorColor.success : TremorColor.warning }

    /// The four checks of SPEC §1.4 S-10, read off a quality report.
    static func checks(for quality: ScanQualityReport) -> [ScanQualityCheck] {
        let issues = Set(quality.issues)
        return [
            ScanQualityCheck(
                issue: .roomShape,
                passed: !issues.contains(.roomShape),
                detail: issues.contains(.roomShape)
                    ? ScanQualityReport.Issue.roomShape.message
                    : "\(ScanFlowCopy.count(quality.wallCount, "wall", "walls")) around a closed floor."),
            ScanQualityCheck(
                issue: .wallCompleteness,
                passed: !issues.contains(.wallCompleteness),
                detail: issues.contains(.wallCompleteness)
                    ? ScanQualityReport.Issue.wallCompleteness.message
                    : "Every wall was scanned from floor to ceiling."),
            ScanQualityCheck(
                issue: .confidence,
                passed: !issues.contains(.confidence),
                detail: issues.contains(.confidence)
                    ? ScanQualityReport.Issue.confidence.message
                    : "\(Int((quality.highConfidenceFraction * 100).rounded()))% of what we found was a confident match."),
            ScanQualityCheck(
                issue: .noObjects,
                passed: !issues.contains(.noObjects),
                detail: issues.contains(.noObjects)
                    ? ScanQualityReport.Issue.noObjects.message
                    : ScanFlowCopy.count(quality.objectCount, "piece of furniture", "pieces of furniture") + " found.")
        ]
    }
}

// MARK: - Coverage bar

/// SPEC §1.4 S-09: "a coverage bar — not a spinner. Four segments labelled
/// Walls · Floor · Doors · Objects."
///
/// Four tracks rather than one, because a single percentage tells someone
/// nothing about where to point the phone next. Completion is carried by the
/// fill *and* by a check beside the label, so the bar survives greyscale, a
/// bright room and colour-vision deficiency.
struct ScanCoverageBar: View {

    var progress: ScanProgress

    private var tracks: [(label: String, value: Double)] {
        [("Walls", progress.walls),
         ("Floor", progress.floor),
         ("Doors", progress.openings),
         ("Objects", progress.objects)]
    }

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.xs) {
            ForEach(tracks, id: \.label) { track in
                trackView(label: track.label, value: track.value)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan coverage")
        .accessibilityValue(spokenValue)
    }

    private func trackView(label: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        let isComplete = clamped >= 0.999
        return VStack(spacing: TremorSpacing.xxs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TremorColor.inkInverse.opacity(0.22))
                    Capsule()
                        .fill(isComplete ? TremorColor.accent : TremorColor.inkInverse)
                        .frame(width: geometry.size.width * clamped)
                }
            }
            .frame(height: TremorSize.grabberHeight)

            HStack(spacing: TremorSpacing.xxs) {
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: TremorType.caption.spec.size, weight: .bold))
                }
                Text(label)
                    .tremorType(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(TremorColor.inkInverse.opacity(isComplete ? 1 : 0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var spokenValue: String {
        tracks
            .map { "\($0.label), \(Int(($0.value * 100).rounded())) percent" }
            .joined(separator: ". ")
    }
}

// MARK: - Coaching pill

/// SPEC §1.4 S-09 layer 1: the live instruction, in a pill over the camera.
///
/// The tone changes the glyph's colour, never the words' legibility, and the
/// words alone always say what to do — colour is the second channel, not the
/// first.
struct ScanCoachingPill: View {

    var coaching: ScanCoaching
    /// Hidden when the pill is on a narrow layout or the copy is already clear.
    var showsDetail: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color {
        switch coaching.tone {
        case .steady: return TremorColor.success
        case .nudge: return TremorColor.primary
        case .attention: return TremorColor.warning
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.xs) {
            Image(systemName: coaching.symbolName)
                .font(.system(size: TremorControlMetrics.glyphMedium, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(coaching.headline)
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if showsDetail, let detail = coaching.detail, !dynamicTypeSize.isAccessibilitySize {
                    Text(detail)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.vertical, TremorSpacing.sm)
        .background(TremorColor.surface.opacity(0.94), in: Capsule())
        .tremorShadow(.raised)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coaching.headline)
        .accessibilityValue(coaching.detail ?? "")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - A chip that floats over the stage

/// The small dark-ground chip S-09 uses for the elapsed timer and the object
/// count: legible on a camera feed without stealing attention from the room.
struct ScanOverlayChip: View {

    var systemImage: String?
    var text: String
    var accessibilityLabelText: String?

    var body: some View {
        HStack(spacing: TremorSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
            }
            Text(text)
                .tremorType(.caption, numeric: true)
        }
        .foregroundStyle(TremorColor.inkInverse)
        .padding(.horizontal, TremorSpacing.sm)
        .padding(.vertical, TremorSpacing.xxs)
        .background(TremorColor.ink.opacity(0.62), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText ?? text)
    }
}

// MARK: - Previews

#Preview("Coverage bar") {
    VStack(spacing: TremorSpacing.xl) {
        ScanCoverageBar(progress: ScanProgress())
        ScanCoverageBar(progress: ScanCoach.progress(
            walls: 2, completeWalls: 1, floors: 1, openings: 0, objects: 2, elapsed: 30))
        ScanCoverageBar(progress: ScanCoach.progress(
            walls: 4, completeWalls: 4, floors: 1, openings: 2, objects: 9, elapsed: 120))
    }
    .padding(TremorSpacing.lg)
    .background(TremorColor.ink)
}

#Preview("Coaching pill") {
    VStack(spacing: TremorSpacing.md) {
        ForEach(ScanCoach.Cue.allCases, id: \.self) { cue in
            ScanCoachingPill(coaching: ScanCoach.coaching(for: cue))
        }
        ScanCoachingPill(coaching: ScanCoach.readyToFinish)
    }
    .padding(TremorSpacing.lg)
    .background(TremorColor.ink)
}

#Preview("Overlay chips") {
    HStack(spacing: TremorSpacing.xs) {
        ScanOverlayChip(systemImage: "timer", text: "2:14")
        ScanOverlayChip(text: "9 objects found")
    }
    .padding(TremorSpacing.lg)
    .background(TremorColor.ink)
}
