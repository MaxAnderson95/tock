import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let store = Store()
    private let navigation = SettingsNavigation()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = editMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = menuBarGlyph()
        item.button?.setAccessibilityLabel("Tock")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        let content = NSHostingController(rootView: CodeList(
            store: store,
            addService: { [weak self] in self?.showSettings(.editor(nil)) },
            showSettings: { [weak self] in self?.showSettings(.list) },
            dismiss: { [weak self] in self?.popover.performClose(nil) }))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        NSApplication.shared.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showSettings(_ screen: SettingsScreen) {
        popover.performClose(nil)
        navigation.screen = screen
        if settingsWindow == nil {
            let size = NSSize(width: 540, height: 640)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Tock Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 480, height: 460)
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store, navigation: navigation))
            window.setContentSize(size)
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApplication.shared.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        navigation.screen = .list
    }

    func popoverDidShow(_ notification: Notification) {
        store.popoverShown = true
        // A transient popover in an accessory app misses clicks on the desktop and menu bar, so close on any outside click.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.popoverShown = false
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    func applicationDidResignActive(_ notification: Notification) {
        popover.performClose(nil)
    }
}

/// Text fields get Command-C, V, X, A, and Z only from matching menu items. An accessory app shows no menu bar, but
/// AppKit still routes key equivalents through its main menu.
private func editMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let item = NSMenuItem()
    item.submenu = edit
    let menu = NSMenu()
    menu.addItem(item)
    return menu
}

/// The app icon's countdown ring and keyhole as an 18 pt template image.
private func menuBarGlyph() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let ring = NSBezierPath()
        // Three quarters of a ring, starting at twelve o'clock and running clockwise, like the icon.
        ring.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.9, startAngle: 270, endAngle: 180, clockwise: false)
        ring.lineWidth = 1.9
        ring.lineCapStyle = .round
        NSColor.black.setStroke()
        ring.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.3, y: 5.4, width: 3.4, height: 3.4)).fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 8.2, y: 7.6))
        stem.line(to: NSPoint(x: 9.8, y: 7.6))
        stem.line(to: NSPoint(x: 10.4, y: 12.4))
        stem.line(to: NSPoint(x: 7.6, y: 12.4))
        stem.close()
        stem.fill()
        return true
    }
    image.isTemplate = true
    return image
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
