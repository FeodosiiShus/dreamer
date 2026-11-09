import Foundation

extension LSPService {
    func restartServers(inWorkspace workspacePath: String) async {
        let keys = serverStates.compactMap { key, state -> ClientKey? in
            guard key.workspacePath == workspacePath else { return nil }
            switch state {
            case .running, .failed: return key
            case .starting, .stopped: return nil
            }
        }
        for key in keys {
            try? await restartServer(key)
        }
    }
}
