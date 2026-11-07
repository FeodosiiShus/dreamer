//
//  SearchIndexer+InternalMethods.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 18.11.23.
//

import Foundation
import UniformTypeIdentifiers

nonisolated extension SearchIndexer {
    /// A "typealias" for a document ID, using a struct because swift lint doesn't allow type-aliases for 3 types
    nonisolated public struct DocumentID: Sendable {
        let url: URL
        let documentID: SKDocumentID
    }
    /// Returns the mime type for the url, or nil if the mime type couldn't be ascertained from the extension
    ///
    /// - Parameter url: the url to detect the mime type for
    /// - Returns: the mime type of the url if able to detect, nil otherwise
    func detectMimeType(_ url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if let mimeType = type.preferredMIMEType {
                return mimeType
            }
        }
        return nil
    }

    /// Remove the given document from the index
    /// When the app deletes a document, use this function to update the index to reflect the change,
    /// i. e. the index does not need to get flushed.
    func remove(document: SKDocument) -> Bool {
        withState { state -> Bool in
            guard let index = state.index else {
                return false
            }
            return SKIndexRemoveDocument(index, document)
        }
    }

    /// Recurse through the children of a document and return an array containing all the document-ids
    private static func addLeafURLs(index: SKIndex, inParentDocument: SKDocument?, docs: inout [DocumentID]) {
        var isLeaf = true

        let iterator = SKIndexDocumentIteratorCreate(index, inParentDocument).takeRetainedValue()
        while let skDocument = SKIndexDocumentIteratorCopyNext(iterator) {
            isLeaf = false
            addLeafURLs(index: index, inParentDocument: skDocument.takeRetainedValue(), docs: &docs)
        }
        if isLeaf, let inParentDocument,
           kSKDocumentStateNotIndexed != SKIndexGetDocumentState(index, inParentDocument) {
            let url = SKDocumentCopyURL(inParentDocument).takeRetainedValue()

            let documentID = SKIndexGetDocumentID(index, inParentDocument)
            docs.append(
                DocumentID(
                    url: url as URL,
                    documentID: documentID
                )
            )

        }
    }

    /// Return an array of all the documents contained within the index
    ///
    /// - Parameter termState: the TermState of documents to be returned (eg. all, empty only, non-empty only)
    /// - Returns: An array containing all the documents matching the TermState
    func fullDocuments(termState: TermState = .all) -> [DocumentID] {
        withState { state -> [DocumentID] in
            guard let index = state.index else {
                return []
            }

            var allDocs = [DocumentID]()

            Self.addLeafURLs(index: index, inParentDocument: nil, docs: &allDocs)

            switch termState {
            case .empty:
                return allDocs.filter {
                    SKIndexGetDocumentTermCount(index, $0.documentID) == 0
                }
            case .notEmpty:
                return allDocs.filter {
                    SKIndexGetDocumentTermCount(index, $0.documentID) != 0
                }
            default:
                return allDocs
            }
        }
    }
}
