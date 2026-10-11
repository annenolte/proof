import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Renders a `SafetyReport` to a real, multi-page, vector PDF.
///
/// Core Text rather than `ImageRenderer`: a report is a *document*, and a
/// contractor or a landlord will print it. `ImageRenderer` rasterises, so the
/// text stops being selectable, stops being searchable, and goes soft at print
/// resolution. Core Text also gives the one thing a report actually needs and a
/// SwiftUI snapshot cannot express — line-accurate pagination, so a paragraph
/// splits across a page boundary instead of being clipped or pushed whole onto
/// the next page.
///
/// Nothing here touches `Tremor/DesignSystem`. The styling is deliberately
/// self-contained, because a PDF has different constraints from a screen (paper
/// white, hairlines, print-safe colours) and because the export layer must keep
/// working while the design system is in flight.
public struct PDFRenderer {

    // MARK: - Configuration

    public struct PageSize: Hashable, Sendable {
        public var width: CGFloat
        public var height: CGFloat

        public init(width: CGFloat, height: CGFloat) {
            self.width = width
            self.height = height
        }

        /// 8.5 × 11 in at 72 dpi.
        public static let usLetter = PageSize(width: 612, height: 792)
        /// 210 × 297 mm at 72 dpi.
        public static let a4 = PageSize(width: 595.28, height: 841.89)
    }

    public var pageSize: PageSize
    /// Left and right margin.
    public var sideMargin: CGFloat
    /// First baseline area starts here; the running header sits above it.
    public var topMargin: CGFloat
    /// Content stops here; the running footer sits below it.
    public var bottomMargin: CGFloat

    public init(
        pageSize: PageSize = .usLetter,
        sideMargin: CGFloat = 56,
        topMargin: CGFloat = 74,
        bottomMargin: CGFloat = 62
    ) {
        self.pageSize = pageSize
        self.sideMargin = sideMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
    }

    private var contentWidth: CGFloat { pageSize.width - sideMargin * 2 }
    private var contentTop: CGFloat { topMargin }
    private var contentBottom: CGFloat { pageSize.height - bottomMargin }

    // MARK: - Public API

