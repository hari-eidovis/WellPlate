import AppKit
import Foundation
import PDFKit

struct TocNumber {
    let page: Int
    let yMin: CGFloat
    let yMax: CGFloat
    let text: String
    let bold: Bool
}

let inputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_bordered.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_toc_corrected.pdf"

let entries: [TocNumber] = [
    // Page 6
    TocNumber(page: 6, yMin: 222.2, yMax: 235.5, text: "9", bold: false),
    TocNumber(page: 6, yMin: 244.0, yMax: 257.3, text: "10", bold: false),
    TocNumber(page: 6, yMin: 265.9, yMax: 279.2, text: "11", bold: true),
    TocNumber(page: 6, yMin: 283.8, yMax: 297.1, text: "11", bold: false),
    TocNumber(page: 6, yMin: 301.2, yMax: 314.4, text: "11", bold: false),
    TocNumber(page: 6, yMin: 318.5, yMax: 331.8, text: "12", bold: false),
    TocNumber(page: 6, yMin: 335.9, yMax: 349.2, text: "12", bold: false),
    TocNumber(page: 6, yMin: 353.3, yMax: 366.5, text: "13", bold: false),
    TocNumber(page: 6, yMin: 370.6, yMax: 383.9, text: "13", bold: false),
    TocNumber(page: 6, yMin: 388.0, yMax: 401.3, text: "14", bold: false),
    TocNumber(page: 6, yMin: 409.9, yMax: 423.1, text: "15", bold: true),
    TocNumber(page: 6, yMin: 427.7, yMax: 441.0, text: "15", bold: false),
    TocNumber(page: 6, yMin: 445.1, yMax: 458.4, text: "15", bold: false),
    TocNumber(page: 6, yMin: 462.5, yMax: 475.8, text: "16", bold: false),
    TocNumber(page: 6, yMin: 479.8, yMax: 493.1, text: "17", bold: false),
    TocNumber(page: 6, yMin: 497.2, yMax: 510.5, text: "17", bold: false),
    TocNumber(page: 6, yMin: 514.6, yMax: 527.9, text: "18", bold: false),
    TocNumber(page: 6, yMin: 531.9, yMax: 545.2, text: "18", bold: false),
    TocNumber(page: 6, yMin: 549.3, yMax: 562.6, text: "18", bold: false),
    TocNumber(page: 6, yMin: 571.2, yMax: 584.5, text: "20", bold: true),
    TocNumber(page: 6, yMin: 589.0, yMax: 602.3, text: "20", bold: false),
    TocNumber(page: 6, yMin: 606.4, yMax: 619.7, text: "20", bold: false),
    TocNumber(page: 6, yMin: 623.8, yMax: 637.1, text: "20", bold: false),
    TocNumber(page: 6, yMin: 641.2, yMax: 654.4, text: "21", bold: false),
    TocNumber(page: 6, yMin: 658.5, yMax: 671.8, text: "21", bold: false),
    TocNumber(page: 6, yMin: 675.9, yMax: 689.2, text: "21", bold: false),

    // Page 7
    TocNumber(page: 7, yMin: 72.5, yMax: 85.8, text: "23", bold: false),
    TocNumber(page: 7, yMin: 89.9, yMax: 103.2, text: "23", bold: false),
    TocNumber(page: 7, yMin: 107.2, yMax: 120.5, text: "24", bold: false),
    TocNumber(page: 7, yMin: 124.6, yMax: 137.9, text: "24", bold: false),
    TocNumber(page: 7, yMin: 142.0, yMax: 155.3, text: "24", bold: false),
    TocNumber(page: 7, yMin: 159.4, yMax: 172.6, text: "25", bold: false),
    TocNumber(page: 7, yMin: 176.7, yMax: 190.0, text: "25", bold: false),
    TocNumber(page: 7, yMin: 198.6, yMax: 211.9, text: "27", bold: true),
    TocNumber(page: 7, yMin: 216.5, yMax: 229.7, text: "27", bold: false),
    TocNumber(page: 7, yMin: 233.8, yMax: 247.1, text: "28", bold: false),
    TocNumber(page: 7, yMin: 251.2, yMax: 264.5, text: "28", bold: false),
    TocNumber(page: 7, yMin: 268.6, yMax: 281.9, text: "29", bold: false),
    TocNumber(page: 7, yMin: 285.9, yMax: 299.2, text: "29", bold: false),
    TocNumber(page: 7, yMin: 303.3, yMax: 316.6, text: "30", bold: false),
    TocNumber(page: 7, yMin: 320.7, yMax: 334.0, text: "30", bold: false),
    TocNumber(page: 7, yMin: 342.5, yMax: 355.8, text: "32", bold: true),
    TocNumber(page: 7, yMin: 360.4, yMax: 373.7, text: "32", bold: false),
    TocNumber(page: 7, yMin: 377.8, yMax: 391.1, text: "32", bold: false),
    TocNumber(page: 7, yMin: 395.1, yMax: 408.4, text: "33", bold: false),
    TocNumber(page: 7, yMin: 412.5, yMax: 425.8, text: "33", bold: false),
    TocNumber(page: 7, yMin: 429.9, yMax: 443.2, text: "34", bold: false),
    TocNumber(page: 7, yMin: 447.3, yMax: 460.5, text: "34", bold: false),
    TocNumber(page: 7, yMin: 464.6, yMax: 477.9, text: "34", bold: false),
    TocNumber(page: 7, yMin: 482.0, yMax: 495.3, text: "34", bold: false),
    TocNumber(page: 7, yMin: 499.4, yMax: 512.6, text: "35", bold: false),
    TocNumber(page: 7, yMin: 516.7, yMax: 530.0, text: "35", bold: false),
    TocNumber(page: 7, yMin: 534.1, yMax: 547.4, text: "36", bold: false),
    TocNumber(page: 7, yMin: 556.0, yMax: 569.2, text: "37", bold: true),
    TocNumber(page: 7, yMin: 573.8, yMax: 587.1, text: "37", bold: false),
    TocNumber(page: 7, yMin: 591.2, yMax: 604.5, text: "37", bold: false),
    TocNumber(page: 7, yMin: 608.6, yMax: 621.9, text: "37", bold: false),
    TocNumber(page: 7, yMin: 625.9, yMax: 639.2, text: "38", bold: false),
    TocNumber(page: 7, yMin: 643.3, yMax: 656.6, text: "38", bold: false),
    TocNumber(page: 7, yMin: 665.2, yMax: 678.5, text: "39", bold: true),
    TocNumber(page: 7, yMin: 683.0, yMax: 696.3, text: "39", bold: false),

    // Page 8
    TocNumber(page: 8, yMin: 72.5, yMax: 85.8, text: "39", bold: false),
    TocNumber(page: 8, yMin: 137.5, yMax: 150.8, text: "39", bold: false),
    TocNumber(page: 8, yMin: 154.9, yMax: 168.1, text: "40", bold: false),
    TocNumber(page: 8, yMin: 172.2, yMax: 185.5, text: "41", bold: false),
    TocNumber(page: 8, yMin: 189.6, yMax: 202.9, text: "41", bold: false),
    TocNumber(page: 8, yMin: 207.0, yMax: 220.2, text: "42", bold: false),
    TocNumber(page: 8, yMin: 224.3, yMax: 237.6, text: "42", bold: false),
    TocNumber(page: 8, yMin: 246.2, yMax: 259.5, text: "43", bold: true),
    TocNumber(page: 8, yMin: 264.1, yMax: 277.4, text: "43", bold: false),
    TocNumber(page: 8, yMin: 281.4, yMax: 294.7, text: "43", bold: false),
    TocNumber(page: 8, yMin: 303.3, yMax: 316.6, text: "45", bold: true),
]

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Could not open input PDF\n", stderr)
    exit(1)
}

