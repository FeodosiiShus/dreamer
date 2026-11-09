//
//  GolangPackageManager.swift
//  Dreamder
//
//  Created by Abe Malla on 2/3/25.
//

import Foundation

final class GolangPackageManager: PackageManagerProtocol {
    private let installationDirectory: URL

    init(installationDirectory: URL) {
        self.installationDirectory = installationDirectory
    }

    // MARK: - PackageManagerProtocol

    func install(method installationMethod: InstallationMethod) throws -> [PackageManagerInstallStep] {
        guard case .standardPackage(let source) = installationMethod else {
            throw PackageManagerError.invalidConfiguration
        }

        let packagePath = try RegistryInputValidation.child(of: installationDirectory, named: source.entryName)
        var steps = [
            initialize(in: packagePath),
            try runGoInstall(source, packagePath: packagePath)
        ]

        if let subpath = source.options["subpath"] {
            steps.append(try buildBinary(source, subpath: subpath, packagePath: packagePath))
        }

        return steps
    }

    /// Check if go is installed
    func isInstalled(method installationMethod: InstallationMethod) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "",
            confirmation: .required(message: "This package requires go to install. Allow Dreamder to run go commands?")
        ) { model in
            let versionOutput = try await model.run(["go", "version"])
            let versionPattern = #"go version go\d+\.\d+"#
            let output = versionOutput.reduce(into: "") {
                $0 += $1.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard output.range(of: versionPattern, options: .regularExpression) != nil else {
                throw PackageManagerError.packageManagerNotInstalled
            }
        }
    }

    /// Get the binary path for a Go package
    func getBinaryPath(for package: String) -> String {
        let binPath = installationDirectory.appending(path: package).appending(path: "bin")
        let binaryName = Self.lastPathComponent(of: package)
        let specificBinPath = binPath.appending(path: binaryName).path
        if FileManager.default.fileExists(atPath: specificBinPath) {
            return specificBinPath
        }
        return binPath.path
    }

    private static func lastPathComponent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    // MARK: - Initialize

    func initialize(in packagePath: URL) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "Initialize Directory Structure",
            confirmation: .none
        ) { model in
            try model.createDirectoryStructure(for: packagePath)

            _ = try await model.run(["go", "mod", "init", "dreamder.temp/placeholder"], in: packagePath)
        }
    }

    // MARK: - Install Using Go

    func runGoInstall(_ source: PackageSource, packagePath: URL) throws -> PackageManagerInstallStep {
        let installCommand = try RegistryInputValidation.argument(getGoInstallCommand(source))
        let gobinPath = packagePath.appending(path: "bin", directoryHint: .isDirectory).path
        return PackageManagerInstallStep(
            name: "Install Package Using go",
            confirmation: .required(
                message: "This requires installing the go package \(installCommand)."
                + "\nAllow Dreamder to install this package?"
            )
        ) { model in
            _ = try await model.run(
                ["go", "install", installCommand],
                in: packagePath,
                environment: ["GOBIN": gobinPath]
            )
        }
    }

    // MARK: - Build Binary

    func buildBinary(
        _ source: PackageSource,
        subpath: String,
        packagePath: URL
    ) throws -> PackageManagerInstallStep {
        let binPath = packagePath.appending(path: "bin")
        let binaryName = try RegistryInputValidation.component(Self.lastPathComponent(of: subpath))
        let execPath = try RegistryInputValidation.child(of: binPath, named: binaryName)
        let target = try RegistryInputValidation.argument(
            source.pkgName.contains("/") ? "\(source.pkgName)/\(subpath)" : subpath
        )
        let buildArgs = ["go", "build", "-o", "bin/\(binaryName)", target]

        return PackageManagerInstallStep(
            name: "Build From Source",
            confirmation: .none
        ) { model in
            if !FileManager.default.fileExists(atPath: binPath.path) {
                try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)
            }

            _ = try await model.run(buildArgs, in: packagePath)
            try FileManager.default.makeExecutable(execPath)
        }
    }

    // MARK: - Helper methods

    private func getGoInstallCommand(_ source: PackageSource) -> String {
        if let gitRef = source.gitReference, let repoUrl = source.repositoryUrl {
            // Check if this is a Git-based package
            var packageName = source.pkgName
            if !packageName.contains("github.com") && !packageName.contains("golang.org") {
                packageName = repoUrl.replacingOccurrences(of: "https://", with: "")
            }

            let gitVersion: String
            switch gitRef {
            case .tag(let tag):
                gitVersion = tag
            case .revision(let rev):
                gitVersion = rev
            }

            return "\(packageName)@\(gitVersion)"
        } else {
            return "\(source.pkgName)@\(source.version)"
        }
    }
}
