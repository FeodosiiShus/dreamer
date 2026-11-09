//
//  RegistryManagerError.swift
//  Dreamder
//
//  Created by Abe Malla on 5/12/25.
//

import Foundation

nonisolated enum RegistryManagerError: Error, LocalizedError {
    case installationRunning
    case invalidResponse(statusCode: Int)
    case downloadFailed(url: URL, error: Error)
    case maxRetriesExceeded(url: URL, lastError: Error)
    case writeFailed(error: Error)
    case failedToSaveRegistryCache
    case checksumMissing(file: String)
    case checksumMismatch(file: String)

    var errorDescription: String? {
        switch self {
        case .installationRunning:
            "A package is already being installed."
        case .invalidResponse(let statusCode):
            "Invalid response received: \(statusCode)"
        case .downloadFailed(let url, _):
            "Download for \(url) error."
        case .maxRetriesExceeded(let url, _):
            "Maximum retries exceeded for url: \(url)"
        case .writeFailed:
            "Failed to write to file."
        case .failedToSaveRegistryCache:
            "Failed to write to registry cache."
        case .checksumMissing(let file):
            "No checksum was published for \(file)."
        case .checksumMismatch(let file):
            "The downloaded \(file) does not match its published checksum."
        }
    }

    var failureReason: String? {
        switch self {
        case .installationRunning, .invalidResponse, .failedToSaveRegistryCache, .checksumMissing, .checksumMismatch:
            return nil
        case .downloadFailed(_, let error), .maxRetriesExceeded(_, let error), .writeFailed(let error):
            return if let error = error as? LocalizedError {
                error.errorDescription
            } else {
                error.localizedDescription
            }
        }
    }
}
