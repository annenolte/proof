import Foundation

// MARK: - The document

/// A complete, self-contained safety report for one room at one shaking
/// intensity: everything a partner, a landlord or a contractor needs to act on,
/// with the reasoning and the error bars attached.
///
/// This is a *value*, not a view. `PDFRenderer` turns it into a document,
/// `ShareExport` turns it into something `ShareLink` can hand to Mail or
/// Messages, and the UI can render it directly. Nothing in here depends on
/// UIKit, SwiftUI or the design system.
public struct SafetyReport: Codable, Hashable, Sendable, Identifiable {

    public var id: UUID
    /// Who, what, where, when, and what was tested.
    public var header: Header
    /// The single-glance verdict.
    public var summary: Summary
    /// One entry per assessed object, ordered worst first.
    public var findings: [Finding]
    /// The ordered list of fixes, with time, cost and a shopping list.
    public var checklist: Checklist
    /// How the numbers were produced, what they are based on, and how far they
    /// can be trusted. Always present — a safety tool that hides its error bars
    /// is not trustworthy.
    public var methodology: Methodology

    public init(
        id: UUID = UUID(),
        header: Header,
        summary: Summary,
        findings: [Finding],
        checklist: Checklist,
        methodology: Methodology
    ) {
        self.id = id
        self.header = header
        self.summary = summary
        self.findings = findings
        self.checklist = checklist
        self.methodology = methodology
    }

    /// The document title, used for the PDF metadata and the share sheet.
    public var title: String {
        "\(header.roomName) — earthquake safety report"
    }

    /// A filename-safe stem, without an extension.
    public var fileStem: String {
        let name = header.roomName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = name.isEmpty ? "Room" : name
        return "proof \(stem) safety report \(ReportFormat.fileDate(header.generatedAt))"
    }
}

// MARK: - Header

extension SafetyReport {

    public struct Header: Codable, Hashable, Sendable {
        public var roomID: UUID
        public var roomName: String
        public var roomKind: RoomKind
        /// When the report was produced.
        public var generatedAt: Date
        /// When the room was scanned.
        public var scannedAt: Date
        /// When the scan was last edited.
        public var updatedAt: Date

        public var intensity: MercalliIntensity
        /// "Intensity VIII — severe shaking".
        public var intensityHeadline: String
        /// "Loma Prieta 1989, San Francisco".
        public var intensityReference: String
        /// What that intensity does to a building's contents.
        public var intensityContents: String

        public var building: BuildingContext
        /// "1st floor · Firm soil · Hardwood".
        public var buildingSummary: String
        public var groundAccelerationInG: Double
        public var floorAccelerationInG: Double
        public var floorAmplification: Double

        public var objectCount: Int
        public var movableObjectCount: Int
        public var floorAreaSquareMetres: Double
        /// The ensemble seed, so a reader can reproduce the run exactly.
        public var seed: UInt64
        public var ensembleSize: Int

        public init(
            roomID: UUID, roomName: String, roomKind: RoomKind,
            generatedAt: Date, scannedAt: Date, updatedAt: Date,
            intensity: MercalliIntensity, intensityHeadline: String,
            intensityReference: String, intensityContents: String,
            building: BuildingContext, buildingSummary: String,
            groundAccelerationInG: Double, floorAccelerationInG: Double,
            floorAmplification: Double, objectCount: Int,
            movableObjectCount: Int, floorAreaSquareMetres: Double,
            seed: UInt64, ensembleSize: Int
        ) {
            self.roomID = roomID
            self.roomName = roomName
            self.roomKind = roomKind
            self.generatedAt = generatedAt
            self.scannedAt = scannedAt
            self.updatedAt = updatedAt
            self.intensity = intensity
            self.intensityHeadline = intensityHeadline
            self.intensityReference = intensityReference
            self.intensityContents = intensityContents
            self.building = building
            self.buildingSummary = buildingSummary
            self.groundAccelerationInG = groundAccelerationInG
            self.floorAccelerationInG = floorAccelerationInG
            self.floorAmplification = floorAmplification
            self.objectCount = objectCount
            self.movableObjectCount = movableObjectCount
            self.floorAreaSquareMetres = floorAreaSquareMetres
            self.seed = seed
            self.ensembleSize = ensembleSize
        }

        /// "Bedroom · scanned 2 August 2026" — the room's own name absorbs the
        /// kind when the user has not renamed it, so the title does not read
        /// "Bedroom · Bedroom".
        public var identityLine: String {
            "\(roomDescription) · scanned \(ReportFormat.shortDate(scannedAt))"
        }

        public var roomDescription: String {
            roomName.caseInsensitiveCompare(roomKind.displayName) == .orderedSame
                ? roomName
                : "\(roomName) · \(roomKind.displayName)"
        }

        /// The facts table printed under the title.
        public var facts: [(label: String, value: String)] {
            [
                ("Room", roomDescription),
                ("Scanned", ReportFormat.longDate(scannedAt)),
                ("Report generated", ReportFormat.longDate(generatedAt)),
                ("Earthquake tested", intensityHeadline),
                ("Comparable event", intensityReference),
                ("Building", buildingSummary),
                ("Shaking at ground level", ReportFormat.g(groundAccelerationInG)),
                ("Shaking at this floor",
                 "\(ReportFormat.g(floorAccelerationInG)) (×\(ReportFormat.decimal(floorAmplification, places: 2)) for height)"),
                ("Objects assessed", "\(objectCount)"),
                ("Simulation runs per object", "\(ensembleSize)"),
                ("Run reference", String(format: "%016llX", seed)),
            ]
        }
    }
}

// MARK: - Summary

extension SafetyReport {

    public struct BandCount: Codable, Hashable, Sendable, Identifiable {
        public var band: RiskBand
        public var count: Int
        public var id: String { band.rawValue }

        public init(band: RiskBand, count: Int) {
            self.band = band
            self.count = count
        }
    }

    public struct Summary: Codable, Hashable, Sendable {
        /// 0…100, weighted towards the worst offenders.
        public var overallScore: Double
        public var overallBand: RiskBand
        /// One line: "Severe — 3 things in this room need securing".
        public var headline: String
        /// The one-sentence instruction that sits under the headline.
        public var action: String
        /// A short paragraph a non-specialist can act on.
        public var narrative: String
        /// Counts in worst-first order, including zero-count bands.
        public var bandCounts: [BandCount]
        public var objectsAssessed: Int
        public var objectsNeedingAction: Int
        /// The names of the worst offenders, worst first, capped at three.
        public var worstOffenders: [String]

