//
//  ExtensionManager.swift
//  Dreamder
//
//  Created by Wouter Hennen on 30/12/2022.
//

import Foundation
import SwiftUI
import ExtensionFoundation
import CodeEditKit
import ConcurrencyPlus

@Observable
final class ExtensionManager {

    static var shared = ExtensionManager()

    var extensions: [ExtensionInfo] = ExtensionDiscovery.shared.extensions

    @ObservationIgnored
    private var observation: Task<Void, Never>?

    init() {
        observation = Task { [weak self] in
            for await extensions in Observations({ ExtensionDiscovery.shared.extensions }) {
                guard let self else { return }
                self.extensions = extensions
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

}
