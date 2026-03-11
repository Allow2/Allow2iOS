import Foundation

/// Errors that can occur within the Allow2 Device SDK.
public enum Allow2Error: Error, Sendable {

    /// The device is not paired. Pairing must be completed first.
    case notPaired

    /// The device is already paired. Unpair before re-pairing.
    case alreadyPaired

    /// No child has been selected for enforcement.
    case missingChildId

    /// The server returned HTTP 401 -- credentials have been invalidated.
    /// The device should be considered unpaired.
    case notAuthorised

    /// The server returned a response that could not be decoded.
    case invalidResponse

    /// A network-level error occurred (no connectivity, DNS failure, etc.).
    case networkError(Error)

    /// The API returned an error with an optional message and HTTP status code.
    case apiError(message: String, code: Int?)

    /// The child's PIN entry is locked due to too many failed attempts.
    case pinLocked(remainingSeconds: Int)

    /// The request timed out.
    case timeout
}

extension Allow2Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notPaired:
            return "Device is not paired. Complete pairing first."
        case .alreadyPaired:
            return "Device is already paired."
        case .missingChildId:
            return "No child selected."
        case .notAuthorised:
            return "Credentials invalidated. Device has been released."
        case .invalidResponse:
            return "Invalid response from server."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .apiError(let message, let code):
            if let code = code {
                return "API error \(code): \(message)"
            }
            return "API error: \(message)"
        case .pinLocked(let seconds):
            return "PIN locked. Try again in \(seconds) seconds."
        case .timeout:
            return "Request timed out."
        }
    }
}
