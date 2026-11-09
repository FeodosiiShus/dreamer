//
//  CETask.swift
//  Dreamder
//
//  Created by Axel Martinez on 2/4/24.
//

import CryptoKit
import Foundation
import Observation

/// Dreamder task that will be executed by the task manager.
@Observable
class CETask: Identifiable, Hashable, Codable {
    static let workspaceSource = "workspace"
    static let defaultTarget = "My Mac"

    var source: String = CETask.workspaceSource
    @ObservationIgnored private var pinnedID: UUID?

    var id: UUID {
        if let pinnedID { return pinnedID }
        let resolved = name.isEmpty ? UUID() : Self.stableID(source: source, name: name)
        pinnedID = resolved
        return resolved
    }

    nonisolated static func stableID(source: String, name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(source)\u{0}\(name)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    var name: String = ""
    var target: String = ""
    var workingDirectory: String = ""
    var command: String = ""
    var environmentVariables: [EnvironmentVariable]  = []

    init(
        name: String = "",
        target: String = "",
        workingDirectory: String = "",
        command: String = "",
        environmentVariables: [CETask.EnvironmentVariable] = [],
        source: String = CETask.workspaceSource
    ) {
        self.name = name
        self.target = target
        self.workingDirectory = workingDirectory
        self.command = command
        self.environmentVariables = environmentVariables
        self.source = source
    }

    init(target: String) {
        self.target = target
    }

    var isInvalid: Bool {
        name.isEmpty ||
        command.isEmpty
    }

    /// Ensures that the shell navigates to the correct folder, and then executes the specified command.
    var fullCommand: String {
        // Move into the specified folder if needed
        let changeDirectoryCommand = workingDirectory.isEmpty ? "" : "cd \(workingDirectory.escapedDirectory()) && "

        // Construct the full command
        return "\(changeDirectoryCommand)\(command)"
    }

    /// Converts an array of `EnvironmentVariable` to a dictionary.
    ///
    /// - Returns: A dictionary with the environment variable keys and values.
    var environmentVariablesDictionary: [String: String] {
        return environmentVariables.reduce(into: [String: String]()) { result, environmentVariable in
            result[environmentVariable.key] = environmentVariable.value
        }
    }

    enum CodingKeys: CodingKey {
        case name
        case target
        case workingDirectory
        case command
        case environmentVariables
    }

    struct EnvironmentVariable: Identifiable, Hashable {
        var id = UUID()
        var key: String = ""
        var value: String = ""

        init() {}

        init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        command = try container.decode(String.self, forKey: .command)

        // Decode environment variables from a dictionary-like structure
        if let envDict = try container.decodeIfPresent([String: String].self, forKey: .environmentVariables) {
            environmentVariables = envDict.map { EnvironmentVariable(key: $0.key, value: $0.value) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !name.isEmpty {
            try container.encode(name, forKey: .name)
        }
        if !target.isEmpty && target != CETask.defaultTarget {
            try container.encode(target, forKey: .target)
        }

        if !workingDirectory.isEmpty {
            try container.encode(workingDirectory, forKey: .workingDirectory)
        }
        if !command.isEmpty {
            try container.encode(command, forKey: .command)
        }

        // Encode environment variables as a dictionary-like structure
        if !environmentVariables.isEmpty {
            var envDict = [String: String]()
            for variable in environmentVariables {
                envDict[variable.key] = variable.value
            }
            try container.encode(envDict, forKey: .environmentVariables)
        }
    }
}

extension CETask {
    static func == (lhs: CETask, rhs: CETask) -> Bool {
        return lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.persistedTarget == rhs.persistedTarget &&
        lhs.workingDirectory == rhs.workingDirectory &&
        lhs.command == rhs.command &&
        lhs.environmentVariablesDictionary == rhs.environmentVariablesDictionary
    }

    private var persistedTarget: String {
        target == CETask.defaultTarget ? "" : target
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(persistedTarget)
        hasher.combine(workingDirectory)
        hasher.combine(command)
        hasher.combine(environmentVariablesDictionary)
    }
}
