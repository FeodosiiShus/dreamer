//
//  GitCheckoutBranchView.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/17/23.
//

import Foundation

@Observable
class GitCheckoutBranchViewModel {
    var selectedBranch: GitBranch?
    var branches: [GitBranch] = []

    let repoPath: URL
    @ObservationIgnored private let gitClient: GitClient

    init(repoPath: URL) {
        self.repoPath = repoPath
        gitClient = .init(directoryURL: repoPath, shellClient: .live())
    }

    func loadBranches() async {
        let branches = ((try? await gitClient.getBranches()) ?? [])
            .filter({ $0.isRemote })

        self.branches = branches
        if selectedBranch == nil {
            selectedBranch = branches.first
        }
    }

    func checkoutBranch() async {
        guard let selectedBranch else { return }

        try? await gitClient.checkoutBranch(selectedBranch)
    }
}
