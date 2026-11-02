import Foundation
import Testing
@testable import Dreamder

@Suite
struct TestFileClassifierTests {
    @Test(arguments: [
        ("/p/a.spec.ts", true),
        ("/p/a.e2e.test.tsx", true),
        ("/p/__tests__/helper.ts", true),
        ("/p/src/__tests__/deep/util.js", true),
        ("/p/spec.ts", false),
        ("/p/test.ts", false),
        ("/p/a.ts.spec", false),
        ("/p/latest.ts", false),
        ("/p/contest.spec", false),
        ("/p/__tests__", false),
        ("/p/aspec.ts", false)
    ])
    func classifiesLikeWebStormTestsScope(path: String, expected: Bool) {
        #expect(TestFileClassifier.isTestFile(URL(fileURLWithPath: path)) == expected)
    }
}
