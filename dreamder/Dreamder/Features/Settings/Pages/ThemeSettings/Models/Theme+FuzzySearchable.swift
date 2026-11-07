//
//  Theme+FuzzySearchable.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 14.08.24.
//

import Foundation

nonisolated extension Theme: FuzzySearchable {
    var searchableString: String {
        return id
    }
}
