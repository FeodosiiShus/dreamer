import Foundation
import Testing
@testable import Dreamder

@Suite
struct RegistryItemHomepageTests {
    private func makeItem(homepage: String) throws -> RegistryItem {
        let json = """
        {
          "name": "entry",
          "description": "d",
          "homepage": "\(homepage)",
          "licenses": [],
          "languages": [],
          "categories": [],
          "source": { "id": "pkg:npm/entry@1.0.0" }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: Data(json.utf8))
    }

    @Test
    func aHomepageThatIsNotAValidURLIsShownAsWritten() throws {
        for homepage in ["", "http://["] {
            let item = try makeItem(homepage: homepage)
            #expect(item.homepageURL == nil, "\(homepage)")
            #expect(item.homepagePretty == homepage, "\(homepage)")
        }
    }

    @Test
    func aHomepageWithoutAHostShowsOnlyItsPath() throws {
        let item = try makeItem(homepage: "docs/readme")
        #expect(item.homepageURL?.host() == nil)
        #expect(item.homepagePretty == "docs/readme")
    }
}
