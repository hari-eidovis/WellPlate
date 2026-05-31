import AppKit
import Foundation
import PDFKit

let inputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_no_boundary.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_cleaned.pdf"

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Could not open input PDF\n", stderr)
    exit(1)
}

let normalFont = NSFont(name: "TimesNewRomanPSMT", size: 12)
    ?? NSFont(name: "Times-Roman", size: 12)
    ?? .systemFont(ofSize: 12)

func addWhiteCover(to page: PDFPage, bounds: CGRect) {
    let cover = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
    let border = PDFBorder()
    border.lineWidth = 0
    cover.border = border
    cover.color = .white
    cover.interiorColor = .white
    cover.shouldPrint = true
    page.addAnnotation(cover)
}

func addText(to page: PDFPage, text: String, x: CGFloat, yTop: CGFloat, width: CGFloat, height: CGFloat = 22) {
    let pageHeight = page.bounds(for: .mediaBox).height
    let annotation = PDFAnnotation(
        bounds: CGRect(x: x, y: pageHeight - yTop - height, width: width, height: height),
        forType: .freeText,
        withProperties: nil
    )
    annotation.contents = text
    annotation.font = normalFont
    annotation.fontColor = .black
    annotation.alignment = .left
    annotation.color = .clear
    let border = PDFBorder()
    border.lineWidth = 0
    annotation.border = border
    annotation.shouldPrint = true
    page.addAnnotation(annotation)
}

// Page 3: remove the Declaration signature line.
if let declarationPage = document.page(at: 2) {
    addWhiteCover(to: declarationPage, bounds: CGRect(x: 100, y: 124, width: 220, height: 28))
}

// Page 9: replace the abbreviations table with a plain list.
if let abbreviationsPage = document.page(at: 8) {
    addWhiteCover(to: abbreviationsPage, bounds: CGRect(x: 100, y: 330, width: 445, height: 370))

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
        addText(
            to: abbreviationsPage,
            text: entry,
            x: 108,
            yTop: 122 + CGFloat(index * 21),
            width: 430
        )
    }
}

if !document.write(to: URL(fileURLWithPath: outputPath)) {
    fputs("Could not write output PDF\n", stderr)
    exit(1)
}

print("Wrote \(outputPath)")
