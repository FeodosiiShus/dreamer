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

    var extensions: [ExtensionInfo] {
        ExtensionDiscovery.shared.extensions
    }

}
