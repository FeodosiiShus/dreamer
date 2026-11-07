import Combine
import Darwin
import SwiftUI

struct LanguageServerRowModel: Identifiable, Equatable {
    enum Status: Equatable {
        case starting
        case running
        case failed
        case stopped

        var title: String {
            switch self {
            case .starting: "Starting"
            case .running: "Running"
            case .failed: "Error"
            case .stopped: "Stopped"
            }
        }

        var color: Color {
            switch self {
            case .starting: Color(hex: 0xA77BE0)
            case .running: Color(hex: 0x5FB865)
            case .failed: Color(hex: 0xE55765)
            case .stopped: Islands.disabledForeground
            }
        }
    }

    let key: LSPService.ClientKey
    let name: String
    let version: String?
    let status: Status
    let message: String?
    let pid: pid_t?
    let hasLogs: Bool

    var id: String { key.workspacePath + "|" + key.languageId.rawValue }

    var canStop: Bool { status == .running }

    static func rows(
        states: [LSPService.ClientKey: LSPService.ServerState],
        clients: [LSPService.ClientKey: LSPService.LanguageServerType],
        workspacePath: String?
    ) -> [LanguageServerRowModel] {
        let keys = Set(states.keys).union(clients.keys)
            .filter { workspacePath == nil || $0.workspacePath == workspacePath }
        return keys.map { key in
            let client = clients[key]
            let status: Status
            var message: String?
            switch states[key] ?? (client == nil ? .stopped : .running) {
            case .starting: status = .starting
            case .running: status = client == nil ? .stopped : .running
            case .failed(let error):
                status = .failed
                message = error
            case .stopped: status = .stopped
            }
            let binaryName = client.map { URL(fileURLWithPath: $0.binary.execPath).lastPathComponent }
            return LanguageServerRowModel(
                key: key,
                name: client?.serverInfo?.name ?? binaryName ?? key.languageId.rawValue,
                version: client?.serverInfo?.version,
                status: status,
                message: message,
                pid: client.map(\.pid),
                hasLogs: !(client?.logContainer.logs.isEmpty ?? true)
            )
        }
        .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }

    static func memoryFootprint(pid: pid_t) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}

struct LanguageServicesToolWindow: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var toolWindowManager: ToolWindowManager

    @Service private var lspService: LSPService

    @State private var rows: [LanguageServerRowModel] = []
    @State private var expandedLogs: Set<String> = []
    @State private var expandedMessages: Set<String> = []
    @State private var memory: [pid_t: UInt64] = [:]

    private let memoryTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {}

    private var workspacePath: String? {
        workspace.fileURL?.absolutePath
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Language Services") {
                EmptyView()
            } actions: {
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.bottom)
                }
            }
            if rows.isEmpty {
                Text("No language servers")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    LanguageServicesButton(icon: "run/restart", title: "Restart All Servers") {
                        restartAll()
                    }
                    LanguageServicesButton(icon: "run/stop", title: "Stop All Servers") {
                        Task { await lspService.stopAllServers() }
                    }
                    .disabled(!rows.contains { $0.canStop })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(workspace.fileURL?.lastPathComponent ?? "Project")
                            .font(Islands.smallFont.weight(.semibold))
                            .foregroundStyle(Islands.secondaryForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        ForEach(rows) { row in
                            serverRow(row)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshRows()
            refreshMemory()
        }
        .onReceive(lspService.$languageClients) { _ in
            Task { @MainActor in refreshRows() }
        }
        .onReceive(lspService.$serverStates) { _ in
            Task { @MainActor in refreshRows() }
        }
        .onReceive(memoryTimer) { _ in
            refreshMemory()
        }
    }

    private func refreshMemory() {
        let megabyte: UInt64 = 1_048_576
        var updated: [pid_t: UInt64] = [:]
        for row in rows where row.status == .running {
            guard let pid = row.pid, let bytes = LanguageServerRowModel.memoryFootprint(pid: pid) else { continue }
            updated[pid] = (bytes + megabyte / 2) / megabyte * megabyte
        }
        if updated != memory {
            memory = updated
        }
    }

    private func refreshRows() {
        rows = LanguageServerRowModel.rows(
            states: lspService.serverStates,
            clients: lspService.languageClients,
            workspacePath: workspacePath
        )
    }

    private func serverRow(_ row: LanguageServerRowModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(row.status.color)
                    .frame(width: 8, height: 8)
                Text(row.name)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                Text(row.status.title)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.secondaryForeground)
                if let version = row.version {
                    Text(version)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
                if let pid = row.pid, row.status == .running, let bytes = memory[pid] {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
                Spacer(minLength: 8)
                if row.message != nil {
                    LanguageServicesButton(icon: "status/error", title: "Message") {
                        toggle(row.id, in: &expandedMessages)
                    }
                    .help("Show Server Message")
                }
                if row.hasLogs {
                    LanguageServicesButton(icon: "general/listFiles", title: "Logs") {
                        toggle(row.id, in: &expandedLogs)
                    }
                    .help("Show Server Logs")
                }
                LanguageServicesButton(icon: "run/restart", title: "Restart") {
                    Task { try? await lspService.restartServer(row.key) }
                }
                .help("Restart \(row.name)")
                if row.canStop {
                    LanguageServicesButton(icon: "run/stop", title: "Stop") {
                        Task {
                            try? await lspService.stopServer(
                                forLanguage: row.key.languageId,
                                workspacePath: row.key.workspacePath
                            )
                        }
                    }
                    .help("Stop \(row.name)")
                }
            }
            if let message = row.message, expandedMessages.contains(row.id) {
                Text(message)
                    .font(Islands.smallFont)
                    .foregroundStyle(Color(hex: 0xE55765))
                    .textSelection(.enabled)
            }
            if expandedLogs.contains(row.id), let client = lspService.languageClients[row.key] {
                LanguageServerLogPreview(messages: client.logContainer.logs.suffix(200).map(\.message))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("LanguageServerRow-\(row.key.languageId.rawValue)")
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func restartAll() {
        let keys = rows.map(\.key)
        Task {
            for key in keys {
                try? await lspService.restartServer(key)
            }
        }
    }
}

private struct LanguageServerLogPreview: View {
    let messages: [String]

    var body: some View {
        ScrollView {
            Text(messages.joined(separator: "\n"))
                .font(Islands.codeFont)
                .foregroundStyle(Islands.editorForeground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .frame(maxHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(Color.black.opacity(0.2))
        )
    }
}

struct LanguageServicesButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(Islands.smallFont)
            }
            .foregroundStyle(isEnabled ? Islands.foreground : Islands.disabledForeground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(isHovering ? Islands.hover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .strokeBorder(Islands.componentBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
