import Foundation
import Testing
@testable import Dreamder

@Suite
struct FileEncodingTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let encoding: FileEncoding
        let foundationValue: UInt

        var testDescription: String { "\(encoding)" }
    }

    static let cases: [Case] = [
        Case(encoding: .utf8, foundationValue: NSUTF8StringEncoding),
        Case(encoding: .utf16BE, foundationValue: NSUTF16BigEndianStringEncoding),
        Case(encoding: .utf16LE, foundationValue: NSUTF16LittleEndianStringEncoding)
    ]

    @Test(arguments: cases)
    func eachEncodingMapsToItsFoundationValueAndBack(_ testCase: Case) {
        #expect(testCase.encoding.nsValue == testCase.foundationValue)
        #expect(FileEncoding(testCase.foundationValue) == testCase.encoding)
    }

    @Test
    func theTableCoversEveryEncoding() {
        #expect(Set(Self.cases.map(\.encoding)) == Set(FileEncoding.allCases))
    }

    @Test
    func unsupportedFoundationEncodingsAreRejected() {
        #expect(FileEncoding(NSISOLatin1StringEncoding) == nil)
        #expect(FileEncoding(NSASCIIStringEncoding) == nil)
    }
}
