import Foundation

func normalizeFoodKey(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
     .lowercased()
     .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
}
