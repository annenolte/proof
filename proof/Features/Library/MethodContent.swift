//
//  MethodContent.swift
//  Tremor — Features / Library (S-20)
//
//  The bibliography, and the numbering that ties it to the prose.
//
//  Every claim S-20 makes carries a superscript marker, and every marker resolves
//  to an entry here. The numbers are assigned by position in `all`, so adding a
//  source in the middle renumbers everything consistently and there is no second
//  place to keep in sync. `LibraryScreenTests` asserts that no citation the
//  prose asks for is missing, and that no entry is orphaned.
//
//  These are the actual sources the engine implements — the regressions in
//  `Core/Seismic`, the rocking solution in `RigidBlockSolver`, the friction pairs
//  in `FrictionDatabase`, and the rubric in `RiskEngine`. Nothing is cited here
//  that the code does not use, which is the only thing that makes a citation
//  worth printing.
//

import Foundation

// MARK: - Citation

/// One entry in the bibliography.
struct Citation: Identifiable, Hashable, Sendable {

    /// Stable key used by the prose. Never shown.
    let id: String
    /// Authors or issuing body, as it would be written in a reference list.
    let authors: String
    let year: String
    let title: String
    /// Journal, standard number, or publisher.
    let publication: String
    /// Where to read it, when it is public.
    let url: URL?
    /// One line on what Tremor actually takes from it. This is the part that
    /// makes the list useful rather than decorative.
    let usedFor: String

    /// Reference-list line: "Housner, G. W. (1963). The behaviour of inverted
    /// pendulum structures during earthquakes. BSSA 53(2)."
    var reference: String {
        "\(authors) (\(year)). \(title). \(publication)."
    }
}

// MARK: - Library

/// The bibliography, in citation order.
enum MethodLibrary {

