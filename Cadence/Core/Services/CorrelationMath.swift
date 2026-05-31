import Foundation

// MARK: - CorrelationMath
//
// Shared Spearman rank correlation + bootstrap CI utilities.
// Extracted from SymptomCorrelationEngine; also used by InsightEngine.
// All functions are nonisolated static for use in Task.detached contexts.
//
// File order matters: ranks → pearsonR → spearmanR → bootstrapCI → interpretationLabel
// (bootstrapCI calls spearmanR internally; bare name resolves within the same enum scope)

enum CorrelationMath {

    // MARK: - Ranks

    nonisolated private static func ranks(of values: [Double]) -> [Double] {
        let n = values.count
        let indexed = values.enumerated().sorted { $0.element < $1.element }
        var result = [Double](repeating: 0, count: n)

        var i = 0
        while i < n {
            var j = i
            while j < n - 1 && indexed[j].element == indexed[j + 1].element { j += 1 }
            let avgRank = Double(i + j) / 2.0 + 1.0
            for k in i...j {
                result[indexed[k].offset] = avgRank
            }
            i = j + 1
        }
        return result
    }

    // MARK: - Pearson R

    nonisolated private static func pearsonR(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        let xBar = x.reduce(0, +) / n
        let yBar = y.reduce(0, +) / n
        let num = zip(x, y).reduce(0.0) { $0 + ($1.0 - xBar) * ($1.1 - yBar) }
        let dxSq = x.reduce(0.0) { $0 + pow($1 - xBar, 2) }
        let dySq = y.reduce(0.0) { $0 + pow($1 - yBar, 2) }
        let denom = sqrt(dxSq * dySq)
        guard denom > 0 else { return 0 }
        return max(-1, min(1, num / denom))
    }

    // MARK: - Spearman Rank Correlation

    nonisolated static func spearmanR(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        let rx = ranks(of: x)
        let ry = ranks(of: y)
        return pearsonR(rx, ry)
    }

    // MARK: - Bootstrap CI (95%)

    nonisolated static func bootstrapCI(
        xValues: [Double],
        yValues: [Double],
        iterations: Int = 1000
    ) -> (low: Double, high: Double) {
        let pairs = Array(zip(xValues, yValues))
        let n = pairs.count
        var rValues: [Double] = []
        rValues.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let sample = (0..<n).map { _ in pairs.randomElement()! }
            let sX = sample.map(\.0)
            let sY = sample.map(\.1)
            rValues.append(spearmanR(sX, sY))
        }

        rValues.sort()
        let lo = Int(Double(iterations) * 0.025)
        let hi = Int(Double(iterations) * 0.975)
        return (rValues[lo], rValues[hi])
    }

    // MARK: - Interpretation

    nonisolated static func interpretationLabel(r: Double, ciSpansZero: Bool) -> String {
        if ciSpansZero { return "No clear pattern (yet)" }
        let direction = r > 0 ? "positive" : "negative"
        let strength: String
        switch abs(r) {
        case 0..<0.3: strength = "weak"
        case 0.3..<0.6: strength = "moderate"
        default: strength = "strong"
        }
        return "\(strength) \(direction) association"
    }
}
