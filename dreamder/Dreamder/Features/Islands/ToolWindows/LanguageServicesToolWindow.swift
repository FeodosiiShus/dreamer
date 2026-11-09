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

@MainActor
@Observable
final class LanguageServicesModel {
    @ObservationIgnored private let lspService: LSPService
    private(set) var expandedLogs: Set<String> = []
    private(set) var expandedMessages: Set<String> = []
    private(set) var memory: [pid_t: UInt64] = [:]

    init(lspService: LSPService) {
        self.lspService = lspService
    }

    func rows(workspacePath: String?) -> [LanguageServerRowModel] {
        LanguageServerRowModel.rows(
            states: lspService.serverStates,
            clients: lspService.languageClients,
            workspacePath: workspacePath
        )
    }

    func logMessages(for key: LSPService.ClientKey) -> [String]? {
        lspService.languageClients[key].map { $0.logContainer.logs.suffix(200).map(\.message) }
    }

    func refreshMemory(workspacePath: String?) {
        let megabyte: UInt64 = 1_048_576
        var updated: [pid_t: UInt64] = [:]
        for row in rows(workspacePath: workspacePath) where row.status == .running {
            guard let pid = row.pid, let bytes = LanguageServerRowModel.memoryFootprint(pid: pid) else { continue }
            updated[pid] = (bytes + megabyte / 2) / megabyte * megabyte
        }
        if updated != memory {
            memory = updated
        }
    }

    func trackMemory(workspacePath: String?, every interval: Duration) async {
        while !Task.isCancelled {
            refreshMemory(workspacePath: workspacePath)
            try? await Task.sleep(for: interval)
        }
    }

    func restart(_ keys: [LSPService.ClientKey]) async {
        for key in keys {
            try? await lspService.restartServer(key)
        }
    }

    func stop(_ key: LSPService.ClientKey) async {
        try? await lspService.stopServer(forLanguage: key.languageId, workspacePath: key.workspacePath)
    }

    func hideAction(_ manager: ToolWindowManager) -> () -> Void {
        { manager.hide(.languageServices) }
    }

    func restartAllAction(workspacePath: String?) -> () -> Void {
        {
            let keys = self.rows(workspacePath: workspacePath).map(\.key)
            Task { await self.restart(keys) }
        }
    }

    func stopAllAction() -> () -> Void {
        { Task { await self.lspService.stopAllServers() } }
    }

    func toggleMessageAction(_ id: String) -> () -> Void {
        { self.expandedMessages.formSymmetricDifference([id]) }
    }

    func toggleLogsAction(_ id: String) -> () -> Void {
        { self.expandedLogs.formSymmetricDifference([id]) }
    }

    func restartAction(_ key: LSPService.ClientKey) -> () -> Void {
        { Task { await self.restart([key]) } }
    }

    func stopAction(_ key: LSPService.ClientKey) -> () -> Void {
        { Task { await self.stop(key) } }
    }
}

struct LanguageServicesToolWindow: View {
    @Environment(WorkspaceDocument.self) private var workspace
    @Environment(ToolWindowManager.self) private var toolWindowManager

    @State private var model: LanguageServicesModel

    private let memoryInterval: Duration

    init(
        model: LanguageServicesModel = LanguageServicesModel(lspService: .shared),
        memoryInterval: Duration = .seconds(2)
    ) {
        _model = State(initialValue: model)
        self.memoryInterval = memoryInterval
    }

    private var workspacePath: String? {
        workspace.fileURL?.absolutePath
    }

    var body: some View {
        let rows = model.rows(workspacePath: workspacePath)
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Language Services") {
                EmptyView()
            } actions: {
                ToolWindowActionButton(icon: "general/hide", help: "Hide", action: model.hideAction(toolWindowManager))
            }
            if rows.isEmpty {
                Text("No language servers")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    LanguageServicesButton(
                        icon: "run/restart",
                        title: "Restart All Servers",
                        action: model.restartAllAction(workspacePath: workspacePath)
                    )
                    LanguageServicesButton(icon: "run/stop", title: "Stop All Servers", action: model.stopAllAction())
                        .disabled(!rows.contains { $0.canStop })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(Self.projectTitle(of: workspace.fileURL))
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
        .task { await model.trackMemory(workspacePath: workspacePath, every: memoryInterval) }
    }

    static func projectTitle(of fileURL: URL?) -> String {
        fileURL?.lastPathComponent ?? "Project"
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
                if let pid = row.pid, row.status == .running, let bytes = model.memory[pid] {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
                Spacer(minLength: 8)
                if row.message != nil {
                    LanguageServicesButton(
                        icon: "status/error",
                        title: "Message",
                        action: model.toggleMessageAction(row.id)
                    )
                        .help("Show Server Message")
                }
                if row.hasLogs {
                    LanguageServicesButton(
                        icon: "general/listFiles",
                        title: "Logs",
                        action: model.toggleLogsAction(row.id)
                    )
                        .help("Show Server Logs")
                }
                LanguageServicesButton(icon: "run/restart", title: "Restart", action: model.restartAction(row.key))
                    .help("Restart \(row.name)")
                if row.canStop {
                    LanguageServicesButton(icon: "run/stop", title: "Stop", action: model.stopAction(row.key))
                        .help("Stop \(row.name)")
                }
            }
            if let message = row.message, model.expandedMessages.contains(row.id) {
                Text(message)
                    .font(Islands.smallFont)
                    .foregroundStyle(Color(hex: 0xE55765))
                    .textSelection(.enabled)
            }
            if model.expandedLogs.contains(row.id), let messages = model.logMessages(for: row.key) {
                LanguageServerLogPreview(messages: messages)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityIdentifier("LanguageServerRow-\(row.key.languageId.rawValue)")
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
                .fill(Islands.glassRaisedFill)
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
        .onHover(perform: setHovering)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}
