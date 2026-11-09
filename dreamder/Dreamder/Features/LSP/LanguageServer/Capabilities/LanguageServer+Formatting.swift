//
//  LanguageServer+Formatting.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    static var documentFormattingMethod: String { "textDocument/formatting" }
    static var rangeFormattingMethod: String { "textDocument/rangeFormatting" }
    static var onTypeFormattingMethod: String { "textDocument/onTypeFormatting" }

    var supportsDocumentFormatting: Bool {
        switch serverCapabilities.documentFormattingProvider {
        case .optionA(let enabled):
            return enabled
        case .optionB:
            return true
        case nil:
            return dynamicCapabilities.hasCapability(Self.documentFormattingMethod)
        }
    }

    var supportsRangeFormatting: Bool {
        switch serverCapabilities.documentRangeFormattingProvider {
        case .optionA(let enabled):
            return enabled
        case .optionB:
            return true
        case nil:
            return dynamicCapabilities.hasCapability(Self.rangeFormattingMethod)
        }
    }

    var onTypeFormattingOptions: DocumentOnTypeFormattingOptions? {
        serverCapabilities.documentOnTypeFormattingProvider
            ?? dynamicCapabilities.registerOptions(
                for: Self.onTypeFormattingMethod,
                as: DocumentOnTypeFormattingOptions.self
            ).first
    }

    func requestFormatting(
        for documentURI: String,
        withFormat formattingOptions: FormattingOptions
    ) async throws -> FormattingResult {
        await flushPendingEdits(for: documentURI)
        do {
            let params = DocumentFormattingParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                options: formattingOptions
            )
            return try await lspInstance.formatting(params)
        } catch {
            logger.warning("requestFormatting: Error \(error)")
            throw error
        }
    }

    func requestRangeFormatting(
        for documentURI: String,
        _ range: LSPRange,
        withFormat formattingOptions: FormattingOptions
    ) async throws -> FormattingResult {
        await flushPendingEdits(for: documentURI)
        do {
            let params = DocumentRangeFormattingParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                range: range,
                options: formattingOptions
            )
            return try await lspInstance.rangeFormatting(params)
        } catch {
            logger.warning("requestRangeFormatting: Error \(error)")
            throw error
        }
    }

    func requestOnTypeFormatting(
        for documentURI: String,
        _ position: Position,
        character char: String,
        withFormat formattingOptions: FormattingOptions
    ) async throws -> FormattingResult {
        await flushPendingEdits(for: documentURI)
        do {
            let params = DocumentOnTypeFormattingParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position,
                ch: char,
                options: formattingOptions
            )
            return try await lspInstance.onTypeFormatting(params)
        } catch {
            logger.warning("requestOnTypeFormatting: Error \(error)")
            throw error
        }
    }
}
