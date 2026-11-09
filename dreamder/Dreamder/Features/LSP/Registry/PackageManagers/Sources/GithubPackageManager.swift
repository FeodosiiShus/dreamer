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
            let packagePath = try RegistryInputValidation.child(of: installationDirectory, named: source.entryName)
            guard url.scheme == "https" else {
                throw PackageManagerError.unsafeValue(url.absoluteString)
            }
            let archivePath = try RegistryInputValidation.child(of: packagePath, named: url.lastPathComponent)
            let executablePath = try RegistryInputValidation.child(
                of: packagePath,
                named: url.deletingPathExtension().lastPathComponent
            )
            return [
                initialize(in: packagePath),
                downloadBinary(url: url, archivePath: archivePath),
                decompressBinary(packagePath: packagePath, archivePath: archivePath, executablePath: executablePath)
            ]
        case let .sourceBuild(source, command):
            let packagePath = try RegistryInputValidation.child(of: installationDirectory, named: source.entryName)
            let repoPath = try RegistryInputValidation.child(of: packagePath, named: source.pkgName)
            let buildCommands = try RegistryInputValidation.buildCommand(command)
            return [
                initialize(in: packagePath),
                try gitClone(source, packagePath: packagePath),
                installFromSource(command: command, buildCommands: buildCommands, repoPath: repoPath)
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
                let versionOutput = try await model.run(["git", "--version"])
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

    private func downloadBinary(url: URL, archivePath: URL) -> PackageManagerInstallStep {
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

                if FileManager.default.fileExists(atPath: archivePath.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: archivePath)
                }

                try FileManager.default.moveItem(at: tempURL, to: archivePath)
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
        packagePath downloadPath: URL,
        archivePath: URL,
        executablePath: URL
    ) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Decompress Binary Executable",
            confirmation: .none
        ) { model in
            let fileName = archivePath.lastPathComponent
            let workingDirectory = downloadPath.path(percentEncoded: false)
            let archive = archivePath.path(percentEncoded: false)

            if archivePath.pathExtension == "zip" {
                model.status("Decompressing \(fileName)")
                try FileManager.default.unzipItem(at: archivePath, to: downloadPath)
                try FileManager.default.removeItem(at: archivePath)
                model.status("Decompressed to '\(workingDirectory)'")
            } else if fileName.hasSuffix(".tar.gz") {
                model.status("Decompressing \(fileName) using `tar`")
                _ = try await model.run(["tar", "-xzf", archive], in: downloadPath)
            } else if archivePath.pathExtension == "tar" {
                model.status("Decompressing \(fileName) using `tar`")
                _ = try await model.run(["tar", "-xf", archive], in: downloadPath)
            } else if archivePath.pathExtension == "gz" {
                model.status("Decompressing \(fileName) using `gunzip`")
                _ = try await model.run(["gunzip", "-f", archive], in: downloadPath)
            }

            if FileManager.default.fileExists(atPath: executablePath.path(percentEncoded: false)) {
                try FileManager.default.makeExecutable(executablePath)
            }
        }
    }

    // MARK: - Git Clone

    private func gitClone(_ source: PackageSource, packagePath: URL) throws -> PackageManagerInstallStep {
        guard let repoURL = source.repositoryUrl else {
            throw PackageManagerError.invalidConfiguration
        }
        let command = ["git", "clone", try RegistryInputValidation.httpsURL(repoURL)]

        return PackageManagerInstallStep(
            name: "Clone with Git",
            // swiftlint:disable:next line_length
            confirmation: .required(message: "This step will run the following command to clone the package from source control:\n`\(command.joined(separator: " "))`")
        ) { model in
            _ = try await model.run(command, in: packagePath)
        }
    }

    // MARK: - Install From Source

    private func installFromSource(
        command: String,
        buildCommands: [[String]],
        repoPath: URL
    ) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Install From Source",
            confirmation: .required(message: "This step will run the following to finish installing:\n`\(command)`")
        ) { model in
            do {
                for buildCommand in buildCommands {
                    _ = try await model.run(buildCommand, in: repoPath)
                }
            } catch {
                throw PackageManagerError.installationFailed("Source build failed.")
            }
        }
    }
}
