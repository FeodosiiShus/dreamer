import Foundation
import Testing
@testable import Dreamder

@Suite(.isolatedDefaults)
struct StructureTreeTransformTests {
    private func node(
        _ id: String,
        _ name: String,
        _ kind: StructureSymbolKind,
        line: Int = 1,
        children: [StructureNode] = []
    ) -> StructureNode {
        StructureNode(id: id, name: name, detail: nil, kind: kind, line: line, column: 1, children: children)
    }

    private var sample: [StructureNode] {
        [
            node("zeta", "zeta", .function, line: 1),
            node("outer", "Outer", .classType, line: 3, children: [
                node("run", "run", .method, line: 4),
                node("value", "value", .property, line: 5),
                node("Alpha", "Alpha", .method, line: 6)
            ]),
            node("beta", "beta", .variable, line: 8)
        ]
    }

    @Test
    func alphabeticalSortIgnoresCaseKeepsSourceOrderForTiesAndRecurses() {
        let tied = [node("1", "b", .function), node("2", "A", .function), node("3", "a", .function)]
        #expect(StructureTreeTransform.sorted(tied).map(\.id) == ["2", "3", "1"])

        let sorted = StructureTreeTransform.sorted(sample)
        #expect(sorted.map(\.name) == ["beta", "Outer", "zeta"])
        #expect(sorted[1].children.map(\.name) == ["Alpha", "run", "value"])
    }

    @Test
    func filterKeepsMatchesAndTheirAncestorsOnly() {
        let filtered = StructureTreeTransform.filtered(sample, pattern: "run")
        #expect(filtered.map(\.name) == ["Outer"])
        #expect(filtered[0].children.map(\.name) == ["run"])
    }

    @Test
    func filterMatchesCamelHumpsAndLeadingWildcards() {
        let nodes = [node("a", "topLevel", .function), node("b", "other", .function)]
        #expect(StructureTreeTransform.filtered(nodes, pattern: "tl").map(\.name) == ["topLevel"])
        #expect(StructureTreeTransform.filtered(nodes, pattern: "*ther").map(\.name) == ["other"])
    }

    @Test
    func blankFilterReturnsEverythingAndNoMatchReturnsNothing() {
        #expect(StructureTreeTransform.filtered(sample, pattern: "") == sample)
        #expect(StructureTreeTransform.filtered(sample, pattern: "  \n") == sample)
        #expect(StructureTreeTransform.filtered(sample, pattern: "qqqq").isEmpty)
        #expect(StructureTreeTransform.isFiltering("a"))
        #expect(!StructureTreeTransform.isFiltering("  "))
    }

    @Test
    func groupingBucketsTopLevelNodesByKindWithCounts() {
        let grouped = StructureTreeTransform.grouped(sample)
        #expect(grouped.map(\.name) == ["Classes", "Functions", "Variables"])
        #expect(grouped.map(\.detail) == ["1", "1", "1"])
        #expect(grouped.map(\.id) == ["group/Classes", "group/Functions", "group/Variables"])
        #expect(grouped.allSatisfy { $0.isGroup })
        #expect(grouped[0].children.first?.children.count == 3)
        #expect(grouped[0].line == 3)
        #expect(StructureTreeTransform.grouped([]).isEmpty)
    }

    @Test
    func groupingOrdersGroupsByKindCategoryNotSourceOrder() {
        let nodes = [
            node("v", "v", .constant, line: 1),
            node("c", "c", .constructor, line: 2),
            node("o", "o", .unknown, line: 3),
            node("n", "n", .namespace, line: 4),
            node("f1", "f1", .function, line: 5),
            node("f2", "f2", .method, line: 6)
        ]
        let grouped = StructureTreeTransform.grouped(nodes)
        #expect(grouped.map(\.name) == ["Namespaces", "Constructors", "Functions", "Variables", "Other"])
        #expect(grouped[2].detail == "2")
        #expect(StructureTreeTransform.groupID(of: nodes[5]) == "group/Functions")
    }

