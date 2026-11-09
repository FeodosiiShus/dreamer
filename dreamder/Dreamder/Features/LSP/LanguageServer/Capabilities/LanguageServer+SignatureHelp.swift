//
//  LanguageServer+SignatureHelp.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    var signatureHelpCapability: SignatureHelpCapability? {
        SignatureHelpCapability(
            staticOptions: serverCapabilities.signatureHelpProvider,
            isDynamicallyRegistered: dynamicCapabilities.hasCapability(SignatureHelpProtocol.method),
            dynamicOptions: dynamicCapabilities.registerOptions(for: SignatureHelpProtocol.method, as: SignatureHelpOptions.self)
        )
    }

    func requestSignatureHelp(
        for documentURI: String,
        position: Position,
        context: SignatureHelpContext
    ) async throws -> SignatureHelpResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let params = SignatureHelpRequestParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                position: position,
                context: context
            )
            return try await lspInstance.customRequest(method: SignatureHelpProtocol.method, params: params.lspAny())
        } catch {
            logger.warning("requestSignatureHelp: Error \(error)")
            throw error
        }
    }
}
