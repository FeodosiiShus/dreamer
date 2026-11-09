//
//  ProjectCEWorkspaceSettings.swift
//  Dreamder
//
//  Created by Axel Martinez on 27/3/24.
//

import SwiftUI
import Observation

@Observable
class ProjectSettings: Codable {
    var projectName: String = ""

    init() {}

    enum CodingKeys: CodingKey {
        case projectName
    }

    /// Explicit decoder init for setting default values when key is not present in `JSON`
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectName, forKey: .projectName)
    }

    func isEmpty() -> Bool {
        projectName == ""
    }
}
