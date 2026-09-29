import AppKit
import Observation
import ServiceManagement
import TockCore

/// App state shared by the popover and the Settings window. Services and their secrets come from the Vault; only the
/// display order and the two preferences live in UserDefaults.
@MainActor @Observable
final class Store {
    private(set) var services: [Service] = []
    var error: String?
    /// Whether the popover is on screen; the code list's clock runs only while it is.
    var popoverShown = false
    var clearsClipboard: Bool {
        didSet { defaults.set(clearsClipboard, forKey: "clearsClipboard") }
    }
    private(set) var launchesAtLogin = false
    var loginMessage: String?

    private let vault: Vault
    private let defaults: UserDefaults

    init(vault: Vault = Vault(), defaults: UserDefaults = .standard) {
        self.vault = vault
        self.defaults = defaults
        clearsClipboard = defaults.object(forKey: "clearsClipboard") as? Bool ?? true
        if !defaults.bool(forKey: "loginSetupCompleted") { setLaunchAtLogin(true) }
        readLoginStatus()
        reload()
    }

    func reload() {
        do {
            let stored = try vault.load()
            let order = defaults.stringArray(forKey: "order") ?? []
            // Services missing from the saved order keep the Vault's alphabetical order after the ordered ones.
            services = stored.sorted { (order.firstIndex(of: $0.id.uuidString) ?? .max) < (order.firstIndex(of: $1.id.uuidString) ?? .max) }
            error = nil
        } catch { self.error = "Could not read the keychain: \(error.localizedDescription)" }
    }

    @discardableResult
    func save(_ service: Service) -> Bool {
        do {
            try vault.save(service)
            if !services.contains(where: { $0.id == service.id }) { saveOrder(services.map(\.id) + [service.id]) }
            reload()
            return true
        } catch {
            self.error = "Could not save to the keychain: \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ service: Service) {
        do {
            try vault.delete(service.id)
            saveOrder(services.map(\.id).filter { $0 != service.id })
            reload()
        } catch { self.error = "Could not delete from the keychain: \(error.localizedDescription)" }
    }

    /// Where a Service sits in the full list. One not saved yet goes after the last.
    func position(of id: UUID) -> Int {
        services.firstIndex { $0.id == id } ?? services.count
    }

    func move(_ service: Service, by offset: Int) {
        var ids = services.map(\.id)
        guard let index = ids.firstIndex(of: service.id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        saveOrder(ids)
        reload()
    }

    /// Copies a code, marked concealed so clipboard managers that honor the nspasteboard.org convention skip it.
    func copy(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pasteboard.changeCount
        guard clearsClipboard else { return }
        Task {
            try? await Task.sleep(for: .seconds(30))
            // Leave the clipboard alone if anything else was copied since.
            if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled && service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if !enabled && service.status != .notRegistered { try service.unregister() }
            defaults.set(true, forKey: "loginSetupCompleted")
            loginMessage = nil
        } catch { loginMessage = "Launch at login could not be changed: \(error.localizedDescription)" }
        readLoginStatus()
    }

    func readLoginStatus() {
        let status = SMAppService.mainApp.status
        launchesAtLogin = status == .enabled || status == .requiresApproval
        if status == .requiresApproval { loginMessage = "Allow Tock in System Settings > General > Login Items." }
    }

    private func saveOrder(_ ids: [UUID]) {
        defaults.set(ids.map(\.uuidString), forKey: "order")
    }
}
