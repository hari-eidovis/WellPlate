import AppKit
import Foundation
import PDFKit

struct TocEntry {
    let title: String
    let page: String
    let indent: CGFloat
    let bold: Bool
}

struct HeadingRun {
    let page: Int
    let x: CGFloat
    let yTop: CGFloat
    let width: CGFloat
    let height: CGFloat
    let text: String
}

let inputPath = "/Users/hariom/Desktop/WellPlate/MayankJangid_SpecBridge.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/MayankJangid_SpecBridge_format_fixed_safe.pdf"
let xmlPath = "/Users/hariom/Desktop/WellPlate/tmp_specbridge_preview/specbridge_xml.xml"

let scale: CGFloat = 1.5
let pageHeight: CGFloat = 792

let bodyFont = NSFont(name: "TimesNewRomanPSMT", size: 10.5)
    ?? NSFont(name: "Times-Roman", size: 10.5)
    ?? .systemFont(ofSize: 10.5)
let bodyFont12 = NSFont(name: "TimesNewRomanPSMT", size: 12)
    ?? NSFont(name: "Times-Roman", size: 12)
    ?? .systemFont(ofSize: 12)
let headingFont = NSFont(name: "TimesNewRomanPS-BoldMT", size: 14)
    ?? NSFont(name: "Times-Bold", size: 14)
    ?? .boldSystemFont(ofSize: 14)
let chapterFont = NSFont(name: "TimesNewRomanPS-BoldMT", size: 12)
    ?? NSFont(name: "Times-Bold", size: 12)
    ?? .boldSystemFont(ofSize: 12)
let coverTitleFont = NSFont(name: "TimesNewRomanPS-BoldMT", size: 34)
    ?? NSFont(name: "Times-Bold", size: 34)
    ?? .boldSystemFont(ofSize: 34)
let footerFont = NSFont(name: "TimesNewRomanPSMT", size: 12)
    ?? NSFont(name: "Times-Roman", size: 12)
    ?? .systemFont(ofSize: 12)

func addCover(to page: PDFPage, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let annotation = PDFAnnotation(bounds: CGRect(x: x, y: y, width: width, height: height), forType: .square, withProperties: nil)
    let border = PDFBorder()
    border.lineWidth = 0
    annotation.border = border
    annotation.color = .white
    annotation.interiorColor = .white
    annotation.shouldPrint = true
    page.addAnnotation(annotation)
}

func addCoverFromTop(to page: PDFPage, x: CGFloat, yTop: CGFloat, width: CGFloat, height: CGFloat) {
    addCover(to: page, x: x, y: pageHeight - yTop - height, width: width, height: height)
}

func addText(
    to page: PDFPage,
    text: String,
    x: CGFloat,
    yTop: CGFloat,
    width: CGFloat,
    height: CGFloat,
    font: NSFont,
    alignment: NSTextAlignment = .left,
    color: NSColor = .black
) {
    let annotation = PDFAnnotation(
        bounds: CGRect(x: x, y: pageHeight - yTop - height, width: width, height: height),
        forType: .freeText,
        withProperties: nil
    )
    annotation.contents = text
    annotation.font = font
    annotation.fontColor = color
    annotation.alignment = alignment
    annotation.color = .clear
    let border = PDFBorder()
    border.lineWidth = 0
    annotation.border = border
    annotation.shouldPrint = true
    page.addAnnotation(annotation)
}

