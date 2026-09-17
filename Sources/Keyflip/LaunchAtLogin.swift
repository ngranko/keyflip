import Foundation
import ServiceManagement

enum LaunchAtLogin {
    enum Result: Equatable {
        case changed
        case requiresApproval
        case failed(domain: String, code: Int)
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func toggle() -> Result {
        let service = SMAppService.mainApp
        let result = change(status: service.status, register: { try service.register() },
                            unregister: { try service.unregister() })
        return needsApproval ? .requiresApproval : result
    }

    static func change(status: SMAppService.Status, register: () throws -> Void,
                       unregister: () throws -> Void) -> Result {
        if status == .requiresApproval { return .requiresApproval }
        do {
            if status == .enabled { try unregister() } else { try register() }
            return .changed
        } catch {
            let error = error as NSError
            if requiresApproval(error) {
                return .requiresApproval
            }
            return .failed(domain: error.domain, code: error.code)
        }
    }

    private static func requiresApproval(_ error: NSError) -> Bool {
        guard error.code == Int(kSMErrorLaunchDeniedByUser) else { return false }
        if #available(macOS 15, *), error.domain == SMAppServiceErrorDomain { return true }
        // Preserve older macOS errors without referencing the deprecated SDK constant.
        return error.domain == "kSMErrorDomainFramework"
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
