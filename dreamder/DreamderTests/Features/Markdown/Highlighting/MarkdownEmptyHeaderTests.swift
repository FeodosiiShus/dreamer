import Foundation
import Testing
@testable import Dreamder

struct MarkdownEmptyHeaderTests {
    @Test(arguments: [
        ("#", ["#"], 1),
        ("#   ", ["#"], 1),
        ("#\t", ["#"], 1),
        ("## ##", ["##", "##"], 2),
        ("#\t#", ["#", "#"], 1),
        ("### ###   ", ["###", "###"], 3)
    ])
    func headersWithoutContentKeepAnEmptyRangeRightAfterTheMarker(text: String, markers: [String], markerEnd: Int) {
        let scan = MarkdownBlockLexer.scan(text)

        #expect(MarkdownLexerSupport.samples(text) == markers.map { MarkdownTokenSample(.headerMarker, $0) })
        #expect(scan.headers.count == 1)
        #expect(scan.headers.first?.isSetext == false)
        #expect(scan.headers.first?.contentRange == NSRange(location: markerEnd, length: 0))
    }
}
