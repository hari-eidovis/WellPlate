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
        print("[BarcodeProductService] lookupProduct: \(barcode)")
        // Try original barcode first; if not found, try stripping leading zeros
        // to handle UPC-A / EAN-13 encoding variants.
        if let product = try await fetchProduct(barcode: barcode) { return product }
        let stripped = String(barcode.drop(while: { $0 == "0" }))
        if !stripped.isEmpty, stripped != barcode {
            print("[BarcodeProductService] retrying with stripped barcode: \(stripped)")
            return try await fetchProduct(barcode: stripped)
        }
        print("[BarcodeProductService] product not found after both attempts")
        return nil
    }

    private func fetchProduct(barcode: String) async throws -> BarcodeProduct? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeProductError.decodingError
        }
        print("[BarcodeProductService] GET \(url)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            print("[BarcodeProductService] ❌ network error: \(error)")
            throw BarcodeProductError.networkError(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[BarcodeProductService] HTTP \(statusCode) — \(data.count) bytes")
        if statusCode == 404 {
            print("[BarcodeProductService] 404 — returning nil")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[BarcodeProductService] ❌ JSON parse failed")
            throw BarcodeProductError.decodingError
        }
        // OFF returns status 0 with no "product" key when not found (HTTP 200)
        let offStatus = json["status"] as? Int ?? -1
        print("[BarcodeProductService] OFF status: \(offStatus)")
        guard let product = json["product"] as? [String: Any] else {
            print("[BarcodeProductService] no 'product' key in response — not found")
            return nil
        }
        let name = (product["product_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        print("[BarcodeProductService] product_name: '\(name)'")
        guard !name.isEmpty else {
            print("[BarcodeProductService] empty product name — returning nil")
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
        print("[BarcodeProductService] ✅ parsed product: '\(name)' | brand: \(result.brandName ?? "nil") | isComplete: \(result.isComplete) | per100g.cal: \(per100g.calories as Any) | perServing.cal: \(perServing.calories as Any)")
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
