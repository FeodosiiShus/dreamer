//
//  StatusBarViewModel.swift
//  Dreamder
//
//  Created by Paul Ebose on 2024/5/12.
//

import SwiftUI

@Observable
final class StatusBarViewModel {

    /// The file size of the currently opened file.
    var fileSize: Int?

    /// The dimensions (width x height) of the currently opened image.
    var dimensions: ImageDimensions?

}

extension FileEncoding {
    var statusBarLabel: String {
        switch self {
        case .utf8:
            return "UTF-8"
        case .utf16BE:
            return "UTF-16 BE"
        case .utf16LE:
            return "UTF-16 LE"
        }
    }
}
