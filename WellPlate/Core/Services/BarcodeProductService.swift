import Foundation

// MARK: - Error

enum BarcodeProductError: LocalizedError {
    case notFound
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .notFound:             return "Product not found."
        case .networkError(let e):  return "Network error: \(e.localizedDescription)"
        case .decodingError:        return "Could not read product data."
        }
    }
}

// MARK: - Value types

struct NutritionPer100g {
    let calories: Double?
    let protein:  Double?
    let carbs:    Double?
    let fat:      Double?
    let fiber:    Double?
}

struct NutritionPerServing {
    let calories: Double?
    let protein:  Double?
    let carbs:    Double?
    let fat:      Double?
    let fiber:    Double?
}

struct BarcodeProduct {
    let barcode:             String
    let productName:         String
    let brandName:           String?
    let servingSize:         String?      // human-readable, e.g. "1 can (355 ml)"
    let servingSizeG:        Double?      // numeric grams from "serving_size_g"
    let nutritionPer100g:    NutritionPer100g?
    let nutritionPerServing: NutritionPerServing?
    let imageURL:            URL?

    /// True when the product has nutrition calorie data (per-serving or per-100g).
    /// A product can still be logged without this — calories will show as 0.
    var isComplete: Bool {
        nutritionPerServing?.calories != nil || nutritionPer100g?.calories != nil
    }
}

// MARK: - Protocol

protocol BarcodeProductServiceProtocol {
    func lookupProduct(barcode: String) async throws -> BarcodeProduct?
}

// MARK: - Implementation

final class BarcodeProductService: BarcodeProductServiceProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookupProduct(barcode: String) async throws -> BarcodeProduct? {
        WPLogger.barcode.info("Lookup: \(barcode)")
        // Try original barcode first; if not found, try stripping leading zeros
        // to handle UPC-A / EAN-13 encoding variants.
        if let product = try await fetchProduct(barcode: barcode) { return product }
        let stripped = String(barcode.drop(while: { $0 == "0" }))
        if !stripped.isEmpty, stripped != barcode {
            WPLogger.barcode.info("Retrying with stripped barcode: \(stripped)")
            return try await fetchProduct(barcode: stripped)
        }
        WPLogger.barcode.warning("Product not found after both attempts — barcode: \(barcode)")
        return nil
    }

    private func fetchProduct(barcode: String) async throws -> BarcodeProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeProductError.decodingError
        }
        WPLogger.barcode.debug("GET \(url)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            WPLogger.barcode.error("Network error: \(error)")
            throw BarcodeProductError.networkError(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        WPLogger.barcode.debug("HTTP \(statusCode) — \(data.count) bytes")
        if statusCode == 404 {
            WPLogger.barcode.info("HTTP 404 — product not found")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            WPLogger.barcode.error("JSON parse failed for barcode: \(barcode)")
            throw BarcodeProductError.decodingError
        }
        // OFF returns status 0 with no "product" key when not found (HTTP 200)
        let offStatus = json["status"] as? Int ?? -1
        guard let product = json["product"] as? [String: Any] else {
            WPLogger.barcode.warning("OFF status: \(offStatus) — no 'product' key in response")
            return nil
        }
        let name = (product["product_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            WPLogger.barcode.warning("Empty product name — returning nil")
            return nil
        }

        let nutriments = product["nutriments"] as? [String: Any]

        let per100g = NutritionPer100g(
            calories: doubleValue(nutriments, key: "energy-kcal_100g"),
            protein:  doubleValue(nutriments, key: "proteins_100g"),
            carbs:    doubleValue(nutriments, key: "carbohydrates_100g"),
            fat:      doubleValue(nutriments, key: "fat_100g"),
            fiber:    doubleValue(nutriments, key: "fiber_100g")
        )
        let perServing = NutritionPerServing(
            calories: doubleValue(nutriments, key: "energy-kcal_serving"),
            protein:  doubleValue(nutriments, key: "proteins_serving"),
            carbs:    doubleValue(nutriments, key: "carbohydrates_serving"),
            fat:      doubleValue(nutriments, key: "fat_serving"),
            fiber:    doubleValue(nutriments, key: "fiber_serving")
        )

        let result = BarcodeProduct(
            barcode:             barcode,
            productName:         name,
            brandName:           product["brands"]        as? String,
            servingSize:         product["serving_size"]  as? String,
            servingSizeG:        product["serving_size_g"] as? Double,
            nutritionPer100g:    per100g,
            nutritionPerServing: perServing,
            imageURL:            (product["image_url"] as? String).flatMap(URL.init)
        )
        WPLogger.barcode.block(emoji: "✅", title: "PRODUCT FOUND", lines: [
            "Name   : \(name)",
            "Brand  : \(result.brandName ?? "unknown")",
            "Complete: \(result.isComplete ? "yes — has calorie data" : "no — missing nutrition")",
            "Per 100g: \(per100g.calories.map { "\($0) kcal" } ?? "n/a")",
            "Per Svng: \(perServing.calories.map { "\($0) kcal" } ?? "n/a")"
        ])
        return result
    }

    /// Reads a nutriments dictionary value as Double, falling back to Int → Double
    /// because Open Food Facts sometimes returns numeric fields as Int.
    private func doubleValue(_ dict: [String: Any]?, key: String) -> Double? {
        guard let dict else { return nil }
        if let d = dict[key] as? Double { return d }
        if let i = dict[key] as? Int    { return Double(i) }
        return nil
    }
}