func decodeXMLText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func isReportHeadingText(_ text: String) -> Bool {
    let titleHeadings: Set<String> = [
        "Bonafide Certificate",
        "Declaration",
        "Acknowledgement",
        "Executive Summary",
        "Abstract",
        "Table of Contents",
        "List of Abbreviations, Tables and Figures",
        "List of Figures",
        "List of Tables",
        "List of Abbreviations",
    ]
    if titleHeadings.contains(text) {
        return true
    }
    if text.range(of: #"^Chapter [0-9]+:"#, options: .regularExpression) != nil {
        return true
    }
    return text.range(of: #"^[0-9]+(\.[0-9]+)+\s+\S"#, options: .regularExpression) != nil
}

func parseColoredHeadings(from xml: String) -> [HeadingRun] {
    let lines = xml.components(separatedBy: .newlines)
    let fontSpecPattern = #"<fontspec id=\"([0-9]+)\" size=\"[^\"]+\" family=\"[^\"]+\" color=\"([^\"]+)\"/>"#
    let textPattern = #"<text top=\"([0-9.]+)\" left=\"([0-9.]+)\" width=\"([0-9.]+)\" height=\"([0-9.]+)\" font=\"([0-9]+)\">(.*)</text>"#
    let fontRegex = try! NSRegularExpression(pattern: fontSpecPattern)
    let textRegex = try! NSRegularExpression(pattern: textPattern)

    var currentPage = 0
    var headingFonts = Set<String>()
    var result: [HeadingRun] = []

    for line in lines {
        if line.contains("<page number="),
           let pageRange = line.range(of: #"number=\"([0-9]+)\""#, options: .regularExpression) {
            let raw = String(line[pageRange])
            currentPage = Int(raw.replacingOccurrences(of: #"number=\""#, with: "", options: .regularExpression).replacingOccurrences(of: "\"", with: "")) ?? 0
        }

        let nsLine = line as NSString
        if let match = fontRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
            let id = nsLine.substring(with: match.range(at: 1))
            let color = nsLine.substring(with: match.range(at: 2)).lowercased()
            if color == "#1f3764" || color == "#2e74b5" {
                headingFonts.insert(id)
            }
        }

        guard currentPage > 1, !(6...7).contains(currentPage) else { continue }
        if let match = textRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
            let fontId = nsLine.substring(with: match.range(at: 5))
            guard headingFonts.contains(fontId) else { continue }
            let text = decodeXMLText(nsLine.substring(with: match.range(at: 6)))
            guard isReportHeadingText(text) else { continue }
            let top = CGFloat(Double(nsLine.substring(with: match.range(at: 1))) ?? 0) / scale
            let left = CGFloat(Double(nsLine.substring(with: match.range(at: 2))) ?? 0) / scale
            let width = CGFloat(Double(nsLine.substring(with: match.range(at: 3))) ?? 0) / scale
            let height = CGFloat(Double(nsLine.substring(with: match.range(at: 4))) ?? 0) / scale
            result.append(HeadingRun(page: currentPage, x: left, yTop: top, width: width, height: height, text: text))
        }
    }

    return result
}

func roman(_ value: Int) -> String {
    let pairs: [(Int, String)] = [
        (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
    ]
    var number = value
    var output = ""
    for (arabic, numeral) in pairs {
        while number >= arabic {
            output += numeral
            number -= arabic
        }
    }
    return output
}

func redrawCoverTitle(on document: PDFDocument) {
    guard let page = document.page(at: 0) else { return }
    addCoverFromTop(to: page, x: 190, yTop: 94, width: 235, height: 45)
    addText(to: page, text: "SpecBridge", x: 188, yTop: 98, width: 238, height: 42, font: coverTitleFont, alignment: .center)
}

func redrawTOC(on document: PDFDocument) {
    let entries: [TocEntry] = [
        TocEntry(title: "Bonafide Certificate", page: "i", indent: 0, bold: false),
        TocEntry(title: "Declaration", page: "ii", indent: 0, bold: false),
        TocEntry(title: "Acknowledgement", page: "iii", indent: 0, bold: false),
        TocEntry(title: "Executive Summary", page: "iv", indent: 0, bold: false),
        TocEntry(title: "Table of Contents", page: "v", indent: 0, bold: false),
        TocEntry(title: "Abstract", page: "vii", indent: 0, bold: false),
        TocEntry(title: "List of Abbreviations, Tables and Figures", page: "viii", indent: 0, bold: false),
        TocEntry(title: "Chapter 1: Introduction", page: "1", indent: 0, bold: true),
        TocEntry(title: "1.1 Introduction to the Study", page: "1", indent: 18, bold: false),
        TocEntry(title: "1.2 Background of the Study", page: "1", indent: 18, bold: false),
        TocEntry(title: "1.3 Problem Statement", page: "2", indent: 18, bold: false),
        TocEntry(title: "1.4 Need for the Proposed System", page: "3", indent: 18, bold: false),
        TocEntry(title: "1.5 Objectives of the Project", page: "3", indent: 18, bold: false),
        TocEntry(title: "1.6 Scope of the Project", page: "4", indent: 18, bold: false),
        TocEntry(title: "1.7 Organization of the Report", page: "4", indent: 18, bold: false),
        TocEntry(title: "Chapter 2: System Study / Literature Review", page: "5", indent: 0, bold: true),
        TocEntry(title: "2.1 Introduction", page: "5", indent: 18, bold: false),
        TocEntry(title: "2.2 Overview of Neurodiversity Research", page: "5", indent: 18, bold: false),
        TocEntry(title: "2.3 The Double Empathy Problem", page: "5", indent: 18, bold: false),
        TocEntry(title: "2.4 Existing Empathy-Building Tools and Their Limitations", page: "6", indent: 18, bold: false),
        TocEntry(title: "2.5 Sensory Simulation in HCI Research", page: "6", indent: 18, bold: false),
        TocEntry(title: "2.6 On-Device Language Models and Privacy", page: "7", indent: 18, bold: false),
        TocEntry(title: "2.7 Research Gap", page: "7", indent: 18, bold: false),
        TocEntry(title: "2.8 Summary", page: "7", indent: 18, bold: false),
        TocEntry(title: "Chapter 3: System Analysis / Problem Description", page: "8", indent: 0, bold: true),
        TocEntry(title: "3.1 Introduction", page: "8", indent: 18, bold: false),
        TocEntry(title: "3.2 Existing System Analysis", page: "8", indent: 18, bold: false),
        TocEntry(title: "3.3 Limitations of Existing Systems", page: "9", indent: 18, bold: false),
        TocEntry(title: "3.4 Proposed System", page: "9", indent: 18, bold: false),
        TocEntry(title: "3.5 Functional Requirements", page: "10", indent: 18, bold: false),
        TocEntry(title: "3.6 Non-Functional Requirements", page: "11", indent: 18, bold: false),
        TocEntry(title: "3.7 Feasibility Study", page: "11", indent: 18, bold: false),
        TocEntry(title: "3.8 Summary", page: "12", indent: 18, bold: false),
        TocEntry(title: "Chapter 4: System Design / Model Design", page: "13", indent: 0, bold: true),
        TocEntry(title: "4.1 Introduction", page: "13", indent: 18, bold: false),
        TocEntry(title: "4.2 Overall System Architecture (MVVM)", page: "13", indent: 18, bold: false),
        TocEntry(title: "4.3 Module Design", page: "13", indent: 18, bold: false),
        TocEntry(title: "4.4 Data Flow Design", page: "14", indent: 18, bold: false),
        TocEntry(title: "4.5 UI/UX Design Principles", page: "15", indent: 18, bold: false),
        TocEntry(title: "4.6 Shader and Effects Pipeline Design", page: "15", indent: 18, bold: false),
        TocEntry(title: "4.7 Audio Graph Design", page: "16", indent: 18, bold: false),
        TocEntry(title: "4.8 AI Integration Design", page: "16", indent: 18, bold: false),
        TocEntry(title: "4.9 Summary", page: "17", indent: 18, bold: false),
        TocEntry(title: "Chapter 5: System Implementation", page: "18", indent: 0, bold: true),
        TocEntry(title: "5.1 Introduction", page: "18", indent: 18, bold: false),
        TocEntry(title: "5.2 Development Environment and Tools", page: "18", indent: 18, bold: false),
        TocEntry(title: "5.3 Sensory Simulator Module Implementation", page: "18", indent: 18, bold: false),
        TocEntry(title: "5.4 Perspective Bridge Module Implementation", page: "19", indent: 18, bold: false),
        TocEntry(title: "5.5 Tone Decoder Module Implementation", page: "20", indent: 18, bold: false),
        TocEntry(title: "5.6 Audio Engine Implementation", page: "20", indent: 18, bold: false),
        TocEntry(title: "5.7 Haptic Engine Implementation", page: "21", indent: 18, bold: false),
        TocEntry(title: "5.8 Foundation Models Integration", page: "21", indent: 18, bold: false),
        TocEntry(title: "5.9 Summary", page: "21", indent: 18, bold: false),
        TocEntry(title: "Chapter 6: Testing", page: "22", indent: 0, bold: true),
        TocEntry(title: "6.1 Introduction", page: "22", indent: 18, bold: false),
        TocEntry(title: "6.2 Testing Strategy", page: "22", indent: 18, bold: false),
        TocEntry(title: "6.3 Unit Testing", page: "22", indent: 18, bold: false),
        TocEntry(title: "6.4 Integration Testing", page: "23", indent: 18, bold: false),
        TocEntry(title: "6.5 Performance and Frame-Rate Testing", page: "23", indent: 18, bold: false),
        TocEntry(title: "6.6 Accessibility Testing", page: "24", indent: 18, bold: false),
        TocEntry(title: "6.7 User Acceptance Testing", page: "25", indent: 18, bold: false),
        TocEntry(title: "6.8 Summary", page: "25", indent: 18, bold: false),
        TocEntry(title: "Chapter 7: Results and Discussion", page: "26", indent: 0, bold: true),
        TocEntry(title: "7.1 Introduction", page: "26", indent: 18, bold: false),
        TocEntry(title: "7.2 Functional Outcomes", page: "26", indent: 18, bold: false),
        TocEntry(title: "7.3 Performance Outcomes", page: "26", indent: 18, bold: false),
        TocEntry(title: "7.4 Qualitative User Feedback", page: "27", indent: 18, bold: false),
        TocEntry(title: "7.5 Comparative Analysis", page: "27", indent: 18, bold: false),
        TocEntry(title: "7.6 Limitations", page: "28", indent: 18, bold: false),
        TocEntry(title: "7.7 Summary", page: "28", indent: 18, bold: false),
        TocEntry(title: "Chapter 8: Conclusion and Future Scope", page: "29", indent: 0, bold: true),
        TocEntry(title: "8.1 Conclusion", page: "29", indent: 18, bold: false),
        TocEntry(title: "8.2 Key Achievements", page: "29", indent: 18, bold: false),
        TocEntry(title: "8.3 Future Scope", page: "30", indent: 18, bold: false),
        TocEntry(title: "8.4 Final Remarks", page: "31", indent: 18, bold: false),
        TocEntry(title: "Chapter 9: References / Bibliography", page: "32", indent: 0, bold: true),
    ]

    let pageSplits = [43, entries.count]
    var start = 0
    for tocPageNumber in 6...7 {
        guard let page = document.page(at: tocPageNumber - 1) else { continue }
        addCoverFromTop(to: page, x: 68, yTop: 70, width: 476, height: 650)
        if tocPageNumber == 6 {
            addText(to: page, text: "Table of Contents", x: 72, yTop: 72, width: 300, height: 24, font: headingFont)
        }
        let end = pageSplits[tocPageNumber - 6]
        var y: CGFloat = tocPageNumber == 6 ? 108 : 88
        for entry in entries[start..<end] {
            let font = entry.bold ? chapterFont : bodyFont
            addText(to: page, text: entry.title, x: 72 + entry.indent, yTop: y, width: 410 - entry.indent, height: 19, font: font)
            addText(to: page, text: entry.page, x: 510, yTop: y, width: 34, height: 19, font: font, alignment: .right)
            y += entry.bold ? 16 : 14
        }
        start = end
    }
}

func redrawFigureAndTableLists(on document: PDFDocument) {
    guard let page = document.page(at: 8) else { return }
    addCoverFromTop(to: page, x: 68, yTop: 108, width: 480, height: 370)

    let figureEntries: [TocEntry] = [
        TocEntry(title: "Figure 4.1: Overall MVVM Architecture of SpecBridge", page: "13", indent: 0, bold: false),
        TocEntry(title: "Figure 4.2: Inter-Module Data Flow Diagram", page: "15", indent: 0, bold: false),
        TocEntry(title: "Figure 4.3: Audio Graph Pipeline (Speech and Ambient Synthesis)", page: "16", indent: 0, bold: false),
        TocEntry(title: "Figure 4.4: Sensory Filter Effect Composition", page: "16", indent: 0, bold: false),
        TocEntry(title: "Figure 4.5: Foundation Models @Generable Schema Diagram", page: "17", indent: 0, bold: false),
        TocEntry(title: "Figure 5.1: Mode 1 - Classroom Scene Layout", page: "19", indent: 0, bold: false),
        TocEntry(title: "Figure 5.2: Mode 2 - Perspective Reveal 2-Panel Layout", page: "20", indent: 0, bold: false),
        TocEntry(title: "Figure 5.3: Mode 3 - Tone Decoder Three-Page Result Carousel", page: "20", indent: 0, bold: false),
        TocEntry(title: "Figure 5.4: Haptic Pattern Diagrams (Per Filter)", page: "21", indent: 0, bold: false),
        TocEntry(title: "Figure 7.1: Frame-Rate Distribution Under Filter Combinations", page: "24", indent: 0, bold: false),
        TocEntry(title: "Figure 7.2: Foundation Models Latency Histogram", page: "27", indent: 0, bold: false),
    ]

    let tableEntries: [TocEntry] = [
        TocEntry(title: "Table 3.1: Functional Requirements", page: "10", indent: 0, bold: false),
        TocEntry(title: "Table 3.2: Non-Functional Requirements", page: "11", indent: 0, bold: false),
        TocEntry(title: "Table 4.1: Reverb and Distortion Wet/Dry Mix per Sensory Filter", page: "16", indent: 0, bold: false),
        TocEntry(title: "Table 5.1: Classroom Scene - Step-by-Step Filter and Intensity Schedule", page: "19", indent: 0, bold: false),
        TocEntry(title: "Table 5.2: Ambient Noise Synthesis Layer Stack per Sensory Filter", page: "21", indent: 0, bold: false),
        TocEntry(title: "Table 6.1: Unit Test Results", page: "23", indent: 0, bold: false),
        TocEntry(title: "Table 6.2: Accessibility Compliance Checklist", page: "25", indent: 0, bold: false),
        TocEntry(title: "Table 7.1: Performance Metrics Across Test Devices", page: "26", indent: 0, bold: false),
        TocEntry(title: "Table 7.2: Capability Comparison - SpecBridge versus Existing Tools", page: "27", indent: 0, bold: false),
    ]

    var y: CGFloat = 116
    addText(to: page, text: "List of Figures", x: 72, yTop: y, width: 260, height: 22, font: headingFont)
    y += 24
    for entry in figureEntries {
        addText(to: page, text: entry.title, x: 72, yTop: y, width: 400, height: 17, font: bodyFont)
        addText(to: page, text: entry.page, x: 512, yTop: y, width: 30, height: 17, font: bodyFont, alignment: .right)
        y += 14
    }

    y += 18
    addText(to: page, text: "List of Tables", x: 72, yTop: y, width: 260, height: 22, font: headingFont)
    y += 24
    for entry in tableEntries {
        addText(to: page, text: entry.title, x: 72, yTop: y, width: 400, height: 17, font: bodyFont)
        addText(to: page, text: entry.page, x: 512, yTop: y, width: 30, height: 17, font: bodyFont, alignment: .right)
        y += 14
    }
}

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Could not open input PDF\n", stderr)
    exit(1)
}

let xml = try String(contentsOfFile: xmlPath)
let headings = parseColoredHeadings(from: xml)

redrawCoverTitle(on: document)

for heading in headings {
    guard let page = document.page(at: heading.page - 1) else { continue }
    addCoverFromTop(
        to: page,
        x: max(heading.x - 1, 0),
        yTop: heading.yTop - 1,
        width: max(heading.width + 8, 230),
        height: max(heading.height + 5, 20)
    )
    addText(
        to: page,
        text: heading.text,
        x: heading.x,
        yTop: heading.yTop,
        width: max(heading.width + 70, 300),
        height: 22,
        font: headingFont
    )
}

redrawTOC(on: document)
redrawFigureAndTableLists(on: document)

for pageIndex in 0..<document.pageCount {
    guard let page = document.page(at: pageIndex) else { continue }
    addCover(to: page, x: 250, y: 20, width: 120, height: 28)
    if pageIndex == 0 { continue }

    let visibleNumber: String
    if pageIndex <= 9 {
        visibleNumber = roman(pageIndex)
    } else {
        visibleNumber = String(pageIndex - 9)
    }

    addText(to: page, text: visibleNumber, x: 285, yTop: 750, width: 42, height: 18, font: footerFont, alignment: .center)
}

if !document.write(to: URL(fileURLWithPath: outputPath)) {
    fputs("Could not write output PDF\n", stderr)
    exit(1)
}

print("Wrote \(outputPath)")