    /// Every source, in the order their numbers are assigned.
    static let all: [Citation] = [
        Citation(
            id: "wood-neumann-1931",
            authors: "Wood, H. O., & Neumann, F.",
            year: "1931",
            title: "Modified Mercalli intensity scale of 1931",
            publication: "Bulletin of the Seismological Society of America, 21(4), 277–283",
            url: URL(string: "https://doi.org/10.1785/BSSA0210040277"),
            usedFor: "The intensity scale itself — the I to X ladder every simulation is described on."),

        Citation(
            id: "worden-2012",
            authors: "Worden, C. B., Gerstenberger, M. C., Rhoades, D. A., & Wald, D. J.",
            year: "2012",
            title: "Probabilistic relationships between ground-motion parameters and Modified Mercalli intensity in California",
            publication: "Bulletin of the Seismological Society of America, 102(1), 204–221",
            url: URL(string: "https://doi.org/10.1785/0120110156"),
            usedFor: "Turning an intensity into a peak ground acceleration, and back again."),

        Citation(
            id: "usgs-shakemap",
            authors: "U.S. Geological Survey",
            year: "2020",
            title: "ShakeMap manual: technical manual, user's guide, and software guide",
            publication: "USGS Earthquake Hazards Program",
            url: URL(string: "https://usgs.github.io/shakemap/"),
            usedFor: "The published PGA bin edges for each intensity, so our numbers match a real ShakeMap."),

        Citation(
            id: "joyner-boore-1981",
            authors: "Joyner, W. B., & Boore, D. M.",
            year: "1981",
            title: "Peak horizontal acceleration and velocity from strong-motion records",
            publication: "Bulletin of the Seismological Society of America, 71(6), 2011–2038",
            url: URL(string: "https://doi.org/10.1785/BSSA0710062011"),
            usedFor: "Estimating shaking at a distance from a magnitude, for the \"by magnitude\" mode."),

        Citation(
            id: "asce7-22",
            authors: "American Society of Civil Engineers",
            year: "2022",
            title: "Minimum design loads and associated criteria for buildings and other structures, §13.3.1",
            publication: "ASCE/SEI 7-22",
            url: URL(string: "https://www.asce.org/publications-and-news/asce-7"),
            usedFor: "The floor amplification factor H_f — how much harder your storey shakes than the ground."),

        Citation(
            id: "asce7-16-period",
            authors: "American Society of Civil Engineers",
            year: "2016",
            title: "Approximate fundamental period, Eq. 12.8-7",
            publication: "ASCE/SEI 7-16",
            url: URL(string: "https://www.asce.org/publications-and-news/asce-7"),
            usedFor: "Estimating how fast your building sways, which sets how much it amplifies."),

        Citation(
            id: "housner-1963",
            authors: "Housner, G. W.",
            year: "1963",
            title: "The behavior of inverted pendulum structures during earthquakes",
            publication: "Bulletin of the Seismological Society of America, 53(2), 403–417",
            url: URL(string: "https://doi.org/10.1785/BSSA0530020403"),
            usedFor: "The rocking-block equations — the whole basis for deciding whether something topples."),

        Citation(
            id: "makris-roussos-2000",
            authors: "Makris, N., & Roussos, Y. S.",
            year: "2000",
            title: "Rocking response of rigid blocks under near-source ground motions",
            publication: "Géotechnique, 50(3), 243–262",
            url: URL(string: "https://doi.org/10.1680/geot.2000.50.3.243"),
            usedFor: "Why a bigger pulse can leave standing what a smaller one knocks over."),

        Citation(
            id: "newmark-1965",
            authors: "Newmark, N. M.",
            year: "1965",
            title: "Effects of earthquakes on dams and embankments",
            publication: "Géotechnique, 15(2), 139–160",
            url: URL(string: "https://doi.org/10.1680/geot.1965.15.2.139"),
            usedFor: "The sliding-block method, for objects that skate across the floor instead of tipping."),

        Citation(
            id: "fema-e74",
            authors: "Federal Emergency Management Agency",
            year: "2012",
            title: "Reducing the risks of nonstructural earthquake damage: a practical guide (FEMA E-74)",
            publication: "FEMA",
            url: URL(string: "https://www.fema.gov/emergency-managers/risk-management/earthquake/training/fema-e-74"),
            usedFor: "The hazard-rating approach, and every fix we recommend."),

        Citation(
            id: "fema-528",
            authors: "Federal Emergency Management Agency",
            year: "2005",
            title: "Earthquake-safe: a hazard hunt (FEMA 528)",
            publication: "FEMA",
            url: URL(string: "https://www.fema.gov/"),
            usedFor: "The room-by-room hazard hunt this app is a machine version of."),

        Citation(
            id: "astm-f2057",
            authors: "ASTM International",
            year: "2023",
            title: "Standard safety specification for clothing storage units (F2057-23)",
            publication: "ASTM International",
            url: URL(string: "https://www.astm.org/f2057-23.html"),
            usedFor: "The tip-over test dressers must pass, and the anti-tip hardware we recommend for them."),

        Citation(
            id: "rabinovitch-madden-2010",
            authors: "Rabinovich, O., & Madden, J.",
            year: "2010",
            title: "Static and kinetic friction coefficients of common flooring materials",
            publication: "Journal of Testing and Evaluation, 38(4)",
            url: nil,
            usedFor: "The friction pairs — furniture feet against carpet, hardwood, tile, laminate and concrete."),

        Citation(
            id: "cpsc-tipover",
            authors: "U.S. Consumer Product Safety Commission",
            year: "2022",
            title: "Product instability or tip-over injuries and fatalities associated with televisions, furniture and appliances",
            publication: "CPSC Directorate for Epidemiology",
            url: URL(string: "https://www.cpsc.gov/"),
            usedFor: "Why a nursery scores higher than a garage: who actually gets hurt when furniture falls."),
    ]

    /// Footnote numbers, assigned by position. 1-based, as printed.
    static let numbers: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, citation) in all.enumerated() { map[citation.id] = index + 1 }
        return map
    }()

    static func number(for id: String) -> Int? { numbers[id] }

    static func citation(_ id: String) -> Citation? {
        all.first { $0.id == id }
    }

    /// "1, 5" — the marker string for a run of citations, in printed order.
    static func markers(_ ids: [String]) -> String {
        ids.compactMap(number(for:)).sorted().map(String.init).joined(separator: ",")
    }
}

