//
//  RegistryManager+HandleRegistryFile.swift
//  Dreamder
//
//  Created by Abe Malla on 3/14/25.
//

import Foundation

extension RegistryManager {
    /// Downloads the latest registry
    func downloadRegistryItems() async {
        guard let registryURL, let checksumURL else { return }
        isDownloadingRegistry = true
        defer { isDownloadingRegistry = false }

        let registryData, checksumData: Data
        do {
            async let zipDataTask = download(from: registryURL)
            async let checksumsTask = download(from: checksumURL)

            (registryData, checksumData) = try await (zipDataTask, checksumsTask)
        } catch {
            handleUpdateError(error)
            return
        }

        do {
            try RegistryChecksums(checksumData).verify(registryData, as: registryURL.lastPathComponent)
        } catch {
            handleUpdateError(error)
            return
        }

        do {
            try installRegistry(archive: registryData, checksums: checksumData)
            downloadError = nil
        } catch let error as RegistryManagerError {
            handleUpdateError(error)
            return
        } catch {
            handleUpdateError(RegistryManagerError.writeFailed(error: error))
            return
        }

        do {
            if let items = loadItemsFromDisk() {
                setRegistryItems(items)
            } else {
                throw RegistryManagerError.failedToSaveRegistryCache
            }
        } catch {
            handleUpdateError(error)
        }
    }

    private func installRegistry(archive: Data, checksums: Data) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: installPath, withIntermediateDirectories: true)

        let staging = installPath.appending(path: Self.stagingDirectoryName, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: staging.path(percentEncoded: false)) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let archiveURL = staging.appending(path: "registry.zip")
        let extracted = staging.appending(path: "extracted", directoryHint: .isDirectory)
        try archive.write(to: archiveURL)
        try fileManager.unzipItem(at: archiveURL, to: extracted)

        let stagedRegistry = extracted.appending(path: "registry.json")
        guard fileManager.fileExists(atPath: stagedRegistry.path(percentEncoded: false)) else {
            throw RegistryManagerError.failedToSaveRegistryCache
        }

        try checksums.write(to: installPath.appending(path: "checksums.txt"), options: .atomic)
        let registryPath = installPath.appending(path: "registry.json")
        let registryFile = registryPath.path(percentEncoded: false)
        if fileManager.fileExists(atPath: registryFile) {
            try fileManager.removeItem(at: registryPath)
        }
        try fileManager.moveItem(at: stagedRegistry, to: registryPath)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: registryFile)
    }

    func handleUpdateError(_ error: Error) {
        self.downloadError = error
        if let regError = error as? RegistryManagerError {
            switch regError {
            case .installationRunning:
                return // Shouldn't need to handle
            case .invalidResponse(let statusCode):
                logger.error("Invalid response received: \(statusCode)")
            case let .downloadFailed(url, error):
                logger.error("Download failed for \(url.absoluteString): \(error.localizedDescription)")
            case let .maxRetriesExceeded(url, error):
                logger.error("Max retries exceeded for \(url.absoluteString): \(error.localizedDescription)")
            case let .writeFailed(error):
                logger.error("Failed to write files to disk: \(error.localizedDescription)")
            case .failedToSaveRegistryCache:
                logger.error("Failed to read registry from cache after download and write.")
            case let .checksumMissing(file):
                logger.error("No checksum published for \(file); registry update rejected.")
            case let .checksumMismatch(file):
                logger.error("Checksum mismatch for \(file); registry update rejected.")
            }
        } else {
            logger.error("Unexpected registry error: \(error.localizedDescription)")
        }
    }

    /// Attempts downloading from `url`, with error handling and a retry policy
    @Sendable
    func download(from url: URL, attempt: Int = 1) async throws -> Data {
        do {
            let (data, response) = try await fetch(url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RegistryManagerError.downloadFailed(
                    url: url, error: NSError(domain: "Invalid response type", code: -1)
                )
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw RegistryManagerError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            return data
        } catch {
            if attempt <= 3 {
                let delay = pow(2.0, Double(attempt))
                try await backoff(delay)
                return try await download(from: url, attempt: attempt + 1)
            } else {
                throw RegistryManagerError.maxRetriesExceeded(url: url, lastError: error)
            }
        }
    }

    /// Loads registry items from disk
    func loadItemsFromDisk() -> [RegistryItem]? {
        let registryPath = installPath.appending(path: "registry.json")
        let fileManager = FileManager.default

        // Update the file every 24 hours
        let attributes = try? fileManager.attributesOfItem(atPath: registryPath.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let needsUpdate = modificationDate.map { Date().timeIntervalSince($0) / 3600 >= 24 } ?? true

        if needsUpdate {
            return nil
        }

        do {
            let registryData = try Data(contentsOf: registryPath)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let items = try decoder.decode([RegistryItem].self, from: registryData)
            return items.filter { $0.categories.contains("LSP") }
        } catch {
            return nil
        }
    }
}
