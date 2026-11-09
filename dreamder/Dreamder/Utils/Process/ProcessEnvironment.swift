import Foundation

nonisolated enum ProcessEnvironment {
    static let strippedPrefixes = ["DYLD_", "__XPC_DYLD_"]

    static let gitRedirectingNames: Set<String> = [
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR",
        "GIT_NAMESPACE",
        "GIT_CEILING_DIRECTORIES",
        "GIT_DISCOVERY_ACROSS_FILESYSTEM",
        "GIT_CONFIG_PARAMETERS",
        "GIT_CONFIG_COUNT",
        "GIT_REPLACE_REF_BASE",
        "GIT_LITERAL_PATHSPECS",
        "GIT_GLOB_PATHSPECS",
        "GIT_NOGLOB_PATHSPECS",
        "GIT_ICASE_PATHSPECS"
    ]

    static let gitRedirectingPrefixes = ["GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"]

    static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment.filter { entry in
            !strippedPrefixes.contains { entry.key.hasPrefix($0) }
        }
    }

    static func sanitizedForGit(_ environment: [String: String]) -> [String: String] {
        sanitized(environment).filter { entry in
            !gitRedirectingNames.contains(entry.key)
                && !gitRedirectingPrefixes.contains { entry.key.hasPrefix($0) }
        }
    }
}
