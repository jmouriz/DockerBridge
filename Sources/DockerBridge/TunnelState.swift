import Foundation

enum TunnelState: Equatable {
    case stopped
    case starting(Date)
    case running(Date)
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    var label: String {
        switch self {
        case .stopped:
            return L10n.tr("state.stopped")
        case .starting:
            return L10n.tr("state.starting")
        case .running:
            return L10n.tr("state.running")
        case .stopping:
            return L10n.tr("state.stopping")
        case .failed:
            return L10n.tr("state.failed")
        }
    }

    var detail: String {
        switch self {
        case .failed(let message):
            return message
        default:
            return label
        }
    }
}
