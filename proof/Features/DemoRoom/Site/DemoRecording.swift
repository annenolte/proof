import Foundation

// A real strong-motion recording of a past earthquake, baked into the app.
//
// Each one is a processed record from the Center for Engineering Strong Motion Data
// (CESMD — California Geological Survey and USGS), converted once by
// `scripts/bake_recording.py` into `Tremor/Resources/Recordings/recording-<eventID>.json`.
// Nothing is fetched at run time.
//
// The recording carries its station's soil in it: a seismometer records the ground as that
// ground filtered it. So no soil filter is applied on top. What the demo changes is only
// the amplitude — the record is scaled so its peak matches the ShakeMap estimate for the
// demo site, and the factor is shown on screen. Scaling a record by a constant is ordinary
// engineering practice; scaling it a lot is not, which is why `maximumScale` exists.

struct DemoRecording: Codable, Sendable, Equatable {

    /// The USGS / ComCat event id — the same id `DemoSite.Event` carries.
    let eventID: String
    let station: Station
    /// Sample interval of the stored components, seconds.
    let dt: Double
    /// The two horizontal components and the vertical, in g, as recorded.
    let h1: [Double]
    let h2: [Double]
    let up: [Double]

    struct Station: Codable, Sendable, Equatable {
        /// "NP" (USGS National Strong Motion Project) or "CE" (CSMIP).
        let network: String
        let code: String
        /// "Dublin; Fire Station"
        let name: String
        /// Distance from the demo site point, km.
        let distanceKm: Double
        /// Measured Vs30 at the station, m/s, when CESMD has one.
        let vs30: Double?
    }

    /// The citation CESMD's Data Attribution and Use Policy asks users to give.
    static let attribution = """
        Recordings: California Geological Survey and U.S. Geological Survey (2005), \
        Center for Engineering Strong Motion Data (CESMD), doi:10.5066/P13HTZQS.
        """

    /// Past this, a record is no longer telling you about *this* site — it is someone
    /// else's shaking turned up. Events that would need more stay synthetic.
    static let maximumScale = 3.5

    /// The demo is a performance, not a lab run, so only the part of the record that does
    /// anything is played: from a little before the shaking builds to a little after it
    /// fades, capped so the room never sits through a long quiet coda.
    static let leadIn = 2.0
    static let tail = 3.0
    static let maximumWindow = 24.0

    /// Largest horizontal resultant, in g.
    var peakHorizontalInG: Double {
        zip(h1, h2).reduce(0) { max($0, ($1.0 * $1.0 + $1.1 * $1.1).squareRoot()) }
    }

    /// The factor that brings this record's peak to `targetPGAInG`.
    func scale(toPGAInG target: Double) -> Double {
        let peak = peakHorizontalInG
        return peak > 0 ? target / peak : 1
    }

    /// "Recorded at Dublin; Fire Station, 14.9 km away · scaled ×1.2"
    func provenance(scale: Double) -> String {
        let place = "Recorded at \(station.name), \(String(format: "%.1f", station.distanceKm)) km away"
        // Within 10% of the original, the scaling is not worth a clause.
        guard abs(scale - 1) > 0.1 else { return place }
        return place + String(format: " · scaled ×%.1f", scale)
    }

    /// The record as the solver consumes it: m/s², scaled, trimmed to its strong-motion
    /// window, and tapered at both ends so the room is not jolted at the first sample.
    func groundMotion(scaledToPGAInG target: Double, name: String) -> GroundMotion {
        let factor = scale(toPGAInG: target) * Physics.g
        let window = strongMotionWindow()

        // Half-second cosine ramps. A trimmed record starts mid-signal; without a taper
        // its first sample is a step in acceleration, which the solver reads as a kick.
        let ramp = max(Int(0.5 / dt), 1)
        let count = window.count
        func taper(_ i: Int) -> Double {
            let fromEnd = count - 1 - i
            let edge = min(i, fromEnd)
            guard edge < ramp else { return 1 }
            return 0.5 - 0.5 * cos(.pi * Double(edge) / Double(ramp))
        }

        var ax: [Double] = [], az: [Double] = [], ay: [Double] = []
        ax.reserveCapacity(count); az.reserveCapacity(count); ay.reserveCapacity(count)
        for (offset, i) in window.enumerated() {
            let w = taper(offset) * factor
            ax.append(h1[i] * w)
            az.append(h2[i] * w)
            ay.append(up[i] * w)
        }
        return GroundMotion(dt: dt, ax: ax, az: az, ay: ay, name: name)
    }

    /// Indices from shortly before 5% of the horizontal Arias intensity has arrived to
    /// shortly after 95% has, capped at `maximumWindow`.
    func strongMotionWindow() -> Range<Int> {
        let n = min(h1.count, h2.count, up.count)
        guard n > 1 else { return 0..<n }

        var cumulative = [Double](repeating: 0, count: n)
        var sum = 0.0
        for i in 0..<n {
            sum += h1[i] * h1[i] + h2[i] * h2[i]
            cumulative[i] = sum
        }
        guard sum > 0 else { return 0..<n }

        let first = cumulative.firstIndex { $0 >= 0.05 * sum } ?? 0
        let last = cumulative.firstIndex { $0 >= 0.95 * sum } ?? (n - 1)
        let start = max(first - Int(Self.leadIn / dt), 0)
        let end = min(last + Int(Self.tail / dt), n - 1, start + Int(Self.maximumWindow / dt))
        return start..<(end + 1)
    }
}

// MARK: - Library

enum DemoRecordingLibrary {

    /// The baked recording for an event, or `nil` when there is none — because no
    /// instrument was there, because the event is a scenario, or because the nearest record
    /// would need more than `DemoRecording.maximumScale` to stand in for the site.
    static func recording(for event: DemoSite.Event, bundle: Bundle = .main) -> DemoRecording? {
        guard event.kind == .historical,
              let url = bundle.url(forResource: "recording-\(event.id)", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let recording = try? JSONDecoder().decode(DemoRecording.self, from: data),
              recording.eventID == event.id,
              recording.scale(toPGAInG: event.pgaInG) <= DemoRecording.maximumScale
        else { return nil }
        return recording
    }
}
