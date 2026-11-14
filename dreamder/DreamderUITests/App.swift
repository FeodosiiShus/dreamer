//
//  App.swift
//  DreamderUITests
//
//  Created by Khan Winter on 7/21/24.
//

import XCTest

@MainActor
enum App {
    static func launchWithDreamderWorkspace() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", projectPath()]
        application.launch()
        return application
    }

    // Launches Dreamder in a new directory and returns the directory path.
    static func launchWithTempDir() throws -> (XCUIApplication, String) {
        let tempDirURL = try tempProjectPath()
        let application = XCUIApplication()
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", tempDirURL]
        application.launch()
        return (application, tempDirURL)
    }

    static func launch() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        application.launch()
        return application
    }
}
