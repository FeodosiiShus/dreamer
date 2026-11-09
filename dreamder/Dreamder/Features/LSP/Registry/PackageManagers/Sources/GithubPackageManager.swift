//
//  GithubPackageManager.swift
//  LSPInstallTest
//
//  Created by Abe Malla on 3/10/25.
//

import Foundation

typealias PackageFileDownload = @Sendable (URLRequest) async throws -> (URL, URLResponse)

final class GithubPackageManager: PackageManagerProtocol {
    private let installationDirectory: URL
    private let download: PackageFileDownload

    init(
        installationDirectory: URL,
        download: @escaping PackageFileDownload = { try await URLSession.shared.download(for: $0) }
    ) {
        self.installationDirectory = installationDirectory
        self.download = download
    }

    // MARK: - PackageManagerProtocol

    func install(method installationMethod: InstallationMethod) throws -> [PackageManagerInstallStep] {
        switch installationMethod {
        case let .binaryDownload(source, url):
            let packagePath = installationDirectory.appending(path: source.entryName)
            return [
                initialize(in: packagePath),
                downloadBinary(source, url: url, installDir: installationDirectory),
                decompressBinary(source, url: url, installDir: installationDirectory)
            ]
        case let .sourceBuild(source, command):
            let packagePath = installationDirectory.appending(path: source.entryName)
            return [
                initialize(in: packagePath),
                try gitClone(source, installDir: installationDirectory),
                installFromSource(source, installDir: installationDirectory, command: command)
            ]
        case .standardPackage, .unknown:
            throw PackageManagerError.invalidConfiguration
        }
    }

    func isInstalled(method installationMethod: InstallationMethod) -> PackageManagerInstallStep {
        switch installationMethod {
        case .binaryDownload:
            PackageManagerInstallStep(
                name: "",
                confirmation: .none,
                handler: { _ in }
            )
        case .sourceBuild:
            PackageManagerInstallStep(
                name: "",
                confirmation: .required(
                    message: "This package requires git to install. Allow Dreamder to run git commands?"
                )
            ) { model in
                let versionOutput = try await model.runCommand("git --version")
                let output = versionOutput.reduce(into: "") {
                    $0 += $1.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard output.contains("git version") else {
                    throw PackageManagerError.packageManagerNotInstalled
                }
            }
        case .standardPackage, .unknown:
            PackageManagerInstallStep(
                name: "",
                confirmation: .none,
                handler: { _ in throw PackageManagerError.invalidConfiguration }
            )
        }
    }

    func getBinaryPath(for package: String) -> String {
        return installationDirectory.appending(path: package).appending(path: "bin").path
    }

    // MARK: - Initialize

    func initialize(in packagePath: URL) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Initialize Directory Structure",
            confirmation: .none
        ) { model in
            do {
                try model.createDirectoryStructure(for: packagePath)
            } catch {
                throw PackageManagerError.initializationFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Download Binary

    private func downloadBinary(
        _ source: PackageSource,
        url: URL,
        installDir installationDirectory: URL
    ) -> PackageManagerInstallStep {
        let download = self.download
        return PackageManagerInstallStep(
            name: "Download Binary Executable",
            confirmation: .none
        ) { model in
            do {
                model.status("Downloading \(url)")
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120.0)
                let (tempURL, response) = try await download(request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw RegistryManagerError.downloadFailed(
                        url: url,
                        error: NSError(domain: "HTTP error", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
                    )
                }

                let downloadPath = installationDirectory.appending(path: source.entryName)
                let packagePath = downloadPath.appending(path: url.lastPathComponent)
                if FileManager.default.fileExists(atPath: packagePath.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: packagePath)
                }

                try FileManager.default.moveItem(at: tempURL, to: packagePath)
            } catch {
                if error is RegistryManagerError {
                    throw error
                }
                throw RegistryManagerError.downloadFailed(
                    url: url,
                    error: error
                )
            }
        }
    }

    // MARK: - Decompress Binary

    private func decompressBinary(
        _ source: PackageSource,
        url: URL,
        installDir installationDirectory: URL
    ) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Decompress Binary Executable",
            confirmation: .none
        ) { model in
            let fileName = url.lastPathComponent
            let downloadPath = installationDirectory.appending(path: source.entryName)
            let packagePath = downloadPath.appending(path: fileName)
            let workingDirectory = downloadPath.path(percentEncoded: false)
            let archivePath = packagePath.path(percentEncoded: false).escapedDirectory()

            if packagePath.pathExtension == "zip" {
                model.status("Decompressing \(fileName)")
                try FileManager.default.unzipItem(at: packagePath, to: downloadPath)
                try FileManager.default.removeItem(at: packagePath)
                model.status("Decompressed to '\(workingDirectory)'")
            } else if fileName.hasSuffix(".tar.gz") {
                model.status("Decompressing \(fileName) using `tar`")
                _ = try await model.executeInDirectory(in: workingDirectory, ["tar", "-xzf", archivePath])
            } else if packagePath.pathExtension == "tar" {
                model.status("Decompressing \(fileName) using `tar`")
                _ = try await model.executeInDirectory(in: workingDirectory, ["tar", "-xf", archivePath])
            } else if packagePath.pathExtension == "gz" {
                model.status("Decompressing \(fileName) using `gunzip`")
                _ = try await model.executeInDirectory(in: workingDirectory, ["gunzip", "-f", archivePath])
            }

            let executablePath = downloadPath.appending(path: url.deletingPathExtension().lastPathComponent)
            if FileManager.default.fileExists(atPath: executablePath.path(percentEncoded: false)) {
                try FileManager.default.makeExecutable(executablePath)
            }
        }
    }

    // MARK: - Git Clone

    private func gitClone(
        _ source: PackageSource,
        installDir installationDirectory: URL
    ) throws -> PackageManagerInstallStep {
        guard let repoURL = source.repositoryUrl else {
            throw PackageManagerError.invalidConfiguration
        }
        let command = ["git", "clone", repoURL]

        return PackageManagerInstallStep(
            name: "Clone with Git",
            // swiftlint:disable:next line_length
            confirmation: .required(message: "This step will run the following command to clone the package from source control:\n`\(command.joined(separator: " "))`")
        ) { model in
            let installPath = installationDirectory.appending(path: source.entryName, directoryHint: .isDirectory)
            _ = try await model.executeInDirectory(in: installPath.path, command)
        }
    }

    // MARK: - Install From Source

    private func installFromSource(
        _ source: PackageSource,
        installDir installationDirectory: URL,
        command: String
    ) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Install From Source",
            confirmation: .required(message: "This step will run the following to finish installing:\n`\(command)`")
        ) { model in
            do {
                let installPath = installationDirectory.appending(path: source.entryName, directoryHint: .isDirectory)
                let repoPath = installPath.appending(path: source.pkgName, directoryHint: .isDirectory)
                _ = try await model.executeInDirectory(in: repoPath.path, [command])
            } catch {
                throw PackageManagerError.installationFailed("Source build failed.")
            }
        }
    }
}
