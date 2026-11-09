import Foundation

extension MergeRevisionsViewModel {
    var leftTitle: String {
        guard let context else { return "Yours" }
        switch context.operation {
        case .merge:
            return "Your version, branch \(context.yoursLabel)"
        case .rebase:
            return "Your commits, branch \(context.yoursLabel)"
        case .cherryPick, .stash:
            return "Local changes"
        default:
            return "Yours"
        }
    }

    var rightTitle: String {
        guard let context else { return "Theirs" }
        switch context.operation {
        case .merge:
            return "Theirs, branch \(context.theirsLabel)"
        case .rebase:
            return "Changes from branch \(context.theirsLabel)"
        case .cherryPick:
            return "Changes from \(context.theirsLabel)"
        case .stash:
            return "Changes from stash"
        default:
            return "Theirs"
        }
    }
}
