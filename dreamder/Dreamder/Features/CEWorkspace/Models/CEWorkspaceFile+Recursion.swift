//
//  CEWorkspaceFile+Recursion.swift
//  Dreamder
//
//  Created by Matthijs Eikelenboom on 30/04/2023.
//

import Foundation

extension CEWorkspaceFile {
    /// Flattens the children of `self` recursively with depth.
    /// - Parameters:
    ///   - depth: An int that indicates the how deep the tree files need to be flattened
    ///   - ignoringFolders: A boolean on whether to ignore files that are Folders
    ///   - fileManager: The workspace's file manager to use.
    /// - Returns: An array of flattened `CEWorkspaceFiles`
    func flattenedChildren(
        withDepth depth: Int,
        ignoringFolders: Bool,
        using fileManager: CEWorkspaceFileManager
    ) -> [CEWorkspaceFile] {
        guard depth > 0 else { return [] }
        guard self.isFolder else { return [self] }
        var childItems: [CEWorkspaceFile] = ignoringFolders ? [] : [self]
        fileManager.childrenOfFile(self)?.forEach { child in
            childItems.append(contentsOf: child.flattenedChildren(
                withDepth: depth - 1,
                ignoringFolders: ignoringFolders,
                using: fileManager
            ))
        }
        return childItems
    }

    /// Returns a list of `CEWorkspaceFiles` that are sibilings of `self`.
    /// The `height` parameter lets the function navigate up the folder hierarchy to
    /// select a starting point from which it should start flettening the items.
    /// - Parameters:
    ///   - height: `Int` that tells where to start in the hierarchy
    ///   - ignoringFolders: Wether the sibling folders should be flattened
    ///   - fileManager: The workspace's file manager to use.
    /// - Returns: A list of `FileSystemItems`
    func flattenedSiblings(
        withHeight height: Int,
        ignoringFolders: Bool,
        using fileManager: CEWorkspaceFileManager
    ) -> [CEWorkspaceFile] {
        let topMostParent = self.getParent(withHeight: height)
        return topMostParent.flattenedChildren(withDepth: height, ignoringFolders: ignoringFolders, using: fileManager)
    }

    /// Using the current instance of `FileSystemItem` it will walk back up the Workspace file hiarchy
    /// the amount of times specified with the `withHeight` parameter.
    /// - Parameter height: The amount of times you want to up a folder.
    /// - Returns: The found `FileSystemItem` object, This should always be a folder.
    private func getParent(withHeight height: Int) -> CEWorkspaceFile {
        var topmostParent = self
        for _ in 0..<height {
            guard let parent = topmostParent.parent else { break }
            topmostParent = parent
        }

        return topmostParent
    }
}
