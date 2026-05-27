import AppKit
import Foundation
import PDFKit

struct TocEntry {
    let title: String
    let page: String
    let indent: CGFloat
    let bold: Bool
}

struct BlueHeading {
    let page: Int
    let x: CGFloat
    let yTop: CGFloat
    let width: CGFloat
    let height: CGFloat
    let text: String
}

let inputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_cleaned.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_format_fixed_safe.pdf"
let xmlPath = "/Users/hariom/Desktop/WellPlate/tmp_pdf_preview/cleaned_full_xml.xml"

let scale: CGFloat = 1.5
let pageHeight: CGFloat = 792

let normalFont = NSFont(name: "TimesNewRomanPSMT", size: 12)
    ?? NSFont(name: "Times-Roman", size: 12)
    ?? .systemFont(ofSize: 12)
let boldFont = NSFont(name: "TimesNewRomanPS-BoldMT", size: 14)
    ?? NSFont(name: "Times-Bold", size: 14)
    ?? .boldSystemFont(ofSize: 14)
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

func addText(
    to page: PDFPage,
    text: String,
    x: CGFloat,
    yTop: CGFloat,
    width: CGFloat,
    height: CGFloat,
    font: NSFont,
    alignment: NSTextAlignment = .left
) {
    let annotation = PDFAnnotation(
        bounds: CGRect(x: x, y: pageHeight - yTop - height, width: width, height: height),
        forType: .freeText,
        withProperties: nil
    )
    annotation.contents = text
    annotation.font = font
    annotation.fontColor = .black
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
    let frontMatterTitles: Set<String> = [
        "Bonafide Certificate",
        "Declaration",
        "Acknowledgement",
        "Executive Summary",
        "Abstract",
        "List of Abbreviations",
    ]
    if frontMatterTitles.contains(text) {
        return true
    }
    if text.range(of: #"^Chapter [0-9]+:"#, options: .regularExpression) != nil {
        return true
    }
    return text.range(of: #"^[0-9]+(\.[0-9]+)+\s+\S"#, options: .regularExpression) != nil
}

func parseBlueHeadings(from xml: String) -> [BlueHeading] {
    let lines = xml.components(separatedBy: .newlines)
    let fontSpecPattern = #"<fontspec id=\"([0-9]+)\" size=\"[^\"]+\" family=\"[^\"]+\" color=\"([^\"]+)\"/>"#
    let textPattern = #"<text top=\"([0-9.]+)\" left=\"([0-9.]+)\" width=\"([0-9.]+)\" height=\"([0-9.]+)\" font=\"([0-9]+)\">(.*)</text>"#
    let fontRegex = try! NSRegularExpression(pattern: fontSpecPattern)
    let textRegex = try! NSRegularExpression(pattern: textPattern)

    var currentPage = 0
    var blueFonts = Set<String>()
    var result: [BlueHeading] = []

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
            if color == "#1f3864" || color == "#2e74b5" {
                blueFonts.insert(id)
            }
        }

        guard currentPage > 1, !(6...8).contains(currentPage) else { continue }
        if let match = textRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
            let fontId = nsLine.substring(with: match.range(at: 5))
            guard blueFonts.contains(fontId) else { continue }
            let text = decodeXMLText(nsLine.substring(with: match.range(at: 6)))
            guard !text.isEmpty else { continue }
            guard isReportHeadingText(text) else { continue }
            let top = CGFloat(Double(nsLine.substring(with: match.range(at: 1))) ?? 0) / scale
            let left = CGFloat(Double(nsLine.substring(with: match.range(at: 2))) ?? 0) / scale
            let width = CGFloat(Double(nsLine.substring(with: match.range(at: 3))) ?? 0) / scale
            let height = CGFloat(Double(nsLine.substring(with: match.range(at: 4))) ?? 0) / scale
            result.append(BlueHeading(page: currentPage, x: left, yTop: top, width: width, height: height, text: text))
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

func redrawTOC(on document: PDFDocument) {
    let entries: [TocEntry] = [
        TocEntry(title: "Bonafide Certificate", page: "i", indent: 0, bold: false),
        TocEntry(title: "Declaration", page: "ii", indent: 0, bold: false),
        TocEntry(title: "Acknowledgement", page: "iii", indent: 0, bold: false),
        TocEntry(title: "Executive Summary", page: "iv", indent: 0, bold: false),
        TocEntry(title: "Table of Contents", page: "v", indent: 0, bold: false),
        TocEntry(title: "List of Abbreviations", page: "viii", indent: 0, bold: false),
        TocEntry(title: "Abstract", page: "ix", indent: 0, bold: false),
        TocEntry(title: "Chapter 1: Introduction", page: "1", indent: 0, bold: true),
        TocEntry(title: "1.1 Background and Context", page: "1", indent: 20, bold: false),
        TocEntry(title: "1.2 Motivation", page: "1", indent: 20, bold: false),
        TocEntry(title: "1.3 Problem Statement", page: "2", indent: 20, bold: false),
        TocEntry(title: "1.4 Aim and Objectives", page: "2", indent: 20, bold: false),
        TocEntry(title: "1.5 Scope of the Project", page: "3", indent: 20, bold: false),
        TocEntry(title: "1.6 Principal Contributions", page: "3", indent: 20, bold: false),
        TocEntry(title: "1.7 Organisation of the Report", page: "4", indent: 20, bold: false),
        TocEntry(title: "Chapter 2: System Study and Literature Review", page: "5", indent: 0, bold: true),
        TocEntry(title: "2.1 Stress: Physiology and Measurement", page: "5", indent: 20, bold: false),
        TocEntry(title: "2.2 Heart-Rate Variability as a Stress Biomarker", page: "5", indent: 20, bold: false),
        TocEntry(title: "2.3 Multimodal and Behavioural Stress Detection", page: "6", indent: 20, bold: false),
        TocEntry(title: "2.4 The Scientific Basis of the Behavioural Drivers", page: "7", indent: 20, bold: false),
        TocEntry(title: "2.5 Explainable and Transparent Algorithms in Health", page: "7", indent: 20, bold: false),
        TocEntry(title: "2.6 Mobile Health and Just-in-Time Adaptive Interventions", page: "8", indent: 20, bold: false),
        TocEntry(title: "2.7 Existing Systems and Commercial Comparators", page: "8", indent: 20, bold: false),
        TocEntry(title: "2.8 Research Gap", page: "8", indent: 20, bold: false),
        TocEntry(title: "Chapter 3: System Analysis", page: "10", indent: 0, bold: true),
        TocEntry(title: "3.1 Requirement Analysis", page: "10", indent: 20, bold: false),
        TocEntry(title: "3.1.1 Functional Requirements", page: "10", indent: 40, bold: false),
        TocEntry(title: "3.1.2 Non-Functional Requirements", page: "10", indent: 40, bold: false),
        TocEntry(title: "3.2 Feasibility Study", page: "11", indent: 20, bold: false),
        TocEntry(title: "3.3 The Stress Scoring v3 Algorithm", page: "11", indent: 20, bold: false),
        TocEntry(title: "3.3.1 Driver Tiers", page: "11", indent: 40, bold: false),
        TocEntry(title: "3.3.2 Justification of Individual Drivers", page: "13", indent: 40, bold: false),
        TocEntry(title: "3.3.3 Modifiers", page: "13", indent: 40, bold: false),
        TocEntry(title: "3.3.4 Final Score Formula", page: "14", indent: 40, bold: false),
        TocEntry(title: "3.3.5 Confidence Estimation", page: "14", indent: 40, bold: false),
        TocEntry(title: "3.3.6 Why Tier-Weighting Rather Than Averaging", page: "14", indent: 40, bold: false),
        TocEntry(title: "3.3.7 Determinism and Auditability", page: "15", indent: 40, bold: false),
        TocEntry(title: "3.3.8 Worked Example", page: "15", indent: 40, bold: false),
        TocEntry(title: "Chapter 4: System Design and Model Design", page: "17", indent: 0, bold: true),
        TocEntry(title: "4.1 Architectural Overview", page: "17", indent: 20, bold: false),
        TocEntry(title: "4.2 Design Patterns", page: "18", indent: 20, bold: false),
        TocEntry(title: "4.3 Navigation Model", page: "18", indent: 20, bold: false),
        TocEntry(title: "4.4 Data Model", page: "19", indent: 20, bold: false),
        TocEntry(title: "4.5 Score-to-Level Mapping and Visual Design", page: "19", indent: 20, bold: false),
        TocEntry(title: "4.6 Concurrency and Error-Handling Design", page: "20", indent: 20, bold: false),
        TocEntry(title: "4.7 Daily Update Sequence", page: "20", indent: 20, bold: false),
        TocEntry(title: "Chapter 5: System Implementation", page: "22", indent: 0, bold: true),
        TocEntry(title: "5.1 Technology Stack", page: "22", indent: 20, bold: false),
        TocEntry(title: "5.2 Implementation of the Scoring Pipeline", page: "22", indent: 20, bold: false),
        TocEntry(title: "5.3 External Integrations", page: "23", indent: 20, bold: false),
        TocEntry(title: "5.3.1 HealthKit", page: "23", indent: 40, bold: false),
        TocEntry(title: "5.3.2 DeviceActivity (Screen Time)", page: "24", indent: 40, bold: false),
        TocEntry(title: "5.3.3 ActivityKit Live Activities", page: "24", indent: 40, bold: false),
        TocEntry(title: "5.3.4 Large-Language-Model Nutrition Parsing", page: "24", indent: 40, bold: false),
        TocEntry(title: "5.4 Project Structure", page: "24", indent: 20, bold: false),
        TocEntry(title: "5.5 Entitlements and Privacy Posture", page: "25", indent: 20, bold: false),
        TocEntry(title: "5.6 Development Workflow", page: "25", indent: 20, bold: false),
        TocEntry(title: "5.7 Food Logging and the Insight Engine", page: "26", indent: 20, bold: false),
        TocEntry(title: "Chapter 6: Testing", page: "27", indent: 0, bold: true),
        TocEntry(title: "6.1 Testing Strategy", page: "27", indent: 20, bold: false),
        TocEntry(title: "6.2 Unit Test Coverage", page: "27", indent: 20, bold: false),
        TocEntry(title: "6.3 Determinism as a Testability Property", page: "27", indent: 20, bold: false),
        TocEntry(title: "6.4 Test Scenarios", page: "28", indent: 20, bold: false),
        TocEntry(title: "6.5 Limitations of the Current Test Suite", page: "28", indent: 20, bold: false),
        TocEntry(title: "Chapter 7: Results and Discussion", page: "29", indent: 0, bold: true),
        TocEntry(title: "7.1 Functional Outcomes", page: "29", indent: 20, bold: false),
        TocEntry(title: "7.2 The Explainability Outcome", page: "29", indent: 20, bold: false),
        TocEntry(title: "7.3 Illustrative Stress Trajectory", page: "29", indent: 20, bold: false),
        TocEntry(title: "7.4 Comparison with Commercial Systems", page: "30", indent: 20, bold: false),
        TocEntry(title: "7.5 Discussion: Multimodal Fusion versus Single-Signal Scoring", page: "31", indent: 20, bold: false),
        TocEntry(title: "7.6 Discussion: Determinism, Privacy, and Trust", page: "31", indent: 20, bold: false),
        TocEntry(title: "7.7 Threats to Validity and Limitations", page: "32", indent: 20, bold: false),
        TocEntry(title: "7.8 Realised User-Facing Surfaces", page: "32", indent: 20, bold: false),
        TocEntry(title: "Chapter 8: Conclusion and Future Scope", page: "33", indent: 0, bold: true),
        TocEntry(title: "8.1 Conclusion", page: "33", indent: 20, bold: false),
        TocEntry(title: "8.2 Future Scope", page: "33", indent: 20, bold: false),
        TocEntry(title: "Chapter 9: References", page: "35", indent: 0, bold: true),
    ]

    let pageSplits = [31, 67, entries.count]
    var start = 0
    for tocPageNumber in 6...8 {
        guard let page = document.page(at: tocPageNumber - 1) else { continue }
        addCover(to: page, x: 90, y: 58, width: 458, height: 660)
        addText(to: page, text: tocPageNumber == 6 ? "Table of Contents" : "", x: 108, yTop: 72, width: 360, height: 28, font: boldFont)
        let end = pageSplits[tocPageNumber - 6]
        var y: CGFloat = tocPageNumber == 6 ? 112 : 72
        for entry in entries[start..<end] {
            addText(to: page, text: entry.title, x: 108 + entry.indent, yTop: y, width: 375 - entry.indent, height: 18, font: entry.bold ? boldFont : normalFont)
            addText(to: page, text: entry.page, x: 502, yTop: y, width: 38, height: 18, font: entry.bold ? boldFont : normalFont, alignment: .right)
            y += entry.bold ? 20 : 18
        }
        start = end
    }
}

func redrawAbbreviationsList(on document: PDFDocument) {
    guard let page = document.page(at: 8) else { return }
    addCover(to: page, x: 92, y: 320, width: 455, height: 360)

    let entries = [
        "API: Application Programming Interface",
        "CoreML: Apple's on-device machine-learning framework",
        "HPA axis: Hypothalamic-Pituitary-Adrenal axis",
        "HRV: Heart-Rate Variability",
        "JITAI: Just-In-Time Adaptive Intervention",
        "LLM: Large Language Model",
        "mHealth: Mobile Health",
        "MVVM: Model-View-ViewModel (architectural pattern)",
        "NLP: Natural-Language Processing",
        "PSS: Perceived Stress Scale",
        "RHR: Resting Heart Rate",
        "RMSSD: Root Mean Square of Successive Differences (an HRV measure)",
        "SDNN: Standard Deviation of Normal-to-Normal intervals (an HRV measure)",
        "UI / UX: User Interface / User Experience",
        "XAI: Explainable Artificial Intelligence",
    ]

    for (index, entry) in entries.enumerated() {
        addText(to: page, text: entry, x: 108, yTop: 122 + CGFloat(index * 21), width: 430, height: 22, font: normalFont)
    }
}

func removeDeclarationSignature(on document: PDFDocument) {
    guard let page = document.page(at: 2) else { return }
    addCover(to: page, x: 96, y: 116, width: 240, height: 38)
}

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Could not open input PDF\n", stderr)
    exit(1)
}

let xml = try String(contentsOfFile: xmlPath)
let headings = parseBlueHeadings(from: xml)

for heading in headings {
    guard let page = document.page(at: heading.page - 1) else { continue }
    addCover(
        to: page,
        x: max(heading.x - 1, 0),
        y: pageHeight - heading.yTop - heading.height - 2,
        width: heading.width + 6,
        height: max(heading.height + 4, 20)
    )
    addText(
        to: page,
        text: heading.text,
        x: heading.x,
        yTop: heading.yTop,
        width: max(heading.width + 60, 320),
        height: 24,
        font: boldFont
    )
}

redrawTOC(on: document)
redrawAbbreviationsList(on: document)
removeDeclarationSignature(on: document)

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
