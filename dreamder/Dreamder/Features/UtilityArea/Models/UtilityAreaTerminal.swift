//
//  UtilityAreaTerminal.swift
//  Dreamder
//
//  Created by Khan Winter on 7/27/24.
//

import Foundation
import Observation

@Observable
final class UtilityAreaTerminal: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var title: String
    var terminalTitle: String
    var shell: Shell?
    var customTitle: Bool

    init(id: UUID, url: URL, title: String, shell: Shell?) {
        self.id = id
        self.title = title
        self.terminalTitle = title
        self.url = url
        self.shell = shell
        self.customTitle = false
    }

    static func == (lhs: UtilityAreaTerminal, rhs: UtilityAreaTerminal) -> Bool {
        lhs.id == rhs.id
    }
}