        public init(
            overallScore: Double, overallBand: RiskBand, headline: String,
            action: String, narrative: String, bandCounts: [BandCount],
            objectsAssessed: Int, objectsNeedingAction: Int,
            worstOffenders: [String]
        ) {
            self.overallScore = overallScore
            self.overallBand = overallBand
            self.headline = headline
            self.action = action
            self.narrative = narrative
            self.bandCounts = bandCounts
            self.objectsAssessed = objectsAssessed
            self.objectsNeedingAction = objectsNeedingAction
            self.worstOffenders = worstOffenders
        }

        public func count(of band: RiskBand) -> Int {
            bandCounts.first { $0.band == band }?.count ?? 0
        }
    }
}

// MARK: - Fixes

extension SafetyReport {

    /// One recommended mitigation, straight from FEMA E-74 Chapter 6 plus
    /// FEMA 528, with the hardware named so it can be bought.
    ///
    /// **This is a projection of `Mitigation`, not a second catalogue.** The
    /// authoritative copy of every fix — its steps, hardware specifications,
    /// costs, times and FEMA reference — lives in `Core/Advice`'s
    /// `MitigationLibrary`. This type exists only because the report is a
    /// versioned document with its own flattened wire format: `Mitigation`
    /// carries `MitigationEffect` and re-scoring machinery that has no business
    /// in an exported PDF or JSON payload. Construct it with `init(_:)`.
    public struct Fix: Codable, Hashable, Sendable, Identifiable {
        /// The one difficulty scale in the app. Shared with `Core/Advice`.
        public typealias Difficulty = MitigationDifficulty
        /// The one hardware line-item type in the app. Shared with `Core/Advice`,
        /// which is where the "every part carries a real specification" test
        /// lives.
        public typealias Hardware = HardwareItem

        /// Stable catalogue identifier, e.g. `anchor-tall-furniture`.
        public var id: String
        public var title: String
        /// One line, imperative.
        public var summary: String
        /// The specification a contractor can work from.
        public var detail: String
        public var hardware: [Hardware]
        public var minutes: Int
        public var estimatedCostUSD: Double
        public var difficulty: Difficulty
        /// "FEMA E-74 §6.4.1".
        public var standardReference: String

        public init(
            id: String, title: String, summary: String, detail: String,
            hardware: [Hardware], minutes: Int, estimatedCostUSD: Double,
            difficulty: Difficulty, standardReference: String
        ) {
            self.id = id
            self.title = title
            self.summary = summary
            self.detail = detail
            self.hardware = hardware
            self.minutes = minutes
            self.estimatedCostUSD = estimatedCostUSD
            self.difficulty = difficulty
            self.standardReference = standardReference
        }

        /// "10 min · about $12 · basic tools".
        public var metaLine: String {
            var parts = [ReportFormat.duration(minutes)]
            if estimatedCostUSD > 0 {
                parts.append("about \(ReportFormat.money(estimatedCostUSD))")
                parts.append(difficulty.displayName.lowercased())
            } else {
                // "free · free" reads as a typo. One word carries both facts.
                parts.append(difficulty == .free ? "free, nothing to buy"
                                                 : "no cost · \(difficulty.displayName.lowercased())")
            }
            return parts.joined(separator: " · ")
        }

        /// Flattens a `MitigationLibrary` entry into the report's wire format.
        ///
        /// The cost collapses from a range to its midpoint because a PDF line
        /// item and a running total need one number; the range itself stays
        /// available on the `Mitigation` for the in-app plan, which shows it.
        public init(_ mitigation: Mitigation) {
            let steps = mitigation.steps.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            var detail = steps.isEmpty
                ? mitigation.summary
                : steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            if let warning = mitigation.warning, !warning.isEmpty {
                detail += "\n\n\(warning)"
            }
            self.init(
                id: mitigation.id,
                title: mitigation.title,
                summary: mitigation.summary,
                detail: detail,
                hardware: mitigation.hardware,
                minutes: mitigation.minutes,
                estimatedCostUSD: (mitigation.estimatedCostUSD.lowerBound
                                   + mitigation.estimatedCostUSD.upperBound) / 2,
                difficulty: mitigation.difficulty,
                standardReference: mitigation.femaReference)
        }
    }

    /// The ASCE 7-22 §13.3.1 anchorage demand for an object we are telling the
    /// user to bolt down. Printed so an installer can check their hardware
    /// instead of guessing.
    public struct Anchorage: Codable, Hashable, Sendable {
        /// Component operating weight, N.
        public var weightNewtons: Double
        /// Short-period design spectral acceleration assumed, g.
        public var designSpectralAcceleration: Double
        /// Height ratio z/h used in (1 + 2z/h).
        public var heightRatio: Double
        /// F_p, N.
        public var designForceNewtons: Double
        public var fixings: Int
        public var forcePerFixingNewtons: Double
        /// The plain-language verdict on hardware adequacy.
        public var note: String

        public init(
            weightNewtons: Double, designSpectralAcceleration: Double,
            heightRatio: Double, designForceNewtons: Double, fixings: Int,
            forcePerFixingNewtons: Double, note: String
        ) {
            self.weightNewtons = weightNewtons
            self.designSpectralAcceleration = designSpectralAcceleration
            self.heightRatio = heightRatio
            self.designForceNewtons = designForceNewtons
            self.fixings = fixings
            self.forcePerFixingNewtons = forcePerFixingNewtons
            self.note = note
        }

        public var summaryLine: String {
            "\(ReportFormat.force(designForceNewtons)) total, "
                + "\(ReportFormat.force(forcePerFixingNewtons)) per fixing across \(fixings)"
        }
    }
}

// MARK: - Findings

extension SafetyReport {

    /// The verdict on one object, with the reasoning that produced it. A finding
    /// is never emitted without at least one reason.
    public struct Finding: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID { objectID }
        public var objectID: UUID
        /// 1-based position in the severity ordering.
        public var rank: Int
        public var name: String
        public var type: ObjectType

