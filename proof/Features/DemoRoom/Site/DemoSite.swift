import Foundation

// Where the demo apartment is, and what the ground there has done and could do.
//
// Every number below is a snapshot of real USGS data, fetched once on 3 October 2026 and
// baked in so the demo needs no network and gives the same answer on every run. None of it
// is invented and none of it is tuned for drama. How each figure was obtained:
//
//   • Design value — ASCE 7-22 web service (earthquake.usgs.gov/ws/building-codes/asce7-22),
//     risk category II, site class D. `pgam` is the site-adjusted MCE_G peak ground
//     acceleration: the code's ~2%-in-50-year shaking for this soil.
//   • Vs30 — the `SVEL` column of the ShakeMap grids below, at the cell nearest the point.
//     241 m/s is NEHRP site class D, which is the app's `.medium`.
//   • Faults — USGS Quaternary Fault and Fold Database (Qfaults MapServer, layer 21),
//     shortest distance from the point to the mapped trace.
//   • Scenarios — the BSSC2014 scenario ShakeMap catalogue; historical events — ComCat
//     ShakeMaps. MMI and PGA are read from each event's grid.xml at the cell nearest the
//     point (−121.7667, 37.6833), PGA converted from %g to g.
//
// The point is downtown Livermore, deliberately not anyone's street address. The grid
// cells are about a kilometre across, so these are neighbourhood values, not a survey of
// one building — which is exactly what `uncertaintyNote` says out loud.

struct DemoSite: Sendable {

    struct Fault: Identifiable, Sendable {
        var id: String { name }
        let name: String
        /// Shortest distance from the site point to the mapped trace, km.
        let distanceKm: Double
        /// Slip rate and sense as the Qfaults database states them.
        let activity: String
    }

    struct Event: Identifiable, Hashable, Sendable {
        enum Kind: Sendable { case scenario, historical }

        /// The USGS event id, so any figure here can be looked up and checked.
        let id: String
        let kind: Kind
        /// "Greenville fault" for a scenario, "Livermore" for a historical event.
        let name: String
        let magnitude: Double
        /// Year it happened. `nil` for a scenario.
        let year: Int?
        /// ShakeMap MMI at the site.
        let mmi: Double
        /// ShakeMap PGA at the site, in g.
        let pgaInG: Double

        /// The whole-number intensity the rest of the demo speaks in.
        var intensity: MercalliIntensity { IntensityScale.bin(forMMI: mmi) }

        /// "M6.9 Greenville fault" · "1980 Livermore, M5.8"
        var title: String {
            let m = String(format: "M%.1f", magnitude)
            if let year { return "\(year) \(name), \(m)" }
            return "\(m) \(name)"
        }

        /// "MMI 8.0 · 0.39 g here"
        var siteReading: String {
            String(format: "MMI %.1f · %.2f g here", mmi, pgaInG)
        }
    }

    /// What the screen calls the place.
    let place: String
    let latitude: Double
    let longitude: Double

    /// Shear-wave velocity in the top 30 m, m/s.
    let vs30: Double
    let siteClass: String
    /// The app's soil class for that Vs30 — fed straight to the accelerogram synthesizer.
    let soil: SoilClass

    /// ASCE 7-22 site-adjusted MCE_G PGA, in g.
    let designPGAInG: Double

    /// Nearest first.
    let faults: [Fault]
    /// The first is the headline: the fault with the best-measured slip rate nearby, and
    /// the one that has already ruptured under this town. The rest follow by MMI.
    let scenarios: [Event]
    /// The one under this town first, then by year.
    let history: [Event]

    let snapshotDate: String

    /// Rule 4: never hide uncertainty. A number with a USGS name on it invites more trust
    /// than a slider does, so the error band has to be stated more plainly, not less.
    let uncertaintyNote = """
        ShakeMap values are estimates for a one-kilometre grid cell in downtown Livermore, \
        not a measurement of this building. Shaking at any single site commonly runs from \
        about half to nearly double the estimate.
        """

    var headline: Event { scenarios[0] }
    var nearestFault: Fault { faults[0] }

    /// "Livermore, CA · Greenville fault 6.7 km"
    var summary: String {
        "\(place) · \(headline.name) \(String(format: "%.1f", nearestActiveFaultDistance)) km"
    }

    /// Distance to the headline scenario's fault rather than to the nearest trace: the
    /// closer traces have no measured slip rate, and the fault a resident should know by
    /// name is the one the headline scenario ruptures.
    private var nearestActiveFaultDistance: Double {
        faults.first { $0.name == headline.name }?.distanceKm ?? nearestFault.distanceKm
    }
}

extension DemoSite {

    static let livermore = DemoSite(
        place: "Livermore, CA",
        latitude: 37.6819,
        longitude: -121.7680,
        vs30: 241,
        siteClass: "D",
        soil: .medium,
        designPGAInG: 0.72,
        faults: [
            Fault(name: "Las Positas fault", distanceKm: 3.6,
                  activity: "Late Quaternary, left-lateral"),
            Fault(name: "Greenville fault", distanceKm: 6.7,
                  activity: "1–5 mm/yr, right-lateral · source of the 1980 quake"),
            Fault(name: "Calaveras fault", distanceKm: 12.8,
                  activity: "Over 5 mm/yr, right-lateral"),
        ],
        scenarios: [
            Event(id: "bssc2014greenvilleno2011cfme_m6p86_se", kind: .scenario,
                  name: "Greenville fault", magnitude: 6.86, year: nil,
                  mmi: 7.98, pgaInG: 0.39),
            Event(id: "bssc2014laspositasellbgeol_m6p5_se", kind: .scenario,
                  name: "Las Positas fault", magnitude: 6.5, year: nil,
                  mmi: 8.22, pgaInG: 0.44),
            Event(id: "bssc2014calaverasno2011cfmel_m6p86_se", kind: .scenario,
                  name: "Calaveras fault", magnitude: 6.86, year: nil,
                  mmi: 7.48, pgaInG: 0.28),
            Event(id: "bssc2014haywardhnhsheshaw09m_m7p36_se", kind: .scenario,
                  name: "Hayward fault", magnitude: 7.36, year: nil,
                  mmi: 7.30, pgaInG: 0.25),
        ],
        history: [
            Event(id: "nc1050040", kind: .historical,
                  name: "Livermore", magnitude: 5.8, year: 1980,
                  mmi: 6.0, pgaInG: 0.16),
            Event(id: "nc216859", kind: .historical,
                  name: "Loma Prieta", magnitude: 6.9, year: 1989,
                  mmi: 6.3, pgaInG: 0.11),
            Event(id: "nc17204", kind: .historical,
                  name: "Morgan Hill", magnitude: 6.2, year: 1984,
                  mmi: 6.4, pgaInG: 0.13),
            Event(id: "official19060418131226300_12", kind: .historical,
                  name: "San Francisco", magnitude: 7.9, year: 1906,
                  mmi: 6.9, pgaInG: 0.24),
        ],
        snapshotDate: "3 Oct 2026"
    )
}
