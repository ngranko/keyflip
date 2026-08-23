import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            try? service.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            do {
                try service.register()
            } catch {
                let ns = error as NSError
                if ns.code == Int(kSMErrorLaunchDeniedByUser) || service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
    }
}
