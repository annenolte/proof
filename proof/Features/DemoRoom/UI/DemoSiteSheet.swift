import SwiftUI

// What the ground under the demo apartment has done and could do, from USGS data.
//
// Reached from the single location chip over the room, so the room's own chrome gains one
// line and no more. Tapping a quake here shakes the room with it — the sheet is a picker
// that happens to explain itself, not a page to read and then leave.

struct DemoSiteSheet: View {
    let site: DemoSite
    var onRun: (DemoSite.Event) -> Void

    /// Which past earthquakes will play a real seismometer record. Looked up once, not per
    /// render — each lookup decodes a bundled file.
    private let recorded: Set<String>

    init(site: DemoSite, onRun: @escaping (DemoSite.Event) -> Void) {
        self.site = site
        self.onRun = onRun
        recorded = Set(site.history.filter {
            DemoRecordingLibrary.recording(for: $0) != nil
        }.map(\.id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                header
                facts
                eventSection(
                    "What could happen here",
                    caption: "USGS scenario earthquakes. Tap one to shake the room with it.",
                    events: site.scenarios)
                eventSection(
                    "What already has",
                    caption: "Real earthquakes, as USGS ShakeMaps estimate they were felt here. "
                        + "Marked ones replay an actual seismometer recording.",
                    events: site.history)

                Text(site.uncertaintyNote)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)

                // CESMD's data policy asks for this citation wherever its records are used.
                if !recorded.isEmpty {
                    Text(DemoRecording.attribution)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }
            .padding(TremorSpacing.pageInset)
        }
        .background(TremorColor.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text("Your site")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            Text(site.place)
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
            Text("Downtown point · USGS data from \(site.snapshotDate)")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            fact(
                "Code design shaking",
                value: String(format: "%.2f g", site.designPGAInG),
                detail: "What building codes plan for here — roughly a 2% chance in 50 years (ASCE 7-22)")
            TremorRowDivider()
            fact(
                "Soil",
                value: "Class \(site.siteClass)",
                detail: "Stiff soil, Vs30 \(Int(site.vs30)) m/s — it shakes longer and harder than rock")
            ForEach(site.faults) { fault in
                TremorRowDivider()
                fact(
                    fault.name,
                    value: String(format: "%.1f km", fault.distanceKm),
                    detail: fault.activity)
            }
        }
    }

    private func fact(_ title: String, value: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.ink)
                Text(detail)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            Spacer(minLength: TremorSpacing.sm)
            Text(value)
                .tremorType(.body, numeric: true)
                .foregroundStyle(TremorColor.ink)
        }
        .padding(.vertical, TremorSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func eventSection(
        _ title: String, caption: String, events: [DemoSite.Event]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TremorSectionHeader(title)
            Text(caption)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .padding(.bottom, TremorSpacing.xs)
            ForEach(events) { event in
                eventRow(event)
                TremorRowDivider()
            }
        }
    }

    private func eventRow(_ event: DemoSite.Event) -> some View {
        Button {
            TremorHaptic.light.play()
            onRun(event)
        } label: {
            HStack(spacing: TremorSpacing.sm) {
                Text(event.intensity.roman)
                    .tremorType(.captionEmphasis)
                    .foregroundStyle(TremorColor.inkInverse)
                    .frame(width: 40, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous)
                            .fill(TremorColor.ink))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .tremorType(.body)
                        .foregroundStyle(TremorColor.ink)
                    HStack(spacing: TremorSpacing.xs) {
                        Text(event.siteReading)
                            .tremorType(.caption, numeric: true)
                            .foregroundStyle(TremorColor.inkTertiary)
                        if recorded.contains(event.id) {
                            Label("Recorded", systemImage: "waveform")
                                .tremorType(.caption)
                                .foregroundStyle(TremorColor.primary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(TremorColor.primary)
            }
            .padding(.vertical, TremorSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.siteReading)")
        .accessibilityHint("Shakes the room with this earthquake")
    }
}
