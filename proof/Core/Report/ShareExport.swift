import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Payload

/// Everything an export carries: the scan, the verdict, and the report built
/// from them. Written as one envelope with its own schema version so a file
/// exported today can still be read after the model moves on.
///
/// This is the honest artefact behind "share my report": a PDF is what a human
/// reads, but the JSON is what another tool — or a future version of Tremor —
/// can actually re-derive the numbers from.
public struct AssessmentExport: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var room: ScannedRoom
    public var assessment: RoomAssessment
    public var report: SafetyReport

    public init(
        schemaVersion: Int = AssessmentExport.currentSchemaVersion,
        exportedAt: Date = Date(),
        room: ScannedRoom,
        assessment: RoomAssessment,
        report: SafetyReport
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.room = room
        self.assessment = assessment
        self.report = report
    }
}

// MARK: - Transferables

/// The rendered PDF, ready for `ShareLink`.
///
///     ShareLink(item: ShareExport.pdf(report), preview: .init(report.title))
public struct SafetyReportPDF: Transferable, Sendable, Hashable, Identifiable {
    public var data: Data
    /// Includes the `.pdf` extension.
    public var filename: String
    public var title: String

    public var id: String { filename }

    public init(data: Data, filename: String, title: String) {
        self.data = data
        self.filename = filename
        self.title = title
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

/// The raw assessment as JSON, for anyone who wants the numbers rather than the
/// prose — a structural engineer, a spreadsheet, or a later version of Tremor.
public struct AssessmentJSONExport: Transferable, Sendable, Hashable, Identifiable {
    public var data: Data
    /// Includes the `.json` extension.
    public var filename: String

    public var id: String { filename }

    public init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

/// The `.tremorroom` package itself — the whole scan, including the geometry and
/// any captured assets, as one shareable document.
public struct TremorRoomPackage: Transferable, Sendable, Hashable, Identifiable {
    /// The on-disk `.tremorroom` directory.
    public var url: URL
    public var filename: String

    public var id: String { url.path }

    public init(url: URL, filename: String? = nil) {
        self.url = url
        self.filename = filename ?? url.lastPathComponent
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: ShareExport.tremorRoomContentType) {
            SentTransferredFile($0.url)
        }
        .suggestedFileName { $0.filename }
    }
}

// MARK: - Factory

/// Builds the shareable wrappers. A small, boring namespace on purpose: the
/// interesting decisions are in `ReportBuilder` and `PDFRenderer`, and the share
/// layer should be the part nobody has to think about.
public enum ShareExport {

    /// The filename extension of a room package.
    public static let roomPackageExtension = "tremorroom"

    /// The content type of a `.tremorroom` package.
    ///
    /// Resolved from the declared document types when the app declares them, and
    /// falling back to a plain package otherwise. Deliberately *not* built with
    /// `UTType(exportedAs:)`: that requires an Info.plist declaration this file
    /// does not own, and getting it wrong is a runtime failure in the share
    /// sheet rather than a compile error.
    public static var tremorRoomContentType: UTType {
        UTType(filenameExtension: roomPackageExtension, conformingTo: .package) ?? .package
    }

    // MARK: PDF

    public static func pdf(
        _ report: SafetyReport, renderer: PDFRenderer = PDFRenderer()
    ) -> SafetyReportPDF {
        SafetyReportPDF(
            data: renderer.render(report),
            filename: "\(report.fileStem).pdf",
            title: report.title)
    }

    // MARK: JSON

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The raw assessment as pretty-printed, key-sorted JSON.
    public static func json(
        room: ScannedRoom, assessment: RoomAssessment, report: SafetyReport,
        exportedAt: Date = Date()
    ) throws -> AssessmentJSONExport {
        let payload = AssessmentExport(
            exportedAt: exportedAt, room: room, assessment: assessment, report: report)
        return AssessmentJSONExport(
            data: try encoder().encode(payload),
            filename: "\(report.fileStem).json")
    }

    /// Reads back what `json(room:assessment:report:)` wrote.
    public static func decode(_ data: Data) throws -> AssessmentExport {
        try decoder().decode(AssessmentExport.self, from: data)
    }

    // MARK: Room package

    public static func package(at url: URL, named name: String? = nil) -> TremorRoomPackage {
        TremorRoomPackage(url: url, filename: name)
    }

    // MARK: Files on disk

    /// Writes the PDF into a fresh temporary directory and returns its URL, for
    /// the share paths that need a file rather than bytes — AirDrop, "Save to
    /// Files", and the print sheet.
    ///
    /// A fresh subdirectory per export, because two reports for two rooms
    /// scanned on the same day produce the same filename, and silently
    /// overwriting one with the other is the kind of bug nobody notices until
    /// they send the wrong room to their landlord.
    @discardableResult
    public static func writePDFToTemporary(
        _ report: SafetyReport, renderer: PDFRenderer = PDFRenderer()
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TremorExports/\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("\(report.fileStem).pdf")
        return try renderer.write(report, to: url)
    }

    /// Writes the JSON export beside a temporary PDF, and returns both.
    public static func writeToTemporary(
        room: ScannedRoom, assessment: RoomAssessment, report: SafetyReport,
        renderer: PDFRenderer = PDFRenderer()
    ) throws -> (pdf: URL, json: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TremorExports/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pdfURL = directory.appendingPathComponent("\(report.fileStem).pdf")
        try renderer.render(report).write(to: pdfURL, options: .atomic)

        let jsonURL = directory.appendingPathComponent("\(report.fileStem).json")
        let export = try json(room: room, assessment: assessment, report: report)
        try export.data.write(to: jsonURL, options: .atomic)

        return (pdfURL, jsonURL)
    }
}