    /// Renders the whole report. Always returns at least one page, even for a
    /// room with no objects in it.
    public func render(_ report: SafetyReport) -> Data {
        let pages = paginate(blocks(for: report))
        let bounds = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: report.title,
            kCGPDFContextAuthor as String: "proof",
            kCGPDFContextCreator as String: "proof",
            kCGPDFContextSubject as String:
                "Earthquake safety assessment at intensity \(report.header.intensity.roman)",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                let cg = context.cgContext
                drawRunningHeader(report: report, in: cg)
                drawRunningFooter(
                    report: report, page: index + 1, of: pages.count, in: cg)
                for placed in page {
                    draw(placed, in: cg)
                }
            }
        }
    }

    /// Writes the PDF to disk, creating intermediate directories.
    @discardableResult
    public func write(_ report: SafetyReport, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try render(report).write(to: url, options: .atomic)
        return url
    }

    /// The number of pages the report will occupy, without rasterising anything.
    public func pageCount(of report: SafetyReport) -> Int {
        max(paginate(blocks(for: report)).count, 1)
    }

    /// How many pages the cover takes. It must always be one.
    ///
    /// Exposed for the test that keeps it that way. This broke once already:
    /// the cover fitted in the system font, and spilled its last two lines onto
    /// an otherwise blank second page as soon as the app's own typeface was
    /// registered, which is the state it actually ships in.
    func coverPageCount(of report: SafetyReport) -> Int {
        max(paginate(coverBlocks(report)).count, 1)
    }

    // MARK: - Palette

    private enum Ink {
        static let heading = UIColor(red: 0.10, green: 0.03, blue: 0.15, alpha: 1)
        static let body = UIColor(red: 0.18, green: 0.14, blue: 0.22, alpha: 1)
        static let secondary = UIColor(red: 0.42, green: 0.39, blue: 0.47, alpha: 1)
        static let tertiary = UIColor(red: 0.55, green: 0.52, blue: 0.60, alpha: 1)
        static let hairline = UIColor(red: 0.85, green: 0.83, blue: 0.87, alpha: 1)
        static let paper = UIColor.white

        static func band(_ band: RiskBand) -> UIColor {
            switch band {
            case .low: return UIColor(red: 0.09, green: 0.45, blue: 0.27, alpha: 1)
            case .moderate: return UIColor(red: 0.62, green: 0.44, blue: 0.02, alpha: 1)
            case .high: return UIColor(red: 0.74, green: 0.32, blue: 0.09, alpha: 1)
            case .severe: return UIColor(red: 0.63, green: 0.10, blue: 0.10, alpha: 1)
            }
        }

        static func bandTint(_ band: RiskBand) -> UIColor {
            band == .low
                ? UIColor(red: 0.94, green: 0.97, blue: 0.95, alpha: 1)
                : self.band(band).withAlphaComponent(0.08)
        }
    }

    // MARK: - Typography

    private enum Face {
        /// The app's display face when it is registered, the system face when it
        /// is not. The report must render identically in a unit test, where no
        /// app bundle has registered the fonts.
        static func display(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
            let name = weight == .bold ? "InstrumentSans-Bold" : "InstrumentSans-SemiBold"
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }

        static func text(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            let name: String
            switch weight {
            case .semibold: name = "Inter-SemiBold"
            case .medium: name = "Inter-Medium"
            case .bold: name = "Inter-Bold"
            default: name = "Inter-Regular"
            }
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }

        static func mono(_ size: CGFloat) -> UIFont {
            .monospacedDigitSystemFont(ofSize: size, weight: .medium)
        }
    }

    private func attributed(
        _ string: String, font: UIFont, color: UIColor,
        lineSpacing: CGFloat = 2.6, tracking: CGFloat = 0,
        alignment: NSTextAlignment = .natural, firstLineIndent: CGFloat = 0,
        headIndent: CGFloat = 0
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        paragraph.firstLineHeadIndent = firstLineIndent
        paragraph.headIndent = headIndent

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            // Both are needed: UIKit reads `.foregroundColor`, Core Text reads
            // its own key and silently draws black without it.
            .foregroundColor: color,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        if tracking != 0 {
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    // MARK: - Block model
    //
    // The document is a linear stream of blocks. Text blocks can split across a
    // page boundary line by line; everything else is atomic and simply moves to
    // the next page whole. That is the whole pagination model, and it is enough
    // to guarantee the two things a report must never do: clip text, or strand a
    // heading at the foot of a page.

    private struct TextBlock {
        var string: NSAttributedString
        var indent: CGFloat = 0
        var trailingInset: CGFloat = 0
        /// Refuse to leave this block alone at the bottom of a page.
        var keepWithNext: Bool = false
        /// Never split leaving fewer than this many points on the page — stops a
        /// single orphaned line at a page foot.
        var minimumSplit: CGFloat = 26
        var framesetter: CTFramesetter { CTFramesetterCreateWithAttributedString(string) }
    }

    private enum Block {
        case text(TextBlock)
        case spacer(CGFloat)
        case rule(topPadding: CGFloat, bottomPadding: CGFloat)
        case pageBreak
        case scoreBanner(band: RiskBand, score: Double, title: String, subtitle: String)
        case findingHeader(rank: Int, name: String, band: RiskBand, score: Double, headline: String)
        case factRow(label: String, value: String)
        case bandRow(band: RiskBand, count: Int, total: Int)
        case checkItem(number: Int, title: String, object: String, meta: String, band: RiskBand)
    }

    /// A block, or a slice of a text block, positioned on a page.
    private struct Placed {
        var block: Block
        var rect: CGRect
        /// For split text blocks: the character range drawn here.
        var range: CFRange = CFRange(location: 0, length: 0)
    }

    // MARK: - Pagination

    private func paginate(_ blocks: [Block]) -> [[Placed]] {
        var pages: [[Placed]] = []
        var page: [Placed] = []
        var y = contentTop

        func flush() {
            pages.append(page)
            page = []
            y = contentTop
        }

        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            index += 1

            switch block {
            case .pageBreak:
                if !page.isEmpty { flush() }

            case .spacer(let height):
                // A spacer at the top of a fresh page is dead space.
                if !page.isEmpty { y += height }

            case .text(let text):
                let width = contentWidth - text.indent - text.trailingInset
                let framesetter = text.framesetter
                let total = text.string.length
                var location = 0

                while location < total {
                    var available = contentBottom - y
                    if text.keepWithNext { available -= 30 }

                    // Not enough room for a meaningful slice: take it to the
                    // next page rather than orphaning one line.
                    if available < text.minimumSplit, !page.isEmpty {
                        flush()
                        continue
                    }

                    let fit = self.fit(
                        framesetter: framesetter, from: location, width: width,
                        maxHeight: max(available, 12), total: total)

                    if fit.length == 0 {
                        if page.isEmpty {
                            // Cannot happen for any block in this document, but
                            // if it ever did, drawing something clipped beats
                            // looping forever.
                            page.append(Placed(
                                block: .text(text),
                                rect: CGRect(x: sideMargin + text.indent, y: y,
                                             width: width, height: max(available, 12)),
                                range: CFRange(location: location, length: total - location)))
                            location = total
                            break
                        }
                        flush()
                        continue
                    }

                    page.append(Placed(
                        block: .text(text),
                        rect: CGRect(x: sideMargin + text.indent, y: y,
                                     width: width, height: fit.height),
                        range: CFRange(location: location, length: fit.length)))
                    y += fit.height
                    location += fit.length

                    if location < total { flush() }
                }

            default:
                let height = self.height(of: block)
                var needed = height
                if case .findingHeader = block { needed += 34 }
                if case .scoreBanner = block { needed += 20 }

                if y + needed > contentBottom, !page.isEmpty { flush() }
                page.append(Placed(
                    block: block,
                    rect: CGRect(x: sideMargin, y: y, width: contentWidth, height: height)))
                y += height
            }
        }

        if !page.isEmpty { pages.append(page) }
        return pages.isEmpty ? [[]] : pages
    }

    /// How much of `framesetter` fits in `maxHeight`, and how tall that is.
    private func fit(
        framesetter: CTFramesetter, from location: Int, width: CGFloat,
        maxHeight: CGFloat, total: Int
    ) -> (length: Int, height: CGFloat) {
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: width, height: maxHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: location, length: 0), path, nil)
        let visible = CTFrameGetVisibleStringRange(frame)
        guard visible.length > 0 else { return (0, 0) }

        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: location, length: visible.length), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), &fitRange)
        return (visible.length, ceil(size.height) + 1)
    }

    private func height(of block: Block) -> CGFloat {
        switch block {
        case .spacer(let height): return height
        case .rule(let top, let bottom): return top + bottom + 1
        case .pageBreak: return 0
        case .scoreBanner: return 96
        case .findingHeader: return 42
        case .factRow(let label, let value):
            let width = contentWidth - factLabelWidth - 10
            let text = attributed(value, font: Face.text(10), color: Ink.body)
            let height = ceil(text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            _ = label
            return max(height, 13) + 6
        case .bandRow: return 22
        case .checkItem(_, let title, _, _, _):
            let width = contentWidth - 26
            let text = attributed(title, font: Face.text(10.5, weight: .semibold), color: Ink.heading)
            let height = ceil(text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            return height + 26
        case .text(let text):
            let width = contentWidth - text.indent - text.trailingInset
            return fit(framesetter: text.framesetter, from: 0, width: width,
                       maxHeight: .greatestFiniteMagnitude, total: text.string.length).height
        }
    }

    private var factLabelWidth: CGFloat { 168 }

    // MARK: - Drawing

    private func draw(_ placed: Placed, in context: CGContext) {
        switch placed.block {
        case .spacer, .pageBreak:
            break

        case .rule(let top, _):
            let y = placed.rect.minY + top
            context.setStrokeColor(Ink.hairline.cgColor)
            context.setLineWidth(0.7)
            context.move(to: CGPoint(x: placed.rect.minX, y: y))
            context.addLine(to: CGPoint(x: placed.rect.maxX, y: y))
            context.strokePath()

        case .text(let text):
            drawText(text.string, range: placed.range, in: placed.rect, context: context)

        case .scoreBanner(let band, let score, let title, let subtitle):
            drawScoreBanner(band: band, score: score, title: title,
                            subtitle: subtitle, in: placed.rect, context: context)

        case .findingHeader(let rank, let name, let band, let score, let headline):
            drawFindingHeader(rank: rank, name: name, band: band, score: score,
                              headline: headline, in: placed.rect, context: context)

        case .factRow(let label, let value):
            let labelRect = CGRect(x: placed.rect.minX, y: placed.rect.minY,
                                   width: factLabelWidth, height: placed.rect.height)
            let valueRect = CGRect(x: placed.rect.minX + factLabelWidth,
                                   y: placed.rect.minY,
                                   width: placed.rect.width - factLabelWidth,
                                   height: placed.rect.height)
            drawText(attributed(label, font: Face.text(10), color: Ink.secondary),
                     in: labelRect, context: context)
            drawText(attributed(value, font: Face.text(10, weight: .medium), color: Ink.body),
                     in: valueRect, context: context)

        case .bandRow(let band, let count, let total):
            drawBandRow(band: band, count: count, total: total,
                        in: placed.rect, context: context)

        case .checkItem(let number, let title, let object, let meta, let band):
            drawCheckItem(number: number, title: title, object: object, meta: meta,
                          band: band, in: placed.rect, context: context)
        }
    }

    /// Draws an attributed string inside a UIKit-coordinate rect using Core
    /// Text, which needs the page flipped back the other way up.
    private func drawText(
        _ string: NSAttributedString, range: CFRange? = nil,
        in rect: CGRect, context: CGContext
    ) {
        guard string.length > 0, rect.height > 0 else { return }
        let drawRange = range ?? CFRange(location: 0, length: 0)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)

        let flipped = CGRect(
            x: rect.minX, y: pageSize.height - rect.maxY,
            width: rect.width, height: rect.height + 2)
        let path = CGPath(rect: flipped, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, drawRange, path, nil)
        CTFrameDraw(frame, context)

        context.restoreGState()
    }

    private func drawScoreBanner(
        band: RiskBand, score: Double, title: String, subtitle: String,
        in rect: CGRect, context: CGContext
    ) {
        let box = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 88)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 10)
        context.setFillColor(Ink.bandTint(band).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()

        // The severity stripe: the one piece of colour that has to survive being
        // photocopied, so it is a solid bar rather than a tint.
        let stripe = CGRect(x: box.minX, y: box.minY, width: 5, height: box.height)
        context.setFillColor(Ink.band(band).cgColor)
        context.addPath(UIBezierPath(roundedRect: stripe, cornerRadius: 2.5).cgPath)
        context.fillPath()

        let scoreText = attributed(
            "\(Int(score.rounded()))", font: Face.display(34, weight: .bold),
            color: Ink.band(band), lineSpacing: 0)
        drawText(scoreText, in: CGRect(x: box.minX + 20, y: box.minY + 16,
                                       width: 74, height: 44), context: context)
        drawText(
            attributed("out of 100", font: Face.text(8), color: Ink.secondary, lineSpacing: 0),
            in: CGRect(x: box.minX + 21, y: box.minY + 58, width: 74, height: 12),
            context: context)

        let textX = box.minX + 100
        let textWidth = box.width - 120
        drawText(
            attributed(title, font: Face.display(16), color: Ink.heading, lineSpacing: 0),
            in: CGRect(x: textX, y: box.minY + 17, width: textWidth, height: 22),
            context: context)
        drawText(
            attributed(subtitle, font: Face.text(10), color: Ink.body, lineSpacing: 2),
            in: CGRect(x: textX, y: box.minY + 40, width: textWidth, height: 40),
            context: context)
    }

    private func drawFindingHeader(
        rank: Int, name: String, band: RiskBand, score: Double, headline: String,
        in rect: CGRect, context: CGContext
    ) {
        // Rank chip.
        let chip = CGRect(x: rect.minX, y: rect.minY + 1, width: 20, height: 18)
        context.setFillColor(Ink.band(band).cgColor)
        context.addPath(UIBezierPath(roundedRect: chip, cornerRadius: 4).cgPath)
        context.fillPath()
        drawText(
            attributed("\(rank)", font: Face.text(9.5, weight: .semibold),
                       color: Ink.paper, lineSpacing: 0, alignment: .center),
            in: CGRect(x: chip.minX, y: chip.minY + 3.5, width: chip.width, height: 13),
            context: context)

        // Band label, right aligned.
        let bandText = "\(band.displayName.uppercased()) · \(Int(score.rounded()))"
        let bandString = attributed(
            bandText, font: Face.text(8.5, weight: .semibold), color: Ink.band(band),
            lineSpacing: 0, tracking: 0.6, alignment: .right)
        drawText(bandString,
                 in: CGRect(x: rect.maxX - 190, y: rect.minY + 4, width: 190, height: 14),
                 context: context)

        drawText(
            attributed(name, font: Face.display(13), color: Ink.heading, lineSpacing: 0),
            in: CGRect(x: rect.minX + 28, y: rect.minY + 2, width: rect.width - 220, height: 18),
            context: context)
        drawText(
            attributed(headline, font: Face.text(10), color: Ink.body, lineSpacing: 0),
            in: CGRect(x: rect.minX + 28, y: rect.minY + 20, width: rect.width - 40, height: 14),
            context: context)

        context.setStrokeColor(Ink.hairline.cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: rect.minX, y: rect.minY + 38))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 38))
        context.strokePath()
    }

    private func drawBandRow(
        band: RiskBand, count: Int, total: Int, in rect: CGRect, context: CGContext
    ) {
        drawText(
            attributed(band.displayName, font: Face.text(10, weight: .medium), color: Ink.body,
                       lineSpacing: 0),
            in: CGRect(x: rect.minX, y: rect.minY + 3, width: 90, height: 14),
            context: context)

        let barX = rect.minX + 96
        let barWidth = rect.width - 96 - 40
        let track = CGRect(x: barX, y: rect.minY + 5, width: barWidth, height: 9)
        context.setFillColor(Ink.hairline.withAlphaComponent(0.5).cgColor)
        context.addPath(UIBezierPath(roundedRect: track, cornerRadius: 4.5).cgPath)
        context.fillPath()

        if count > 0, total > 0 {
            let fraction = CGFloat(count) / CGFloat(total)
            let fill = CGRect(x: barX, y: rect.minY + 5,
                              width: max(barWidth * fraction, 9), height: 9)
            context.setFillColor(Ink.band(band).cgColor)
            context.addPath(UIBezierPath(roundedRect: fill, cornerRadius: 4.5).cgPath)
            context.fillPath()
        }

        drawText(
            attributed("\(count)", font: Face.mono(10), color: Ink.body,
                       lineSpacing: 0, alignment: .right),
            in: CGRect(x: rect.maxX - 32, y: rect.minY + 3, width: 32, height: 14),
            context: context)
    }

    private func drawCheckItem(
        number: Int, title: String, object: String, meta: String, band: RiskBand,
        in rect: CGRect, context: CGContext
    ) {
        let box = CGRect(x: rect.minX, y: rect.minY + 1, width: 13, height: 13)
        context.setStrokeColor(Ink.band(band).cgColor)
        context.setLineWidth(1.1)
        context.addPath(UIBezierPath(roundedRect: box, cornerRadius: 3.5).cgPath)
        context.strokePath()

        let textX = rect.minX + 26
        let textWidth = rect.width - 26
        let titleString = attributed(
            title, font: Face.text(10.5, weight: .semibold), color: Ink.heading, lineSpacing: 1.5)
        let titleHeight = ceil(titleString.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)

        drawText(titleString,
                 in: CGRect(x: textX, y: rect.minY, width: textWidth, height: titleHeight + 2),
                 context: context)
        drawText(
            attributed("\(object) · \(meta)", font: Face.text(9), color: Ink.secondary,
                       lineSpacing: 0),
            in: CGRect(x: textX, y: rect.minY + titleHeight + 2, width: textWidth, height: 13),
            context: context)
    }

    // MARK: - Running head and foot

    private func drawRunningHeader(report: SafetyReport, in context: CGContext) {
        let y: CGFloat = 34
        drawText(
            attributed("TREMOR · EARTHQUAKE SAFETY REPORT", font: Face.text(7.5, weight: .semibold),
                       color: Ink.tertiary, lineSpacing: 0, tracking: 0.8),
            in: CGRect(x: sideMargin, y: y, width: contentWidth * 0.6, height: 12),
            context: context)
        drawText(
            attributed(report.header.roomName, font: Face.text(7.5, weight: .medium),
                       color: Ink.tertiary, lineSpacing: 0, tracking: 0.4, alignment: .right),
            in: CGRect(x: sideMargin + contentWidth * 0.4, y: y,
                       width: contentWidth * 0.6, height: 12),
            context: context)

        context.setStrokeColor(Ink.hairline.cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: sideMargin, y: y + 16))
        context.addLine(to: CGPoint(x: pageSize.width - sideMargin, y: y + 16))
        context.strokePath()
    }

    private func drawRunningFooter(
        report: SafetyReport, page: Int, of total: Int, in context: CGContext
    ) {
        let y = pageSize.height - 44

        context.setStrokeColor(Ink.hairline.cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: sideMargin, y: y))
        context.addLine(to: CGPoint(x: pageSize.width - sideMargin, y: y))
        context.strokePath()

        drawText(
            attributed(
                "Generated \(ReportFormat.shortDate(report.header.generatedAt)) · "
                    + "Intensity \(report.header.intensity.roman) · Estimate, not a professional inspection",
                font: Face.text(7.5), color: Ink.tertiary, lineSpacing: 0),
            in: CGRect(x: sideMargin, y: y + 7, width: contentWidth * 0.75, height: 12),
            context: context)
        drawText(
            attributed("Page \(page) of \(total)", font: Face.mono(7.5), color: Ink.tertiary,
                       lineSpacing: 0, alignment: .right),
            in: CGRect(x: sideMargin + contentWidth * 0.75, y: y + 7,
                       width: contentWidth * 0.25, height: 12),
            context: context)
    }

    // MARK: - Content

    private func blocks(for report: SafetyReport) -> [Block] {
        var blocks: [Block] = []
        blocks += coverBlocks(report)
        blocks.append(.pageBreak)
        blocks += findingBlocks(report)
        blocks.append(.pageBreak)
        blocks += checklistBlocks(report)
        blocks.append(.pageBreak)
        blocks += methodologyBlocks(report)
        return blocks
    }

    // Title page.
    //
    // Sized to fit one page with room to spare, and checked against the widest
    // of the fixture rooms. It is the one page in the document that must not
    // spill: a cover whose last two lines fall onto an otherwise blank page 2
    // is the single most obvious sign of a generated document.
    private func coverBlocks(_ report: SafetyReport) -> [Block] {
        var blocks: [Block] = []
        let header = report.header

        blocks.append(.text(TextBlock(
            string: attributed("Earthquake safety report", font: Face.display(27),
                               color: Ink.heading, lineSpacing: 0))))
        blocks.append(.spacer(6))
        blocks.append(.text(TextBlock(
            string: attributed(header.identityLine, font: Face.text(11),
                               color: Ink.secondary, lineSpacing: 0))))
        blocks.append(.spacer(16))

        blocks.append(.scoreBanner(
            band: report.summary.overallBand,
            score: report.summary.overallScore,
            title: report.summary.headline,
            subtitle: report.summary.action))
        blocks.append(.spacer(14))

        blocks.append(.text(TextBlock(
            string: attributed(report.summary.narrative, font: Face.text(10.5), color: Ink.body,
                               lineSpacing: 3))))
        blocks.append(.spacer(16))

        if report.summary.objectsAssessed > 0 {
            blocks += section("What was found")
            for count in report.summary.bandCounts {
                blocks.append(.bandRow(
                    band: count.band, count: count.count,
                    total: max(report.summary.objectsAssessed, 1)))
            }
            blocks.append(.spacer(14))
        }

        blocks += section("What was tested")
        for fact in header.facts {
            blocks.append(.factRow(label: fact.label, value: fact.value))
        }

        return blocks
    }

    // One entry per object, worst first.
    private func findingBlocks(_ report: SafetyReport) -> [Block] {
        var blocks: [Block] = []
        blocks += section("Findings")

        guard !report.findings.isEmpty else {
            blocks.append(.text(TextBlock(
                string: attributed(
                    """
                    This scan contains no objects, so there is nothing to report on. That \
                    usually means the room was scanned too quickly for the furniture to be \
                    recognised, or that the room really is empty. Re-scan it slowly, keeping \
                    each piece of furniture in frame for a couple of seconds, and the findings \
                    will appear here.
                    """,
                    font: Face.text(11), color: Ink.body, lineSpacing: 3.4))))
            return blocks
        }

        blocks.append(.text(TextBlock(
            string: attributed(
                "At intensity \(report.header.intensity.roman): \(report.header.intensityContents) "
                    + "\(report.findings.count) \(report.findings.count == 1 ? "object was" : "objects were") assessed, "
                    + "ordered worst first, each with the reasoning behind it.",
                font: Face.text(10), color: Ink.secondary, lineSpacing: 2.8))))
        blocks.append(.spacer(14))

        for finding in report.findings {
            blocks.append(.findingHeader(
                rank: finding.rank, name: finding.name, band: finding.band,
                score: finding.score, headline: finding.headline))
            blocks.append(.spacer(6))

            blocks.append(.text(TextBlock(
                string: attributed(finding.measurementsLine, font: Face.text(8.8),
                                   color: Ink.tertiary, lineSpacing: 1.6))))
            blocks.append(.text(TextBlock(
                string: attributed(finding.physicsLine, font: Face.text(8.8),
                                   color: Ink.tertiary, lineSpacing: 1.6))))
            blocks.append(.spacer(8))

            blocks.append(.text(TextBlock(
                string: attributed("Why", font: Face.text(9, weight: .semibold),
                                   color: Ink.heading, lineSpacing: 0, tracking: 0.5),
                keepWithNext: true)))
            blocks.append(.spacer(4))
            for reason in finding.reasons {
                blocks.append(.text(TextBlock(
                    string: bullet(reason, font: Face.text(10), color: Ink.body),
                    indent: 4)))
                blocks.append(.spacer(3))
            }

            if !finding.endangers.isEmpty {
                blocks.append(.spacer(3))
                blocks.append(.text(TextBlock(
                    string: attributed(
                        "In its path: \(ReportFormat.list(finding.endangers))",
                        font: Face.text(9.5, weight: .medium), color: Ink.body, lineSpacing: 2))))
            }

            if let note = finding.regulatoryNote {
                blocks.append(.spacer(6))
                blocks.append(.text(TextBlock(
                    string: attributed("Code requirement — \(note)",
                                       font: Face.text(9.5, weight: .medium),
                                       color: Ink.band(.severe), lineSpacing: 2.4))))
            }

            if finding.identification.isUncertain {
                blocks.append(.spacer(5))
                blocks.append(.text(TextBlock(
                    string: attributed(
                        "Identified with \(ReportFormat.percent(finding.identification.confidence)) confidence "
                            + "from the scanner category \"\(finding.identification.scannerCategory)\". "
                            + "If this is not a \(finding.name.lowercased()), correct it and re-run.",
                        font: Face.text(9), color: Ink.secondary, lineSpacing: 2))))
            }

            if !finding.fixes.isEmpty {
                blocks.append(.spacer(9))
                blocks.append(.text(TextBlock(
                    string: attributed("How to fix it", font: Face.text(9, weight: .semibold),
                                       color: Ink.heading, lineSpacing: 0, tracking: 0.5),
                    keepWithNext: true)))
                blocks.append(.spacer(5))

                for fix in finding.fixes {
                    blocks.append(.text(TextBlock(
                        string: attributed(fix.title, font: Face.text(10, weight: .semibold),
                                           color: Ink.heading, lineSpacing: 1.6),
                        indent: 4, keepWithNext: true)))
                    blocks.append(.text(TextBlock(
                        string: attributed(
                            "\(fix.metaLine) · \(fix.standardReference)",
                            font: Face.text(8.5), color: Ink.tertiary, lineSpacing: 1.4),
                        indent: 4)))
                    blocks.append(.spacer(3))
                    blocks.append(.text(TextBlock(
                        string: attributed(fix.detail, font: Face.text(9.6), color: Ink.body,
                                           lineSpacing: 2.8),
                        indent: 4)))
                    if !fix.hardware.isEmpty {
                        blocks.append(.spacer(3))
                        blocks.append(.text(TextBlock(
                            string: attributed(
                                "You need: " + fix.hardware.map {
                                    $0.quantity > 1 ? "\($0.quantity) × \($0.name)" : $0.name
                                }.joined(separator: ", "),
                                font: Face.text(9), color: Ink.secondary, lineSpacing: 2),
                            indent: 4)))
                    }
                    blocks.append(.spacer(8))
                }
            }

            if let anchorage = finding.anchorage {
                blocks.append(.text(TextBlock(
                    string: attributed(
                        "Anchorage demand (ASCE 7-22 Eq. 13.3-1): \(anchorage.summaryLine). \(anchorage.note)",
                        font: Face.text(9), color: Ink.secondary, lineSpacing: 2.2),
                    indent: 4)))
                blocks.append(.spacer(6))
            }

            blocks.append(.rule(topPadding: 6, bottomPadding: 12))
        }

        return blocks
    }

    // The fix-it plan.
    private func checklistBlocks(_ report: SafetyReport) -> [Block] {
        var blocks: [Block] = []
        blocks += section("Fix-it plan")

        guard !report.checklist.isEmpty else {
            blocks.append(.text(TextBlock(
                string: attributed(
                    report.findings.isEmpty
                        ? "There is nothing to fix, because there is nothing in this scan to assess."
                        : "Nothing in this room needs securing at the intensity tested. If you want a stricter answer, run the room again at a higher intensity.",
                    font: Face.text(11), color: Ink.body, lineSpacing: 3.2))))
            return blocks
        }

        blocks.append(.text(TextBlock(
            string: attributed(
                "\(report.checklist.summaryLine). Work down the list — it is ordered so that the "
                    + "thing most likely to hurt someone is fixed first.",
                font: Face.text(10.5), color: Ink.body, lineSpacing: 3))))
        blocks.append(.spacer(14))

        for item in report.checklist.items {
            blocks.append(.checkItem(
                number: item.priority,
                title: "\(item.priority). \(item.fix.title) — \(item.objectName)",
                object: item.band.displayName.lowercased() + " risk",
                meta: "\(item.fix.metaLine) · \(item.fix.standardReference)",
                band: item.band))
            blocks.append(.text(TextBlock(
                string: attributed(item.fix.summary, font: Face.text(9.5), color: Ink.secondary,
                                   lineSpacing: 2),
                indent: 26)))
            blocks.append(.spacer(11))
        }

        if !report.checklist.shoppingList.isEmpty {
            blocks.append(.spacer(8))
            blocks += section("Shopping list")
            for item in report.checklist.shoppingList {
                blocks.append(.text(TextBlock(
                    string: bullet(item.displayLine, font: Face.text(10), color: Ink.body),
                    indent: 4)))
                blocks.append(.spacer(3))
            }
            blocks.append(.spacer(8))
            blocks.append(.text(TextBlock(
                string: attributed(
                    "Costs are rough US retail prices for the hardware only, and are there to show "
                        + "that this is a cheap afternoon rather than a renovation.",
                    font: Face.text(9), color: Ink.tertiary, lineSpacing: 2))))
        }

        return blocks
    }

    // The appendix.
    private func methodologyBlocks(_ report: SafetyReport) -> [Block] {
        var blocks: [Block] = []
        let methodology = report.methodology

        blocks += section("How this was worked out")
        blocks.append(.text(TextBlock(
            string: attributed(methodology.overview, font: Face.text(10.5), color: Ink.body,
                               lineSpacing: 3))))
        blocks.append(.spacer(14))

        for step in methodology.steps {
            blocks.append(.text(TextBlock(
                string: attributed(step.title, font: Face.text(10, weight: .semibold),
                                   color: Ink.heading, lineSpacing: 0),
                keepWithNext: true)))
            blocks.append(.spacer(4))
            blocks.append(.text(TextBlock(
                string: attributed(step.body, font: Face.text(9.8), color: Ink.body,
                                   lineSpacing: 2.8))))
            blocks.append(.spacer(10))
        }

        blocks.append(.spacer(6))
        blocks += section("How far to trust this")
        for item in methodology.uncertainties {
            blocks.append(.text(TextBlock(
                string: attributed(item.title, font: Face.text(10, weight: .semibold),
                                   color: Ink.heading, lineSpacing: 0),
                keepWithNext: true)))
            blocks.append(.spacer(4))
            blocks.append(.text(TextBlock(
                string: attributed(item.body, font: Face.text(9.8), color: Ink.body,
                                   lineSpacing: 2.8))))
            blocks.append(.spacer(10))
        }

        blocks.append(.spacer(4))
        blocks += section("What this report does not cover")
        for limitation in methodology.limitations {
            blocks.append(.text(TextBlock(
                string: bullet(limitation, font: Face.text(9.8), color: Ink.body),
                indent: 4)))
            blocks.append(.spacer(4))
        }

        blocks.append(.spacer(10))
        blocks += section("Sources")
        for citation in methodology.citations {
            blocks.append(.text(TextBlock(
                string: attributed(citation.reference, font: Face.text(9.4), color: Ink.body,
                                   lineSpacing: 2.4),
                keepWithNext: true)))
            blocks.append(.spacer(2))
            blocks.append(.text(TextBlock(
                string: attributed("Used for: \(citation.usedFor)", font: Face.text(9),
                                   color: Ink.secondary, lineSpacing: 2.2),
                indent: 12)))
            blocks.append(.spacer(9))
        }

        blocks.append(.spacer(6))
        blocks.append(.rule(topPadding: 0, bottomPadding: 10))
        blocks.append(.text(TextBlock(
            string: attributed(methodology.disclaimer, font: Face.text(9), color: Ink.secondary,
                               lineSpacing: 2.6))))

        return blocks
    }

    // MARK: - Small helpers

    private func section(_ title: String) -> [Block] {
        [
            .text(TextBlock(
                string: attributed(title.uppercased(), font: Face.text(9, weight: .semibold),
                                   color: Ink.band(.severe), lineSpacing: 0, tracking: 1.1),
                keepWithNext: true)),
            .spacer(4),
            .rule(topPadding: 0, bottomPadding: 9),
        ]
    }

    private func bullet(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        attributed("•\u{2003}" + text, font: font, color: color,
                   lineSpacing: 2.6, headIndent: 13)
    }
}
