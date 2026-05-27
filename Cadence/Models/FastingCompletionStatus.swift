import Foundation

/// Completion status for a FastingSession. Persisted as the raw string on
/// `FastingSession.completionStatus`. The legacy `completed: Bool` field is
/// kept alongside for backward compatibility; `resolvedStatus` derives the
/// canonical value with a sensible fallback for rows from before this model.
enum FastingCompletionStatus: String, Codable {
    case completed
    case endedEarly
    case overachieved
    case autoCappedAt24h
}

extension FastingSession {
    /// Canonical status, preferring the new `completionStatus` field and
    /// falling back to the legacy `completed: Bool` for rows written before
    /// the v1 schema additions.
    var resolvedStatus: FastingCompletionStatus {
        if let raw = completionStatus, let s = FastingCompletionStatus(rawValue: raw) {
            return s
        }
        return completed ? .completed : .endedEarly
    }
}