        public var band: RiskBand
        /// 0…100.
        public var score: Double
        /// Probability of failure from the ensemble, 0…1.
        public var likelihood: Double
        /// "Topples onto the bed".
        public var headline: String
        public var behaviour: RigidBlockSolver.Behaviour
        /// Why it scored what it scored. Guaranteed non-empty.
        public var reasons: [String]
        /// What sits inside its strike zone.
        public var endangers: [String]
        /// Set when a code or standard forced the band up.
        public var regulatoryNote: String?

        public var massKg: Double
        public var extents: Extents
        public var mounting: Mounting
        public var loading: LoadingState
        public var topHeightMetres: Double
        public var slendernessRatio: Double
        public var identification: IdentificationProvenance

        /// Acceleration at which it starts to move, g.
        public var movementThresholdInG: Double
        /// Acceleration it was tested against, g.
        public var testedAccelerationInG: Double
        public var slidingDisplacementMetres: Double
        public var impactEnergyJoules: Double
        /// Peak rotation as a fraction of the toppling angle in the runs that
        /// survived, 0…1.
        public var closenessToToppling: Double
        /// Fraction of runs ending in each behaviour, worst first.
        public var behaviourDistribution: [String: Double]
        /// The consequence factors that actually drove the score, worst first.
        public var topContributors: [String]

        public var fixes: [Fix]
        public var anchorage: Anchorage?

        public init(
            objectID: UUID, rank: Int, name: String, type: ObjectType,
            band: RiskBand, score: Double, likelihood: Double, headline: String,
            behaviour: RigidBlockSolver.Behaviour, reasons: [String],
            endangers: [String], regulatoryNote: String?, massKg: Double,
            extents: Extents, mounting: Mounting, loading: LoadingState,
            topHeightMetres: Double, slendernessRatio: Double,
            identification: IdentificationProvenance,
            movementThresholdInG: Double, testedAccelerationInG: Double,
            slidingDisplacementMetres: Double, impactEnergyJoules: Double,
            closenessToToppling: Double, behaviourDistribution: [String: Double],
            topContributors: [String], fixes: [Fix], anchorage: Anchorage?
        ) {
            self.objectID = objectID
            self.rank = rank
            self.name = name
            self.type = type
            self.band = band
            self.score = score
            self.likelihood = likelihood
            self.headline = headline
            self.behaviour = behaviour
            self.reasons = reasons
            self.endangers = endangers
            self.regulatoryNote = regulatoryNote
            self.massKg = massKg
            self.extents = extents
            self.mounting = mounting
            self.loading = loading
            self.topHeightMetres = topHeightMetres
            self.slendernessRatio = slendernessRatio
            self.identification = identification
            self.movementThresholdInG = movementThresholdInG
            self.testedAccelerationInG = testedAccelerationInG
            self.slidingDisplacementMetres = slidingDisplacementMetres
            self.impactEnergyJoules = impactEnergyJoules
            self.closenessToToppling = closenessToToppling
            self.behaviourDistribution = behaviourDistribution
            self.topContributors = topContributors
            self.fixes = fixes
            self.anchorage = anchorage
        }

        /// "0.80 × 1.90 × 0.30 m · 152 kg · free-standing · packed".
        public var measurementsLine: String {
            var parts = [
                ReportFormat.dimensions(extents),
                ReportFormat.mass(massKg),
                mounting.displayName.lowercased(),
            ]
            if type.respondsToLoading { parts.append(loading.displayName.lowercased()) }
            return parts.joined(separator: " · ")
        }

