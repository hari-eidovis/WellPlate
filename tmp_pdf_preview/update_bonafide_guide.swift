import AppKit
import Foundation
import PDFKit

let inputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_toc_corrected.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_final.pdf"

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)),
      let page = document.page(at: 1) else {
    fputs("Could not open Bonafide page\n", stderr)
    exit(1)
}

let mediaBox = page.bounds(for: .mediaBox)
let normalFont = NSFont(name: "TimesNewRomanPSMT", size: 12) ?? NSFont(name: "Times-Roman", size: 12) ?? .systemFont(ofSize: 12)

let cover = PDFAnnotation(
    bounds: CGRect(x: 95, y: 70, width: 220, height: 170),
    forType: .square,
    withProperties: nil
)
let coverBorder = PDFBorder()
coverBorder.lineWidth = 0
cover.border = coverBorder
cover.color = .white
cover.interiorColor = .white
cover.shouldPrint = true
page.addAnnotation(cover)

let lines: [(String, CGFloat)] = [
    ("Project Guide", 600),
    ("Mr. Ashwini Kumar", 632),
    ("Assistant Professor", 664),
    ("May 27, 2026", 682),
    ("FET,Haridwar", 700),
    ("Signature ___________", 732),
]

for (content, yTop) in lines {
    let rect = CGRect(
        x: 108,
        y: mediaBox.height - yTop - 16,
        width: 220,
        height: 20
    )
    let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
    annotation.contents = content
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

if !document.write(to: URL(fileURLWithPath: outputPath)) {
    fputs("Could not write output PDF\n", stderr)
    exit(1)
}

print("Wrote \(outputPath)")
