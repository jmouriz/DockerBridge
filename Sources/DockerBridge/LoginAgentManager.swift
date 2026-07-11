import Foundation
import ServiceManagement

enum LoginAgentState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LoginAgentError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.tr("loginAgent.error.unavailable")
        }
    }
}

enum LoginAgentManager {
    private static var service: SMAppService {
        SMAppService.loginItem(identifier: AppConstants.loginItemBundleIdentifier)
    }

    static var state: LoginAgentState {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            // Ad-hoc development builds report notFound until the first registration.
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    static func isInstalled() -> Bool {
        state == .enabled || state == .requiresApproval
    }

    static func install() throws {
        switch state {
        case .enabled:
            return
        case .requiresApproval:
            openSystemSettings()
            return
        case .unavailable:
            throw LoginAgentError.unavailable
        case .disabled:
            do {
                try service.register()
            } catch {
                if service.status == .requiresApproval {
                    openSystemSettings()
                    return
                }
                throw error
            }

            if service.status == .requiresApproval {
                openSystemSettings()
            }
        }
    }

    static func uninstall() throws {
        switch state {
        case .disabled:
            return
        case .unavailable:
            throw LoginAgentError.unavailable
        case .enabled, .requiresApproval:
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