        /// "Starts to move at 0.15 g · tested at 0.44 g · 45 kg landing at 210 J".
        public var physicsLine: String {
            var parts = [
                "moves at \(ReportFormat.g(movementThresholdInG))",
                "tested at \(ReportFormat.g(testedAccelerationInG))",
                "\(ReportFormat.percent(likelihood)) chance of failing",
            ]
            if impactEnergyJoules >= 1 {
                parts.append("\(ReportFormat.energy(impactEnergyJoules)) if it lands")
            }
            if slidingDisplacementMetres >= 0.02 {
                parts.append("slides \(ReportFormat.distance(slidingDisplacementMetres))")
            }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: - Checklist

extension SafetyReport {

    public struct Checklist: Codable, Hashable, Sendable {

        public struct Item: Codable, Hashable, Sendable, Identifiable {
            /// Stable across rebuilds: object identity plus fix identity.
            public var id: String
            public var objectID: UUID
            public var objectName: String
            public var band: RiskBand
            /// 1-based: the order the fixes should be done in.
            public var priority: Int
            public var fix: Fix
            public var isComplete: Bool

            public init(
                objectID: UUID, objectName: String, band: RiskBand,
                priority: Int, fix: Fix, isComplete: Bool = false
            ) {
                self.id = "\(objectID.uuidString)/\(fix.id)"
                self.objectID = objectID
                self.objectName = objectName
                self.band = band
                self.priority = priority
                self.fix = fix
                self.isComplete = isComplete
            }
        }

        /// The one aggregated shopping line in the app. Shared with
        /// `Core/Advice`, whose `FixItPlan` builds the same list for the in-app
        /// plan — two different merge rules for the same trip to the hardware
        /// store is exactly the kind of disagreement a user notices.
        public typealias ShoppingItem = HardwareLine

        public var items: [Item]
        public var shoppingList: [ShoppingItem]
        public var totalMinutes: Int
        public var totalCostUSD: Double

        public init(items: [Item], shoppingList: [ShoppingItem],
                    totalMinutes: Int, totalCostUSD: Double) {
            self.items = items
            self.shoppingList = shoppingList
            self.totalMinutes = totalMinutes
            self.totalCostUSD = totalCostUSD
        }

        public var isEmpty: Bool { items.isEmpty }

        /// "6 fixes · about $74 · 2 hours".
        public var summaryLine: String {
            guard !items.isEmpty else { return "No fixes needed" }
            let fixes = items.count == 1 ? "1 fix" : "\(items.count) fixes"
            let cost = totalCostUSD <= 0 ? "no cost" : "about \(ReportFormat.money(totalCostUSD))"
            return "\(fixes) · \(cost) · \(ReportFormat.duration(totalMinutes))"
        }
    }
}

// MARK: - Methodology

extension SafetyReport {

    public struct Methodology: Codable, Hashable, Sendable {

        public struct Section: Codable, Hashable, Sendable, Identifiable {
            public var title: String
            public var body: String
            public var id: String { title }

            public init(title: String, body: String) {
                self.title = title
                self.body = body
            }
        }

        public struct Citation: Codable, Hashable, Sendable, Identifiable {
            /// "Housner (1963)".
            public var shortForm: String
            /// The full reference.
            public var reference: String
            /// What it is used for in this report.
            public var usedFor: String
            public var id: String { shortForm }

            public init(shortForm: String, reference: String, usedFor: String) {
                self.shortForm = shortForm
                self.reference = reference
                self.usedFor = usedFor
            }
        }

        /// The one-paragraph description of how a score is produced.
        public var overview: String
        /// The pipeline, step by step.
        public var steps: [Section]
        /// The honest error bars. Never empty.
        public var uncertainties: [Section]
        /// What this report deliberately does not cover.
        public var limitations: [String]
        /// The standards and papers the numbers come from. Never empty.
        public var citations: [Citation]
        public var disclaimer: String

        public init(
            overview: String, steps: [Section], uncertainties: [Section],
            limitations: [String], citations: [Citation], disclaimer: String
        ) {
            self.overview = overview
            self.steps = steps
            self.uncertainties = uncertainties
            self.limitations = limitations
            self.citations = citations
            self.disclaimer = disclaimer
        }
    }
}

// MARK: - Builder

/// Turns a scan, an assessment and a mitigation checklist into a `SafetyReport`.
///
/// The builder owns three judgements that the risk engine deliberately does not
/// make: which fixes to recommend, in what order the user should do them, and
/// how much of the uncertainty to put in front of the reader. The engine
/// produces physics; this produces a document someone can act on.
public struct ReportBuilder {

    /// Bands at or above this appear in the fix-it checklist. Moderate is
    /// included on purpose: "worth securing" items are cheap and are where most
    /// of the achievable risk reduction actually lives.
    public var checklistThreshold: RiskBand
    /// Ensemble size quoted in the header, for reproducibility.
    public var ensembleSize: Int

    public init(checklistThreshold: RiskBand = .moderate, ensembleSize: Int = 20) {
        self.checklistThreshold = checklistThreshold
        self.ensembleSize = ensembleSize
    }

    // MARK: Build

    /// Builds the report.
    ///
    /// - Parameters:
    ///   - room: the scan the assessment was computed from.
    ///   - assessment: the verdict from `RiskEngine.assess`.
    ///   - checklist: the user's own fix-it plan, if they have one — this is
    ///     what carries their completion ticks. When `nil`, a checklist is
    ///     derived from the findings. Findings always carry the full set of
    ///     *recommended* fixes either way: what you should do and what you have
    ///     chosen to do are different lists, and conflating them would let a
    ///     half-built plan hide a hazard.
    ///   - generatedAt: report timestamp; injected so tests are deterministic.
    public func build(
        room: ScannedRoom,
        assessment: RoomAssessment,
        checklist: SafetyReport.Checklist? = nil,
        generatedAt: Date = Date()
    ) -> SafetyReport {

        let findings = self.findings(room: room, assessment: assessment)

        return SafetyReport(
            header: header(room: room, assessment: assessment, generatedAt: generatedAt),
            summary: summary(assessment: assessment, findings: findings),
            findings: findings,
            checklist: checklist ?? Self.checklist(from: findings, threshold: checklistThreshold),
            methodology: methodology(room: room, assessment: assessment)
        )
    }

    // MARK: Header

    private func header(
        room: ScannedRoom, assessment: RoomAssessment, generatedAt: Date
    ) -> SafetyReport.Header {
        let intensity = assessment.intensity
        return SafetyReport.Header(
            roomID: room.id,
            roomName: room.name.isEmpty ? room.kind.displayName : room.name,
            roomKind: room.kind,
            generatedAt: generatedAt,
            scannedAt: room.createdAt,
            updatedAt: room.updatedAt,
            intensity: intensity,
            intensityHeadline: "Intensity \(intensity.roman) — \(intensity.shakingLabel.lowercased()) shaking",
            intensityReference: intensity.reference,
            intensityContents: intensity.contentsDescription,
            building: room.building,
            buildingSummary: room.building.summary,
            groundAccelerationInG: assessment.groundAccelerationInG,
            floorAccelerationInG: assessment.floorAccelerationInG,
            floorAmplification: room.building.floorAmplification,
            objectCount: room.objects.count,
            movableObjectCount: room.movableObjects.count,
            floorAreaSquareMetres: room.floorArea,
            seed: assessment.seed,
            ensembleSize: ensembleSize
        )
    }

    // MARK: Summary

    private func summary(
        assessment: RoomAssessment, findings: [SafetyReport.Finding]
    ) -> SafetyReport.Summary {
        let band = assessment.overallBand
        let score = assessment.overallScore
        let needingAction = findings.filter { $0.band >= .high }.count
        let worst = findings.prefix(3).map(\.name)

        let headline: String
        let narrative: String

        if findings.isEmpty {
            headline = "Nothing to assess"
            narrative = """
                This scan contains no objects, so there is nothing to score. \
                Re-scan the room and make sure the furniture is in frame — Tremor \
                can only judge what it can see.
                """
        } else if needingAction == 0 {
            headline = "\(band.displayName) — nothing here needs anchoring"
            narrative = """
                Nothing in this room is likely to fall on someone at intensity \
                \(assessment.intensity.roman). \(findings.count == 1 ? "The one object" : "All \(findings.count) objects") \
                assessed came back at \(band.displayName.lowercased()) risk or below. \
                Items marked "worth securing" are cheap wins rather than urgent work.
                """
        } else {
            let subject = needingAction == 1 ? "one thing" : "\(needingAction) things"
            headline = "\(band.displayName) — \(subject) in this room \(needingAction == 1 ? "needs" : "need") securing"
            narrative = """
                At intensity \(assessment.intensity.roman) \
                (\(ReportFormat.g(assessment.floorAccelerationInG)) at this floor), \
                \(subject) in this room \(needingAction == 1 ? "is" : "are") likely to fall, \
                and likely to hurt someone or block the way out. \
                The worst \(needingAction == 1 ? "is" : "are") \(ReportFormat.list(worst)). \
                Everything needed to fix \(needingAction == 1 ? "it" : "them") is listed in the fix-it plan below.
                """
        }

        let counts = RiskBand.allCases.reversed().map { band in
            SafetyReport.BandCount(band: band, count: findings.filter { $0.band == band }.count)
        }

        // Deliberately not `RiskBand.detail`: that sentence is written about a
        // single object ("secure it before you sleep in this room again") and
        // reads as nonsense when it is applied to a whole room.
        let action: String
        switch (findings.isEmpty, band) {
        case (true, _):
            action = "There is nothing in this scan to assess."
        case (_, .low):
            action = "Nothing in this room needs securing. Keep it that way when the furniture moves."
        case (_, .moderate):
            action = "Nothing here is likely to fall on someone, but a few cheap fixes are worth doing."
        case (_, .high):
            action = "The items flagged below need anchoring. Start at the top of the fix-it plan."
        case (_, .severe):
            action = "The items flagged below are life-safety items. Start at the top of the fix-it plan."
        }

        return SafetyReport.Summary(
            overallScore: score,
            overallBand: band,
            headline: headline,
            action: action,
            narrative: narrative,
            bandCounts: counts,
            objectsAssessed: findings.count,
            objectsNeedingAction: needingAction,
            worstOffenders: Array(worst)
        )
    }

    // MARK: Findings

    private func findings(
        room: ScannedRoom, assessment: RoomAssessment
    ) -> [SafetyReport.Finding] {

        // Worst first. Ties break on mass and then on identity, so the ordering
        // is stable across runs and across machines — a report that reshuffles
        // itself between exports is not a document.
        let ordered = assessment.objectRisks
            .compactMap { risk -> (ObjectRisk, ScannedObject)? in
                guard let object = room.object(id: risk.objectID) else { return nil }
                return (risk, object)
            }
            .sorted { a, b in
                if a.0.score != b.0.score { return a.0.score > b.0.score }
                if a.1.mass != b.1.mass { return a.1.mass > b.1.mass }
                return a.1.id.uuidString < b.1.id.uuidString
            }

        return ordered.enumerated().map { index, pair in
            finding(rank: index + 1, risk: pair.0, object: pair.1, room: room,
                    assessment: assessment)
        }
    }

    private func finding(
        rank: Int, risk: ObjectRisk, object: ScannedObject, room: ScannedRoom,
        assessment: RoomAssessment
    ) -> SafetyReport.Finding {

        let fixes = Self.recommendedFixes(for: object, risk: risk, in: room)

        // A finding without a reason is unusable — the reader cannot check it,
        // argue with it or act on it. The engine always supplies at least one,
        // but the guarantee belongs here, where the document is assembled.
        var reasons = risk.reasons.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if reasons.isEmpty {
            reasons.append(Self.fallbackReason(object: object, risk: risk))
        }
        if let override = risk.overrideReason, !reasons.contains(override) {
            reasons.append(override)
        }

        let contributors = risk.consequence.rankedContributions.prefix(3).map { entry -> String in
            let share = entry.contribution / max(risk.consequence.total, 0.001)
            return "\(entry.label) (\(Int((share * 100).rounded()))% of the consequence)"
        }

        return SafetyReport.Finding(
            objectID: object.id,
            rank: rank,
            name: object.type.displayName,
            type: object.type,
            band: risk.band,
            score: risk.score,
            likelihood: risk.likelihood,
            headline: Self.headline(risk: risk, object: object),
            behaviour: risk.dominantBehaviour,
            reasons: reasons,
            endangers: risk.endangers,
            regulatoryNote: risk.overrideReason,
            massKg: object.mass,
            extents: object.extents,
            mounting: object.mounting,
            loading: object.loading,
            topHeightMetres: object.topHeight,
            slendernessRatio: object.slenderness,
            identification: object.provenance,
            movementThresholdInG: risk.movementThresholdInG,
            testedAccelerationInG: risk.testedAccelerationInG,
            slidingDisplacementMetres: risk.slidingDisplacement,
            impactEnergyJoules: risk.impactEnergy,
            closenessToToppling: risk.closenessToToppling,
            behaviourDistribution: risk.behaviourDistribution,
            topContributors: Array(contributors),
            fixes: fixes,
            anchorage: Self.anchorage(
                for: object, in: room, fixes: fixes,
                groundPGAInG: assessment.groundAccelerationInG)
        )
    }

    private static func fallbackReason(object: ScannedObject, risk: ObjectRisk) -> String {
        if !object.canMove {
            return "It's anchored, so it stays where it is."
        }
        return String(
            format: "It starts to move at %.2fg and this quake reaches %.2fg at floor level.",
            risk.movementThresholdInG, risk.testedAccelerationInG)
    }

    /// The one-line verdict shown next to the object's name.
    static func headline(risk: ObjectRisk, object: ScannedObject) -> String {
        let target = risk.endangers.first.map { " onto the \($0.lowercased())" } ?? ""
        switch risk.dominantBehaviour {
        case .overturned:
            return object.mounting == .leaning ? "Slides out and falls\(target)" : "Topples over\(target)"
        case .fellOffSupport:
            return object.mounting == .wallMounted
                ? "Comes off the wall\(target)"
                : "Falls off what it's standing on\(target)"
        case .rocked:
            return "Rocks hard but stays up"
        case .slid:
            return "Slides across the floor"
        case .restrained:
            return "Held in place"
        case .stable:
            return "Stays put"
        }
    }

    // MARK: Anchorage sizing

    /// The fixes that put a fastener into structure, and therefore need a sized
    /// demand printed next to them. Derived from the catalogue rather than
    /// listed by hand, so a new anchoring mitigation cannot be added in
    /// `Core/Advice` and silently lose its anchorage figure in the report.
    static let anchoringFixIDs: Set<String> = Set(
        MitigationLibrary.all.filter { $0.effect.setsAnchored }.map(\.id))

    /// ASCE 7-22 §13.3.1 Eq. 13.3-1, used only where we are telling the user to
    /// bolt something down. This is the one place `R_p` legitimately appears —
    /// sizing hardware, not simulating motion.
    static func anchorage(
        for object: ScannedObject, in room: ScannedRoom,
        fixes: [SafetyReport.Fix], groundPGAInG: Double
    ) -> SafetyReport.Anchorage? {
        guard fixes.contains(where: { Self.anchoringFixIDs.contains($0.id) }) else { return nil }

        // S_DS ≈ 2.5 × PGA is the standard short-period plateau relationship;
        // it is stated in the methodology rather than buried here. It is the
        // *only* thing this function decides — the sizing itself, the height
        // ratio, the code bounds and the fixing count all come from
        // `AnchorageCalculator`, which is the one place `R_p` is allowed to
        // appear and the one place that decides how many fixings a piece gets.
        // A second copy of Eq. 13.3-1 here would have printed a different
        // number in the PDF than the in-app plan shows for the same object.
        let sds = min(max(2.5 * groundPGAInG, 0.1), 2.0)
        let requirement = AnchorageCalculator.requirement(for: object, in: room, sds: sds)

        let each = requirement.forcePerFixingNewtons
        let fixings = requirement.fixingCount
        let lag = FixingType.lagScrewIntoStud.capacityNewtons

        let note: String
        if each <= lag * 0.5 {
            note = """
                A ¼″ × 2½″ lag screw driven into a stud carries about 2.7 kN in \
                withdrawal, so \(fixings) of them are comfortably adequate. A drywall \
                toggle carries 0.2–0.35 kN and is not.
                """
        } else if each <= lag {
            note = """
                A ¼″ × 2½″ lag screw into a stud carries about 2.7 kN in withdrawal, \
                so this is close to the capacity of \(fixings) fixings. Use \(fixings + 2) \
                fixings, or larger lags, and hit studs — drywall anchors are not an option here.
                """
        } else {
            note = """
                This demand exceeds what ¼″ lags into wood studs can be relied on for. \
                Have the anchorage specified by a contractor: through-bolting, larger \
                lags or a structural bracket.
                """
        }

        return SafetyReport.Anchorage(
            weightNewtons: requirement.weightNewtons,
            designSpectralAcceleration: requirement.sds,
            heightRatio: requirement.heightRatio,
            designForceNewtons: requirement.designForceNewtons,
            fixings: fixings,
            forcePerFixingNewtons: each,
            note: note
        )
    }

    // MARK: Checklist

    /// Derives the fix-it plan from the findings: every recommended fix for
    /// every object at or above the threshold band, ordered by severity.
    public static func checklist(
        from findings: [SafetyReport.Finding], threshold: RiskBand = .moderate
    ) -> SafetyReport.Checklist {

        var items: [SafetyReport.Checklist.Item] = []
        for finding in findings where finding.band >= threshold {
            for fix in finding.fixes {
                items.append(SafetyReport.Checklist.Item(
                    objectID: finding.objectID,
                    objectName: finding.name,
                    band: finding.band,
                    priority: items.count + 1,
                    fix: fix
                ))
            }
        }
        // Re-number after collection so priority is contiguous.
        items = items.enumerated().map { index, item in
            var copy = item
            copy.priority = index + 1
            return copy
        }

        // Aggregate the hardware. Identical items across objects merge, which is
        // the difference between a shopping list and a pile of receipts.
        var byName: [String: SafetyReport.Checklist.ShoppingItem] = [:]
        var order: [String] = []
        for item in items {
            for hardware in item.fix.hardware {
                if var existing = byName[hardware.name] {
                    existing.quantity += hardware.quantity
                    existing.approxCostUSD += hardware.totalCostUSD
                    byName[hardware.name] = existing
                } else {
                    byName[hardware.name] = .init(
                        id: hardware.id,
                        name: hardware.name,
                        specification: hardware.specification,
                        quantity: hardware.quantity,
                        approxCostUSD: hardware.totalCostUSD)
                    order.append(hardware.name)
                }
            }
        }

        return SafetyReport.Checklist(
            items: items,
            shoppingList: order.compactMap { byName[$0] },
            totalMinutes: items.reduce(0) { $0 + $1.fix.minutes },
            totalCostUSD: items.reduce(0) { $0 + $1.fix.estimatedCostUSD }
        )
    }

    // MARK: Fix selection

    /// The fixes we recommend for one object, worst-first, capped at three so
    /// the reader acts instead of reading.
    ///
    /// The *selection* is `MitigationLibrary.advice(for:risk:in:)` — the same
    /// call the in-app fix-it plan makes, so the PDF and the screen can never
    /// recommend different work for the same object. What stays here are the
    /// two judgements that belong to the document rather than to the domain:
    ///
    /// * an object that cannot move is not sold hardware — the report's job for
    ///   an already-anchored piece is to say "check the fixing", which it does
    ///   in the finding's reasoning, not in a shopping list;
    /// * below `.moderate` we print nothing, because recommending brackets for
    ///   a coffee table is how a safety tool loses the reader.
    public static func recommendedFixes(
        for object: ScannedObject, risk: ObjectRisk, in room: ScannedRoom
    ) -> [SafetyReport.Fix] {

        // Already bolted down. The only honest advice is to check the fixing.
        guard object.canMove else { return [] }
        // Nothing that never moves needs hardware.
        guard risk.band >= .moderate else { return [] }

        return MitigationLibrary.advice(for: object, risk: risk, in: room)
            .prefix(Checklist.maximumFixesPerObject)
            .map(SafetyReport.Fix.init)
    }

    // MARK: Methodology

    /// The appendix. Always present, always cites what was actually used, and
    /// always states the error bars — including the one that is genuinely
    /// uncomfortable, which is that overturning is not monotonic near threshold.
    public func methodology(
        room: ScannedRoom, assessment: RoomAssessment
    ) -> SafetyReport.Methodology {

        let overview = """
            Tremor scans the room with the phone's LiDAR sensor, identifies each object, \
            estimates its mass and centre of gravity from its size and kind, then shakes \
            it with synthetic earthquake ground motion and integrates the equations of \
            motion for a rigid block that can rock and slide. Every object is run \
            \(ensembleSize) times with different friction \
            draws and different ground-motion realisations, and the verdict is the \
            fraction of those runs in which it failed, multiplied by how bad that failure \
            would be. The band is the answer; the number is a way of ordering the band.
            """

        let steps: [SafetyReport.Methodology.Section] = [
            .init(title: "1 · Geometry", body: """
                RoomPlan returns each object as a gravity-aligned box in metres, together \
                with the walls, doors and windows. Tremor keeps that convention untouched, \
                so what is simulated is exactly what was measured.
                """),
            .init(title: "2 · Mass and centre of gravity", body: """
                Mass comes from the object's bounding-box volume times an effective density \
                prior for its kind — a wardrobe is mostly air, so its effective density is a \
                tenth of the board it is made from — then clamped to the plausible mass range \
                for that kind. Centre-of-gravity height is a fraction of the object's height, \
                raised when something heavy is stacked on top. Priors are compiled from \
                manufacturer specification sheets, ASHRAE equipment weights and FEMA E-74 \
                Chapter 6.
                """),
            .init(title: "3 · Ground motion", body: """
                The shaking is a synthetic accelerogram: filtered Gaussian noise passed \
                through a Kanai–Tajimi ground filter tuned to the soil class, shaped by a \
                Jennings envelope and scaled to the target peak ground acceleration for the \
                chosen Modified Mercalli intensity. The intensity-to-acceleration conversion \
                is Worden et al. (2012). Motion is amplified from the ground to this floor by \
                ASCE 7-22 §13.3.1's (1 + 2z/h) height factor — here a factor of \
                \(ReportFormat.decimal(room.building.floorAmplification, places: 2)).
                """),
            .init(title: "4 · Rocking and sliding", body: """
                Each object is integrated as a rigid block on a rigid floor following Housner's \
                inverted-pendulum formulation, with Housner's energy-conserving impact rule at \
                each corner strike and a Coulomb friction law for sliding. The branch between \
                rocking and sliding is decided by comparing the friction coefficient with the \
                block's base-to-height ratio. Objects that are wall-mounted or leaning are not \
                blocks and are not treated as such: a wall-mounted object is assessed on its \
                fixing's withdrawal capacity, a leaning one on its base sliding out.
                """),
            .init(title: "5 · Consequence", body: """
                How bad a failure would be is scored from seven weighted factors: impact \
                energy at the moment it lands, who is in the strike zone and whether they can \
                react, how far it falls, whether it blocks the way out, broken glass, sheer \
                mass, and secondary hazards such as gas or water. The impact-energy scale is \
                anchored at 50 J, the industrial helmet impact limit (EN 397 tests at 49 J). \
                Room type weights the result: a bedroom or nursery scores higher than a garage, \
                because a sleeping occupant cannot move out of the way.
                """),
            .init(title: "6 · Codes and overrides", body: """
                A small number of items are raised to at least "high" regardless of what the \
                physics returns, because a code or a documented loss history says so: \
                unstrapped water heaters (California Health & Safety Code §19211, IRC P2801.8), \
                gas ranges without an anti-tip bracket and a flexible connector, large leaning \
                mirrors, and anything heavy mounted or stacked above a bed or a crib. \
                Mitigation details are taken from FEMA E-74 Chapter 6 and FEMA 528.
                """),
        ]

        let uncertainties: [SafetyReport.Methodology.Section] = [
            .init(title: "Friction is known to about ±25%", body: """
                Published static friction coefficients for the same pair of materials vary by \
                a quarter or more between sources, and real floors are dusty, waxed and worn. \
                Tremor does not pick one value: it samples friction across that spread on every \
                run, so the reported probability of failure already contains the friction \
                uncertainty rather than hiding it. Where an object sits close to the boundary \
                between sliding and tipping, that spread is the difference between two \
                completely different behaviours — which is exactly why the answer is a \
                probability and not a verdict.
                """),
            .init(title: "Mass is estimated to about ±30%", body: """
                Nothing was weighed. Mass is inferred from size, kind and how full the object \
                appears, and a loaded bookcase can weigh three times an empty one of the same \
                size. Correcting an object's contents in the app is the single highest-value \
                thing you can do to sharpen this report. Mass matters less for whether an \
                object tips — that is governed by shape — and more for how much damage it does \
                when it lands.
                """),
            .init(title: "Overturning is genuinely unpredictable near the threshold", body: """
                This is the most important caveat in this report. A rocking block's response is \
                non-monotonic in the strength of the shaking: an object can survive a stronger \
                pulse than one that knocks it over, because whether it topples depends on the \
                phasing of the shaking against its own rocking, not only on the amplitude \
                (Makris & Roussos, 2000). For an object sitting near its threshold, a 10% \
                change in the input can flip the outcome, and no amount of extra computation \
                removes that. It is why Tremor reports an ensemble rather than a single \
                simulation, why the band matters more than the score, and why an object \
                reported as "came close" should be treated as one that fell.
                """),
            .init(title: "The scan itself has error", body: """
                LiDAR room capture is accurate to a few centimetres on dimensions, but it \
                mistakes one kind of storage for another, misses small objects, and cannot see \
                inside anything. Objects marked as uncertain in the findings below were guessed \
                rather than recognised; correcting them changes the result.
                """),
        ]

        let limitations = [
            "This is an assessment of the room's contents, not of the building. It says nothing about whether the structure itself is safe.",
            "Objects are simulated one at a time on a rigid floor. Furniture colliding with other furniture, walls flexing, and floors failing are not modelled.",
            "Existing anchors are only counted when they were marked in the app. proof cannot see a bracket behind a bookcase.",
            "One intensity was tested. A different earthquake will produce a different result; run the room again at a higher intensity to see how much margin there is.",
            "Contents are inferred, not observed. What is inside a cabinet changes both its mass and what comes out of it first.",
        ]

        let citations: [SafetyReport.Methodology.Citation] = [
            .init(
                shortForm: "Housner (1963)",
                reference: "Housner, G. W. \"The behavior of inverted pendulum structures during earthquakes.\" Bulletin of the Seismological Society of America 53(2), 403–417.",
                usedFor: "The rocking-block equations of motion and the impact energy-loss rule used for every free-standing object."),
            .init(
                shortForm: "Makris & Roussos (2000)",
                reference: "Makris, N. & Roussos, Y. \"Rocking response of rigid blocks under near-source ground motions.\" Géotechnique 50(3), 243–262.",
                usedFor: "The non-monotonic overturning behaviour that makes an ensemble, rather than a single run, the only honest way to report a result."),
            .init(
                shortForm: "Worden et al. (2012)",
                reference: "Worden, C. B., Gerstenberger, M. C., Rhoades, D. A. & Wald, D. J. \"Probabilistic relationships between ground-motion parameters and Modified Mercalli intensity in California.\" Bulletin of the Seismological Society of America 102(1), 204–221.",
                usedFor: "Converting the chosen Modified Mercalli intensity into the peak ground acceleration and velocity the simulation is scaled to."),
            .init(
                shortForm: "ASCE/SEI 7-22 §13.3.1",
                reference: "ASCE/SEI 7-22, Minimum Design Loads and Associated Criteria for Buildings and Other Structures, Chapter 13 (Seismic Design Requirements for Nonstructural Components), Eq. 13.3-1.",
                usedFor: "Amplifying ground motion to this floor by (1 + 2z/h), and sizing the anchorage forces quoted with each fix. Fp uses ap = 1.0, Rp = 1.5, Ip = 1.0, with Sds taken as 2.5 × the peak ground acceleration."),
            .init(
                shortForm: "FEMA E-74 (2012)",
                reference: "FEMA E-74, Reducing the Risks of Nonstructural Earthquake Damage — A Practical Guide, 4th edition, FEMA/Applied Technology Council.",
                usedFor: "Every mitigation detail in the fix-it plan, and the qualitative life-safety/property-loss/functional-loss framing the consequence score preserves."),
            .init(
                shortForm: "FEMA 528 (2005)",
                reference: "FEMA 528, Earthquake Safety Guide for Homeowners.",
                usedFor: "Householder-level fixes: strapping, latching, and where not to put heavy objects."),
            .init(
                shortForm: "ASTM F2057-23",
                reference: "ASTM F2057-23, Standard Safety Specification for Clothing Storage Units.",
                usedFor: "The anti-tip requirement applied to dressers and chests of drawers, and the child-occupancy weighting."),
        ]

        let disclaimer = """
            This report is an engineering estimate produced from a phone scan. It is not a \
            professional structural or seismic engineering assessment, it is not an \
            inspection, and it does not certify anything. The physics is standard and the \
            sources are cited above, but the inputs are inferred rather than measured, and \
            earthquake response near a stability threshold is inherently uncertain. Use it to \
            decide what to secure first — not as a guarantee that anything is safe. If an item \
            matters to you, have it looked at by a qualified contractor or engineer.
            """

        return SafetyReport.Methodology(
            overview: overview, steps: steps, uncertainties: uncertainties,
            limitations: limitations, citations: citations, disclaimer: disclaimer)
    }
}

// MARK: - The fix catalogue
//
// There is no catalogue here. It used to hold sixteen `SafetyReport.Fix`
// statics that duplicated — by the same identifiers, with different titles,
// different hardware, different costs and different times — the thirty-two
// entries in `Core/Advice/MitigationAdvice.swift`. `MitigationLibrary` is the
// single source of truth; `SafetyReport.Fix.init(_ mitigation:)` projects it
// into the report wire format.

// MARK: - Bridging the in-app plan into the document

extension SafetyReport.Checklist {

    /// Renders the user's real fix-it plan — including which boxes they have
    /// already ticked — into the report's flattened checklist.
    ///
    /// `ReportBuilder.build(checklist:)` synthesises a checklist from the
    /// findings when it is given none; that fallback is for a report generated
    /// straight off an assessment. Once the app has a `FixItPlan`, this is how
    /// it goes into the PDF, so the printed list is the list the user is
    /// working from rather than a parallel one.
    public init(_ plan: FixItPlan, completed: Set<String> = []) {
        let items = plan.items.enumerated().map { index, item in
            Item(
                objectID: item.objectID,
                objectName: item.objectName,
                band: item.currentBand,
                priority: index + 1,
                fix: SafetyReport.Fix(item.mitigation),
                isComplete: completed.contains(item.id))
        }
        // The trips already carry the merged hardware, and merging them again
        // here is how the two lists would drift apart.
        var byName: [String: ShoppingItem] = [:]
        var order: [String] = []
        for line in plan.trips.flatMap(\.hardware) {
            if var existing = byName[line.name] {
                existing.quantity += line.quantity
                existing.approxCostUSD += line.approxCostUSD
                byName[line.name] = existing
            } else {
                byName[line.name] = line
                order.append(line.name)
            }
        }
        self.init(
            items: items,
            shoppingList: order.compactMap { byName[$0] },
            totalMinutes: plan.totalMinutes,
            totalCostUSD: (plan.estimatedCostUSD.lowerBound
                           + plan.estimatedCostUSD.upperBound) / 2)
    }
}

// MARK: - Formatting

/// Number and date formatting for the report and its PDF. Kept here so the
/// document and the renderer cannot disagree about how a mass is written.
public enum ReportFormat {

    public static func decimal(_ value: Double, places: Int = 1) -> String {
        String(format: "%.\(places)f", value)
    }

    public static func g(_ value: Double) -> String {
        String(format: "%.2f g", value)
    }

    public static func mass(_ kg: Double) -> String {
        kg < 10 ? String(format: "%.1f kg", kg) : "\(Int(kg.rounded())) kg"
    }

    public static func distance(_ metres: Double) -> String {
        metres < 1 ? "\(Int((metres * 100).rounded())) cm" : String(format: "%.2f m", metres)
    }

    public static func energy(_ joules: Double) -> String {
        joules >= 1000 ? String(format: "%.1f kJ", joules / 1000) : "\(Int(joules.rounded())) J"
    }

    public static func force(_ newtons: Double) -> String {
        newtons >= 1000 ? String(format: "%.2f kN", newtons / 1000) : "\(Int(newtons.rounded())) N"
    }

    public static func money(_ usd: Double) -> String {
        usd >= 100 ? "$\(Int(usd.rounded()))" : "$\(Int(usd.rounded()))"
    }

    public static func duration(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: return "\(minutes) min"
        case 60: return "1 hour"
        default:
            let hours = Double(minutes) / 60
            return hours == hours.rounded()
                ? "\(Int(hours)) hours"
                : String(format: "%.1f hours", hours)
        }
    }

    public static func dimensions(_ extents: Extents) -> String {
        String(format: "%.2f × %.2f × %.2f m", extents.width, extents.height, extents.depth)
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// "a, b and c".
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    public static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// yyyy-MM-dd, locale-independent, for filenames.
    public static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
