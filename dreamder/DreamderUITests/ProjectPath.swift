//
//  ProjectPath.swift
//  DreamderUITests
//
//  Created by Khan Winter on 7/10/24.
//

import Foundation
import Synchronization

func projectPath() -> String {
    return String(
        URL(fileURLWithPath: #filePath)
            .pathComponents
            .prefix(while: { $0 != "DreamderUITests" })
            .joined(separator: "/")
            .dropFirst()
    )
}

private let tempProjectPathIds = Mutex(Set<String>())

private func makeTempID() -> String {
    let id = String((0..<10).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-".randomElement()! })
    let inserted = tempProjectPathIds.withLock { $0.insert(id).inserted }
    return inserted ? id : makeTempID()
}

func tempProjectPath() throws -> String {
    let baseDir = FileManager.default.temporaryDirectory.appending(path: "DreamderUITests")
    let id = makeTempID()
    let path = baseDir.appending(path: id)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return path.path(percentEncoded: false)
}

func cleanUpTempProjectPaths() throws {
    let baseDir = FileManager.default.temporaryDirectory.appending(path: "DreamderUITests")
    try FileManager.default.removeItem(at: baseDir)
    tempProjectPathIds.withLock { $0.removeAll() }
}
