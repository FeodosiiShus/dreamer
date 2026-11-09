//
//  AcknowledgementsModel.swift
//  DreamderModules/Acknowledgements
//
//  Created by Lukas Pistrol on 01.05.22.
//

import SwiftUI
import Observation
import OSLog

@Observable
final class AcknowledgementsViewModel {

    private(set) var acknowledgements: [AcknowledgementDependency]

    var indexedAcknowledgements: [(index: Int, acknowledgement: AcknowledgementDependency)] {
      return Array(zip(acknowledgements.indices, acknowledgements))
    }

    private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "AcknowledgementsViewModel")

    private let packageResolvedPath: String?

    init(
        _ dependencies: [AcknowledgementDependency] = [],
        packageResolvedPath: String? = Bundle.main.path(forResource: "Package", ofType: "resolved")
    ) {
        self.acknowledgements = dependencies
        self.packageResolvedPath = packageResolvedPath

        if acknowledgements.isEmpty {
            fetchDependencies()
        }
    }

    func fetchDependencies() {
        self.acknowledgements.removeAll()
        do {
            if let bundlePath = packageResolvedPath {
                let jsonData = Data(try String(contentsOfFile: bundlePath, encoding: .utf8).utf8)
                let parsedJSON = try JSONDecoder().decode(AcknowledgementObject.self, from: jsonData)
                for dependency in parsedJSON.pins.sorted(by: { $0.identity < $1.identity })
                where dependency.identity.range(
                    of: "[Cc]ode[Ee]dit",
                    options: .regularExpression,
                    range: nil,
                    locale: nil
                ) == nil {
                    self.acknowledgements.append(
                        AcknowledgementDependency(
                            name: dependency.name,
                            repositoryLink: dependency.location,
                            version: dependency.state.version ?? "-"
                        )
                    )
                }
            }
        } catch {
            Self.logger.error("Failed to read package dependencies: \(error.localizedDescription, privacy: .public)")
        }
    }
}