let normalFont = NSFont(name: "TimesNewRomanPSMT", size: 12) ?? NSFont(name: "Times-Roman", size: 12) ?? .systemFont(ofSize: 12)
let boldFont = NSFont(name: "TimesNewRomanPS-BoldMT", size: 12) ?? NSFont(name: "Times-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)

for entry in entries {
    guard let page = document.page(at: entry.page - 1) else { continue }
    let mediaBox = page.bounds(for: .mediaBox)
    let clearRect = CGRect(
        x: 522,
        y: mediaBox.height - entry.yMax - 2,
        width: 23,
        height: (entry.yMax - entry.yMin) + 4
    )

    let cover = PDFAnnotation(bounds: clearRect, forType: .square, withProperties: nil)
    let coverBorder = PDFBorder()
    coverBorder.lineWidth = 0
    cover.border = coverBorder
    cover.color = .white
    cover.interiorColor = .white
    cover.shouldPrint = true
    page.addAnnotation(cover)

    let textRect = CGRect(
        x: 508,
        y: mediaBox.height - entry.yMax - 2,
        width: 32,
        height: (entry.yMax - entry.yMin) + 5
    )
    let text = PDFAnnotation(bounds: textRect, forType: .freeText, withProperties: nil)
    text.contents = entry.text
    text.font = entry.bold ? boldFont : normalFont
    text.fontColor = .black
    text.alignment = .right
    text.color = .clear
    let textBorder = PDFBorder()
    textBorder.lineWidth = 0
    text.border = textBorder
    text.shouldPrint = true
    page.addAnnotation(text)
}

if !document.write(to: URL(fileURLWithPath: outputPath)) {
    fputs("Could not write output PDF\n", stderr)
    exit(1)
}

print("Wrote \(outputPath) with \(entries.count) corrected TOC page numbers")
