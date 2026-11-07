//
//  StopTaskToolbarButton.swift
//  Dreamder
//
//  Created by Austin Condiff on 8/3/24.
//

import SwiftUI

struct StopTaskToolbarButton: View {
    @Environment(\.controlActiveState)
    private var activeState

    let taskManager: TaskManager

    private var currentSelectedStatus: CETaskStatus? {
        guard let id = taskManager.selectedTaskID else { return nil }
        return taskManager.activeTasks[id]?.status
    }

    var body: some View {
        HStack {
            if let currentSelectedStatus, currentSelectedStatus == .running {
                    Button {
                        taskManager.terminateActiveTask()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                            .opacity(activeState == .inactive ? 0.5 : 1.0)
                            .font(.system(size: 15, weight: .regular))
                            .help("Stop selected task")
                            .frame(width: 28)
                            .offset(y: 1.5)
                    }
                    .frame(height: 22)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(width: 38, height: 22)
        .animation(
            .easeInOut(duration: 0.3),
            value: currentSelectedStatus
        )
    }
}