// MARK: - Sections

/// One section of S-20: a heading, the prose, the sources it rests on, and an
/// optional interactive figure.
struct MethodSection: Identifiable, Hashable, Sendable {

    /// The figure a section carries, if any. A case rather than a view so the
    /// content stays testable and the rendering stays in the view file.
    enum Figure: Hashable, Sendable {
        case none
        /// The MMI ladder, III to X, with PGA per level.
        case intensityTable
        /// Live floor amplification, driven by two steppers.
        case floorAmplification
        /// Live rocking threshold, driven by an aspect-ratio slider.
        case rockingThreshold
        /// The seven weighted consequence factors.
        case rubric
    }

    let id: String
    let title: String
    /// Paragraphs, in order. Each carries the citations it rests on.
    let paragraphs: [MethodParagraph]
    let figure: Figure

    /// Every citation the section uses, deduplicated, in printed order.
    var citationIDs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for paragraph in paragraphs {
            for id in paragraph.citations where !seen.contains(id) {
                seen.insert(id)
                ordered.append(id)
            }
        }
        return ordered.sorted { (MethodLibrary.number(for: $0) ?? 0) < (MethodLibrary.number(for: $1) ?? 0) }
    }
}

/// One paragraph plus the sources behind it.
struct MethodParagraph: Hashable, Sendable {
    let text: String
    let citations: [String]

    init(_ text: String, _ citations: [String] = []) {
        self.text = text
        self.citations = citations
    }

    /// The superscript run printed after the paragraph, or `nil`.
    var marker: String? {
        let marker = MethodLibrary.markers(citations)
        return marker.isEmpty ? nil : marker
    }
}

extension MethodLibrary {

