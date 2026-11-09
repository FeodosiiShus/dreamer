//
//  AcknowledgementsTests.swift
//  DreamderTests
//
//  Created by Lukas Pistrol on 14.01.23.
//

import XCTest
@testable import Dreamder

@MainActor
final class AcknowledgementsTests: XCTestCase {

    func testAcknowledgementsNotEmpty() throws {
        let model = AcknowledgementsViewModel()
        XCTAssertFalse(model.acknowledgements.isEmpty)
    }
}
