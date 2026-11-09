//
//  LSPCache+Data.swift
//  Dreamder
//
//  Created by Abe Malla on 6/23/24.
//

import Foundation
import LanguageServerProtocol

struct CacheKey: Hashable {
    let uri: String
    let requestType: String
    let position: Position?
    let documentVersion: Int?
    let extraData: AnyHashable?

    init(
        uri: String,
        requestType: String,
        position: Position? = nil,
        documentVersion: Int? = nil,
        extraData: AnyHashable? = nil
    ) {
        self.uri = uri
        self.requestType = requestType
        self.position = position
        self.documentVersion = documentVersion
        self.extraData = extraData
    }
}
