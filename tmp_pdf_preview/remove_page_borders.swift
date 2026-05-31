import Foundation
import PDFKit

let inputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_final.pdf"
let outputPath = "/Users/hariom/Desktop/WellPlate/Cadence_Project_Report_Hariom-2_no_boundary.pdf"

guard let document = PDFDocument(url: URL(fileURLWithPath: inputPath)) else {
    fputs("Could not open input PDF\n", stderr)
    exit(1)
}

var removed = 0

for pageIndex in 0..<document.pageCount {
    guard let page = document.page(at: pageIndex) else { continue }
    let mediaBox = page.bounds(for: .mediaBox)

    for annotation in page.annotations {
        let bounds = annotation.bounds
        let isPageBorder =
            annotation.type == "Square" &&
            abs(bounds.minX - 24) < 1 &&
            abs(bounds.minY - 24) < 1 &&
            abs(bounds.width - (mediaBox.width - 48)) < 1 &&
            abs(bounds.height - (mediaBox.height - 48)) < 1

        if isPageBorder {
            page.removeAnnotation(annotation)
            removed += 1
        }
    }
}

if !document.write(to: URL(fileURLWithPath: outputPath)) {
    fputs("Could not write output PDF\n", stderr)
    exit(1)
}

print("Wrote \(outputPath); removed \(removed) page-border annotations")
