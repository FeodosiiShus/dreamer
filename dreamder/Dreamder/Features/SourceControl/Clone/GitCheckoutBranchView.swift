//
//  GitCheckoutBranchView.swift
//  DreamderModules/Git
//
//  Created by Aleksi Puttonen on 14.4.2022.
//

import Foundation
import SwiftUI

struct GitCheckoutBranchView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var viewModel: GitCheckoutBranchViewModel
    private var openDocument: (URL) -> Void

    init(
        viewModel: GitCheckoutBranchViewModel,
        openDocument: @escaping (URL) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.openDocument = openDocument
    }

    init(
        repoLocalPath: URL,
        openDocument: @escaping (URL) -> Void
    ) {
        self.init(viewModel: GitCheckoutBranchViewModel(repoPath: repoLocalPath), openDocument: openDocument)
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 50)
                VStack(alignment: .leading) {
                    Text("Checkout branch")
                        .bold()
                        .padding(.bottom, 2)
                    Text("Select a branch to checkout")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.selectedBranch, content: {
                        ForEach(viewModel.branches, id: \.self) { branch in
                            Text(branch.name.replacingOccurrences(of: "origin/", with: ""))
                                .tag(branch as GitBranch?)
                        }
                    })
                    .labelsHidden()

                    HStack {
                        Button("Cancel", action: dismiss.callAsFunction)
                        Button("Checkout", action: checkout)
                            .keyboardShortcut(.defaultAction)
                    }
                    .offset(x: 145)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(width: 400)
            .task {
                await viewModel.loadBranches()
            }
        }
    }

    func checkout() {
        Task {
            await viewModel.checkoutBranch()
            dismiss()
            openDocument(viewModel.repoPath)
        }
    }
}