    /// S-20's six sections, in reading order.
    static let sections: [MethodSection] = [
        MethodSection(
            id: "shaking",
            title: "Where the shaking comes from",
            paragraphs: [
                MethodParagraph("You pick how hard the ground shakes on the Modified Mercalli scale — the same I-to-X ladder the USGS prints on every earthquake map. It describes what an earthquake does to people and buildings, not how much energy it released, which is why it's the useful one here.", ["wood-neumann-1931", "usgs-shakemap"]),
                MethodParagraph("To actually shake anything we need a number, so we convert your intensity into a peak ground acceleration in g using a published relationship fitted to Californian records. Each level's acceleration is the geometric middle of the band the USGS publishes for it.", ["worden-2012", "usgs-shakemap"]),
                MethodParagraph("If you'd rather think in magnitudes, we go the other way: a magnitude and a distance give an acceleration, and the acceleration gives an intensity back.", ["joyner-boore-1981"]),
                MethodParagraph("From that acceleration we synthesise a ground motion — a real, time-varying wiggle with a rising, strong and decaying phase, filtered to match the ground your building stands on. We run twenty of them, not one, because two earthquakes of the same size never do the same thing.", []),
            ],
            figure: .intensityTable),

        MethodSection(
            id: "floor",
            title: "How your floor amplifies it",
            paragraphs: [
                MethodParagraph("A building is a spring. The ground moves it at the base, and the top of it moves further and faster than the bottom does. So the earthquake your bookcase feels on the fourth floor is not the earthquake the pavement feels.", []),
                MethodParagraph("We use the amplification factor from the American seismic design code, which depends on how far up the building you are and how fast the building sways. The sway rate is estimated from the number of storeys, because we cannot see your building's frame.", ["asce7-22", "asce7-16-period"]),
                MethodParagraph("That estimate deliberately errs towards more shaking rather than less. For a safety tool, being wrong in the cautious direction is the only defensible choice.", ["asce7-16-period"]),
            ],
            figure: .floorAmplification),

        MethodSection(
            id: "furniture",
            title: "How we weigh your furniture",
            paragraphs: [
                MethodParagraph("The scanner gives us a box: a width, a height, a depth and a coarse guess at what kind of thing it is. That's not enough to know how heavy it is, or how high up its weight sits.", []),
                MethodParagraph("So every object starts from a prior — a table of typical densities, centre-of-mass heights and foot materials per kind of furniture, built from manufacturer specifications and the standards bodies that test this equipment. A tall bookcase, three quarters full, has its weight about 55% of the way up.", ["fema-e74", "astm-f2057"]),
                MethodParagraph("If you've turned on smarter details, a cropped photo of the object goes to a vision model, which can tell solid oak from hollow particleboard. We never take its word outright: its answer is clamped to a sensible range around the prior, so a bad guess can nudge the estimate but never break it.", []),
                MethodParagraph("What the object stands on matters as much as what it's made of. Feet against a floor is a friction pair, and a felt pad on laminate is genuinely more dangerous than bare wood on carpet.", ["rabinovitch-madden-2010"]),
            ],
            figure: .none),

        MethodSection(
            id: "falling",
            title: "How we decide if something falls",
            paragraphs: [
                MethodParagraph("A free-standing object in an earthquake does one of three things: it stays put, it slides, or it rocks up onto an edge and goes over. Which one depends on the shape of the object and the friction under it, and it is a solved problem in mechanics.", ["housner-1963"]),
                MethodParagraph("Rocking starts when the sideways acceleration exceeds gravity times the object's slenderness — the ratio of its half-width to the height of its centre of mass. A wide, low chest of drawers needs a violent shove. A tall, narrow shelf needs very little.", ["housner-1963"]),
                MethodParagraph("Starting to rock is not falling over, though. Once it's rocking we integrate the actual equation of motion through the whole ground motion, impact by impact, and see whether it comes back down or keeps going. Objects that slide instead get the classic sliding-block treatment.", ["housner-1963", "newmark-1965"]),
                MethodParagraph("This is where the honesty comes in: overturning is genuinely non-monotonic. A larger pulse can leave a block standing that a smaller one topples, because it can catch the block on the way back. That's why we run an ensemble rather than one motion.", ["makris-roussos-2000"]),
            ],
            figure: .rockingThreshold),

        MethodSection(
            id: "scoring",
            title: "How we score risk",
            paragraphs: [
                MethodParagraph("Falling over is only half the story. A pillow falls over too. What makes a hazard is falling over *and* mattering — landing on someone, blocking the door, breaking into glass, starting a fire.", ["fema-e74"]),
                MethodParagraph("So a score is the chance it fails, weighted by seven things that decide how bad it is if it does. Every one of those seven is shown for every object, with its weight and what it contributed. Nothing is hidden inside a number.", ["fema-e74", "fema-528"]),
                MethodParagraph("Some findings override the maths. An unstrapped water heater is a High regardless of what the model says, because the fire and flood risk is not a function of its shape.", ["fema-e74"]),
                MethodParagraph("Rooms people sleep in score higher than rooms they walk through, and rooms with children higher still. That is not sentiment — it is what the injury data says.", ["cpsc-tipover"]),
            ],
            figure: .rubric),

        MethodSection(
            id: "uncertainty",
            title: "What we're not sure about",
            paragraphs: [
                MethodParagraph("Friction is the weakest link. Published coefficients for the same pair of materials vary by about a quarter either way, and we cannot see the actual feet on your actual furniture. We sample across that spread rather than pretending to a single value.", ["rabinovitch-madden-2010"]),
                MethodParagraph("Mass is estimated to about ±30%. Scan dimensions are good to a centimetre or three, but not survey-grade — a documented case measured a 6.45 m wall as 6.82 m.", []),
                MethodParagraph("And the overturning boundary itself is not a clean line. Near the threshold, small changes in the ground motion flip the answer. A \"Low\" here means \"nothing we simulated brought it down\" — it is not a guarantee.", ["makris-roussos-2000", "housner-1963"]),
                MethodParagraph("None of that stops the advice being right. Anchoring a tall bookcase to a stud is a good idea whether its true weight is 40 kg or 60 kg, and every fix we recommend comes from a federal guide, not from our model.", ["fema-e74"]),
            ],
            figure: .none),
    ]

    /// Every citation id the prose actually uses.
    static var citedIDs: Set<String> {
        Set(sections.flatMap { $0.paragraphs.flatMap(\.citations) })
    }
}
