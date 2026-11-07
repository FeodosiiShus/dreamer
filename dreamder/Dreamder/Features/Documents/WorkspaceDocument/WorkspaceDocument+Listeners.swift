//
//  WorkspaceDocument+CommandListeners.swift
//  Dreamder
//
//  Created by Khan Winter on 6/5/22.
//

import Foundation
import Observation

@Observable
class WorkspaceNotificationModel {

    var highlightedFileItem: CEWorkspaceFile?

    init() {
        highlightedFileItem = nil
    }

}
