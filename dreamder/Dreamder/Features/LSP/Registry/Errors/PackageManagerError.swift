//
//  PackageManagerError.swift
//  Dreamder
//
//  Created by Abe Malla on 5/12/25.
//

import Foundation

nonisolated enum PackageManagerError: Error, LocalizedError {
    case unknown
    case packageManagerNotInstalled
    case initializationFailed(String)
    case installationFailed(String)
    case invalidConfiguration
    case unsafeValue(String)

    var errorDescription: String? {
        switch self {
        case .unknown:
            "Unknown error occurred"
        case .packageManagerNotInstalled:
            "The required package manager is not installed."
        case .initializationFailed:
            "Installation directory initialization failed."
        case .installationFailed:
            "Package installation failed."
        case .invalidConfiguration:
            "The package registry contained an invalid installation configuration."
        case .unsafeValue(let value):
            "The package registry contained a value that is not allowed: \(value)"
        }
    }

    var failureReason: String? {
        switch self {
        case .unknown:
            nil
        case .packageManagerNotInstalled:
            nil
        case .initializationFailed(let string):
            string
        case .installationFailed(let string):
            string
        case .invalidConfiguration:
            nil
        case .unsafeValue:
            nil
        }
    }
}
