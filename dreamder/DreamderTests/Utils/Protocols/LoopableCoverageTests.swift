import Foundation
import Testing
@testable import Dreamder

nonisolated struct LoopableCoverageStructFixture: Loopable {
    var name = "Steve"
    var books = 4
}

nonisolated final class LoopableCoverageClassFixture: Loopable {
    let title = "Dune"
    let pages = 412
}

nonisolated enum LoopableCoverageEnumFixture: Loopable {
    case value
}

nonisolated struct LoopableCoverageUnlabeledFixture: Loopable, CustomReflectable {
    var customMirror: Mirror {
        let children: [Mirror.Child] = [
            (label: nil, value: 1),
            (label: "kept", value: 2)
        ]
        return Mirror(self, children: children, displayStyle: .struct)
    }
}

@Suite
struct LoopableCoverageTests {
    @Test
    func structPropertiesAreReturnedByName() throws {
        let properties = try LoopableCoverageStructFixture().allProperties()

        #expect(properties.count == 2)
        #expect(properties["name"] as? String == "Steve")
        #expect(properties["books"] as? Int == 4)
    }

    @Test
    func classPropertiesAreReturnedByName() throws {
        let properties = try LoopableCoverageClassFixture().allProperties()

        #expect(properties.count == 2)
        #expect(properties["title"] as? String == "Dune")
        #expect(properties["pages"] as? Int == 412)
    }

    @Test
    func nonStructuredTypesThrow() {
        #expect(throws: LoopableError.notAStructOrClass) {
            try LoopableCoverageEnumFixture.value.allProperties()
        }
    }

    @Test
    func childrenWithoutALabelAreSkipped() throws {
        let properties = try LoopableCoverageUnlabeledFixture().allProperties()

        #expect(properties.count == 1)
        #expect(properties["kept"] as? Int == 2)
    }
}
