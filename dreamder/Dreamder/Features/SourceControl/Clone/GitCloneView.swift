//
//  GitCloneView.swift
//  DreamderModules/Git
//
//  Created by Aleksi Puttonen on 23.3.2022.
//

import SwiftUI
import Foundation

struct GitCloneView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var viewModel: GitCloneViewModel

    private let openBranchView: (URL) -> Void
    private let openDocument: (URL) -> Void

    init(
        viewModel: GitCloneViewModel = GitCloneViewModel(),
        openBranchView: @escaping (URL) -> Void,
        openDocument: @escaping (URL) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.openBranchView = openBranchView
        self.openDocument = openDocument
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text("Clone a Repository")
                        .bold()
                        .padding(.bottom, 2)
                    Text("Enter a git repository URL:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Git Repository URL", text: $viewModel.repoUrlStr)
                        .lineLimit(1)
                        .padding(.bottom, 15)

                    HStack {
                        Spacer()
                        Button("Cancel", action: dismiss.callAsFunction)
                        Button("Clone", action: cloneRepository)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!viewModel.isValidUrl(url: viewModel.repoUrlStr))
                    }
                }
                .frame(width: 300)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .onAppear(perform: viewModel.checkClipboard)
            .sheet(isPresented: $viewModel.isCloning) { GitCloneProgressSheet(viewModel: viewModel) }
        }
    }

    func cloneRepository() {
        viewModel.cloneRepository { localPath in
            dismiss()

            guard let gitClient = viewModel.gitClient else { return }

            Task {
                let branches = ((try? await  gitClient.getBranches()) ?? [])
                    .filter({ $0.isRemote })
                if branches.count > 1 {
                    openBranchView(localPath)
                    return
                }

                openDocument(localPath)
            }
        }
    }
}

struct GitCloneProgressSheet: View {
    let viewModel: GitCloneViewModel

    var body: some View {
        NavigationStack {
            VStack {
                ProgressView(
                    viewModel.cloningProgress.state.label,
                    value: viewModel.cloningProgress.progress,
                    total: 100
                )
            }
        }
        .toolbar { ToolbarItem { Button("Cancel Cloning", action: viewModel.cancelCloning) } }
        .padding()
        .frame(width: 350)
    }
}
