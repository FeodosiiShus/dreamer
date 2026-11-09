//
//  CargoPackageManager.swift
//  Dreamder
//
//  Created by Abe Malla on 2/3/25.
//

import Foundation

final class CargoPackageManager: PackageManagerProtocol {
    private let installationDirectory: URL

    init(installationDirectory: URL) {
        self.installationDirectory = installationDirectory
    }

    func install(method installationMethod: InstallationMethod) throws -> [PackageManagerInstallStep] {
        guard case .standardPackage(let source) = installationMethod else {
            throw PackageManagerError.invalidConfiguration
        }
        let packagePath = try RegistryInputValidation.child(of: installationDirectory, named: source.entryName)
        return [
            initialize(in: packagePath),
            try runCargoInstall(source, in: packagePath)
        ]
    }

    func isInstalled(method installationMethod: InstallationMethod) -> PackageManagerInstallStep {
        PackageManagerInstallStep(
            name: "",
            confirmation: .none
        ) { model in
            let versionOutput = try await model.run(["cargo", "--version"])
            let output = versionOutput.reduce(into: "") {
                $0 += $1.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard output.starts(with: "cargo") else {
                throw PackageManagerError.packageManagerNotInstalled
            }
        }
    }

    func getBinaryPath(for package: String) -> String {
        return installationDirectory.appending(path: package).appending(path: "bin").path
    }

    func initialize(in packagePath: URL) -> PackageManagerInstallStep {
        PackageManagerInstallStep(name: "Initialize Directory Structure", confirmation: .none) { model in
            try model.createDirectoryStructure(for: packagePath)
        }
    }

    func runCargoInstall(_ source: PackageSource, in packagePath: URL) throws -> PackageManagerInstallStep {
        let qualifiedPackageName = "\(source.pkgName)@\(source.version)"

        var cargoArgs = ["cargo", "install", "--root", "."]
        if let gitRef = source.gitReference, let repoUrl = source.repositoryUrl {
            cargoArgs.append(contentsOf: ["--git", try RegistryInputValidation.httpsURL(repoUrl)])
            switch gitRef {
            case .tag(let tag):
                cargoArgs.append(contentsOf: ["--tag", try RegistryInputValidation.argument(tag)])
            case .revision(let rev):
                cargoArgs.append(contentsOf: ["--rev", try RegistryInputValidation.argument(rev)])
            }
        } else {
            let name = try RegistryInputValidation.argument(source.pkgName)
            let version = try RegistryInputValidation.argument(source.version)
            cargoArgs.append("\(name)@\(version)")
        }

        if let features = source.options["features"] {
            cargoArgs.append(contentsOf: ["--features", try RegistryInputValidation.argument(features)])
        }
        if source.options["locked"] == "true" {
            cargoArgs.append("--locked")
        }

        let arguments = cargoArgs
        return PackageManagerInstallStep(
            name: "Install Package Using cargo",
            confirmation: .required(
                message: "This requires the cargo package \(qualifiedPackageName)."
                + "\nAllow Dreamder to install this package?"
            )
        ) { model in
            try await model.run(arguments, in: packagePath)
        }
    }
}
