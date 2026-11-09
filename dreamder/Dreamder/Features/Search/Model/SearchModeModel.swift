//
//  SearchModeModel.swift
//  DreamderModules/Search
//
//  Created by Ziyuan Zhao on 2022/3/22.
//

import Foundation

struct SearchModeModel: Hashable {
    let title: String
    let children: [SearchModeModel]
    let needSelectionHighlight: Bool

    static let Containing = SearchModeModel(title: "Containing", children: [], needSelectionHighlight: false)
    static let MatchingWord = SearchModeModel(
        title: "Matching Word",
        children: [],
        needSelectionHighlight: true
    )
    static let StartingWith = SearchModeModel(
        title: "Starting With",
        children: [],
        needSelectionHighlight: true
    )
    static let EndingWith = SearchModeModel(title: "Ending With", children: [], needSelectionHighlight: true)

    static let Text = SearchModeModel(
        title: "Text",
        children: [.Containing, .MatchingWord, .StartingWith, .EndingWith],
        needSelectionHighlight: false
    )
    static let References = SearchModeModel(
        title: "References",
        children: [.Containing, .MatchingWord, .StartingWith, .EndingWith],
        needSelectionHighlight: true
    )
    static let Definitions = SearchModeModel(
        title: "Definitions",
        children: [.Containing, .MatchingWord, .StartingWith, .EndingWith],
        needSelectionHighlight: true
    )
    static let RegularExpression = SearchModeModel(
        title: "Regular Expression",
        children: [],
        needSelectionHighlight: true
    )
    static let CallHierarchy = SearchModeModel(
        title: "Call Hierarchy",
        children: [],
        needSelectionHighlight: true
    )

    static let Find = SearchModeModel(
        title: "Find",
        children: [.Text, .References, .Definitions, .RegularExpression, .CallHierarchy],
        needSelectionHighlight: false
    )
    static let Replace = SearchModeModel(
        title: "Replace",
        children: [.Text, .RegularExpression],
        needSelectionHighlight: true
    )

    static let TextMatchingModes: [SearchModeModel] = [.Containing, .MatchingWord, .StartingWith, .EndingWith]
    static let FindModes: [SearchModeModel] = [
        .Text,
        .References,
        .Definitions,
        .RegularExpression,
        .CallHierarchy
    ]
    static let ReplaceModes: [SearchModeModel] = [.Text, .RegularExpression]
    static let SearchModes: [SearchModeModel] = [.Find, .Replace]
}

extension SearchModeModel: Equatable {
    static func == (lhs: SearchModeModel, rhs: SearchModeModel) -> Bool {
        lhs.title == rhs.title
            && lhs.children == rhs.children
            && lhs.needSelectionHighlight == rhs.needSelectionHighlight
    }
}

extension Array where Element == SearchModeModel {
    var isReplaceMode: Bool { first == .Replace }
    var isRegularExpressionMode: Bool { count > 1 && self[1] == .RegularExpression }
    var matchingMode: SearchModeModel? { count > 2 ? self[2] : nil }

    func switchingRegularExpression(_ enabled: Bool) -> [SearchModeModel] {
        let kind = first ?? .Find
        return enabled ? [kind, .RegularExpression] : [kind, .Text, .Containing]
    }

    func switchingMatchingMode(_ mode: SearchModeModel) -> [SearchModeModel] {
        guard count > 2 else { return self }
        var modes = self
        modes[2] = mode
        return modes
    }
}
