//
//  SourceControlPreferences.swift
//  DreamderModules/Settings
//
//  Created by Nanashi Li on 2022/04/08.
//

import Foundation

extension SettingsData {
    /// The global settings for source control
    struct SourceControlSettings: Codable, Hashable, SearchableSettingsPage {

        var searchKeys: [String] {
            [
                "General",
                "Enable source control",
                "Refresh local status automatically",
                "Fetch and refresh server status automatically",
                "Add and remove files automatically",
                "Select files to commit automatically",
                "Show source control changes",
                "Include upstream changes",
                "Comparison view",
                "Source control navigator",
                "Default branch name",
                "Git",
                "Author Name",
                "Author Email",
                "Prefer to rebase when pulling",
                "Show merge commits in per-file log"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// The general source control settings
        var general: SourceControlGeneral = .init()

        /// The source control git settings
        var git: SourceControlGit = .init()

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.general = container.lenient(.general, default: .init())
            self.git = container.lenient(.git, default: .init())
        }
    }

    struct SourceControlGeneral: Codable, Hashable {
        /// Indicates whether or not the source control is active
        var sourceControlIsEnabled: Bool = true
        /// Indicates whether the status should be refreshed locally without fetching updates from the server.
        var refreshStatusLocally: Bool = true
        /// Indicates whether the application should automatically fetch updates from the server and refresh the status.
        var fetchRefreshServerStatus: Bool = true
        /// Indicates whether new and deleted files should be automatically staged for commit.
        var addRemoveAutomatically: Bool = true
        /// Indicates whether the application should automatically select files to commit.
        var selectFilesToCommit: Bool = true
        /// Indicates whether or not to show the source control changes
        var showSourceControlChanges: Bool = true
        /// Indicates whether or not we should include the upstream
        var includeUpstreamChanges: Bool = true
        /// The selected value of the comparison view
        var revisionComparisonLayout: RevisionComparisonLayout = .localLeft
        /// The selected value of the control navigator
        var controlNavigatorOrder: ControlNavigatorOrder = .sortByName
        /// Default initializer
        init() {}
        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.sourceControlIsEnabled = container.lenient(.sourceControlIsEnabled, default: true)
            self.refreshStatusLocally = container.lenient(.refreshStatusLocally, default: true)
            self.fetchRefreshServerStatus = container.lenient(.fetchRefreshServerStatus, default: true)
            self.addRemoveAutomatically = container.lenient(.addRemoveAutomatically, default: true)
            self.selectFilesToCommit = container.lenient(.selectFilesToCommit, default: true)
            self.showSourceControlChanges = container.lenient(.showSourceControlChanges, default: true)
            self.includeUpstreamChanges = container.lenient(.includeUpstreamChanges, default: true)
            self.revisionComparisonLayout = container.lenient(.revisionComparisonLayout, default: .localLeft)
            self.controlNavigatorOrder = container.lenient(.controlNavigatorOrder, default: .sortByName)
        }
    }

    /// The style for comparison View
    /// - **localLeft**: Local Revision on Left Side
    /// - **localRight**: Local Revision on Right Side
    enum RevisionComparisonLayout: String, Codable {
        case localLeft
        case localRight
    }

    /// The style for control Navigator
    /// - **sortName**: They are sorted by Name
    /// - **sortDate**: They are sorted by Date
    enum ControlNavigatorOrder: String, Codable {
        case sortByName
        case sortByDate
    }

    struct SourceControlGit: Codable, Hashable {
        /// Indicates whether we should rebase when pulling commits
        var showMergeCommitsPerFileLog: Bool = false
        /// Default initializer
        init() {}
        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.showMergeCommitsPerFileLog = container.lenient(.showMergeCommitsPerFileLog, default: false)
        }
    }
}
