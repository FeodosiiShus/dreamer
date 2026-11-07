//
//  URL+FuzzySearchable.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 03.02.24.
//

import Foundation

nonisolated extension URL: FuzzySearchable {
    var searchableString: String {
        return self.lastPathComponent
    }
}