    @Test(arguments: [
        (StructureSymbolKind.file, StructureKindGroup.namespaces),
        (.module, .namespaces),
        (.namespace, .namespaces),
        (.package, .namespaces),
        (.classType, .classes),
        (.structType, .classes),
        (.actorType, .classes),
        (.enumType, .classes),
        (.interface, .classes),
        (.typeAlias, .classes),
        (.extensionDecl, .classes),
        (.typeParameter, .classes),
        (.constructor, .constructors),
        (.method, .functions),
        (.function, .functions),
        (.property, .variables),
        (.field, .variables),
        (.variable, .variables),
        (.constant, .variables),
        (.enumMember, .variables),
        (.unknown, .other)
    ])
    func everyKindBelongsToOneGroup(kind: StructureSymbolKind, group: StructureKindGroup) {
        #expect(StructureKindGroup(kind) == group)
        #expect(StructureKindGroup.allCases.map(\.title) == [
            "Namespaces", "Classes", "Constructors", "Functions", "Variables", "Other"
        ])
    }

    @Test
    func displayAppliesSortThenFilterThenGroup() {
        var options = StructureViewOptions()
        options.sortsAlphabetically = true
        options.groupsByKind = true
        let displayed = StructureTreeTransform.display(nodes: sample, options: options, filter: "")
        #expect(displayed.map(\.name) == ["Classes", "Functions", "Variables"])
        #expect(displayed[0].children[0].children.map(\.name) == ["Alpha", "run", "value"])

        let filtered = StructureTreeTransform.display(nodes: sample, options: options, filter: "alp")
        #expect(filtered.map(\.name) == ["Classes"])
        #expect(filtered[0].children[0].children.map(\.name) == ["Alpha"])

        #expect(StructureTreeTransform.display(nodes: sample, options: StructureViewOptions(), filter: "") == sample)
    }

    @Test
    func findLocatesNodesAtAnyDepth() {
        #expect(StructureTreeTransform.find("value", in: sample)?.name == "value")
        #expect(StructureTreeTransform.find("zeta", in: sample)?.name == "zeta")
        #expect(StructureTreeTransform.find("missing", in: sample) == nil)
    }

    @Test
    func forcedExpansionIgnoresCollapsedIds() {
        let rows = StructureTreeBuilder.rows(nodes: sample, collapsed: ["outer"], expandsAll: true)
        #expect(rows.map(\.node.id) == ["zeta", "outer", "run", "value", "Alpha", "beta"])
        #expect(StructureTreeBuilder.rows(nodes: sample, collapsed: ["outer"]).map(\.node.id) == ["zeta", "outer", "beta"])
    }

    @Test
    func optionsDefaultToIntelliJStyleAndRoundTripThroughDefaults() throws {
        let defaults = try IsolatedDefaults.require()
        let initial = StructureViewOptions(defaults: defaults)
        #expect(initial == StructureViewOptions())
        #expect(initial.sortsAlphabetically == false)
        #expect(initial.groupsByKind == false)
        #expect(initial.autoscrollsFromSource)
        #expect(initial.autoscrollsToSource == false)

        var changed = initial
        changed.sortsAlphabetically = true
        changed.groupsByKind = true
        changed.autoscrollsFromSource = false
        changed.autoscrollsToSource = true
        changed.save(to: defaults)
        #expect(StructureViewOptions(defaults: defaults) == changed)
    }

    @Test
    func caretLineCountsNewlinesBeforeTheOffset() {
        let text = "a\nbb\n\nccc"
        #expect(StructureCaretLine.line(offset: 0, in: text) == 1)
        #expect(StructureCaretLine.line(offset: 2, in: text) == 2)
        #expect(StructureCaretLine.line(offset: 5, in: text) == 3)
        #expect(StructureCaretLine.line(offset: 7, in: text) == 4)
        #expect(StructureCaretLine.line(offset: 999, in: text) == 4)
        #expect(StructureCaretLine.line(offset: -3, in: text) == 1)
        #expect(StructureCaretLine.line(offset: 0, in: "") == 1)
    }
}
