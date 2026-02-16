import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let gammaController = GammaController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu bar only, no dock icon
        gammaController.registerReconfigurationCallback()
        gammaController.setupWakeNotification()
        if gammaController.isEnabled {
            gammaController.applyToAllDisplays()
        }
        gammaController.startReapplyTimerIfNeeded()
        setupStatusItem()
        setupPopover()
        setupMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gammaController.applicationWillTerminate()
        gammaController.restoreAllDisplays()
        gammaController.unregisterReconfigurationCallback()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(NSMenuItem(title: "Quit ScreenWarmth", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Screen Warmth") {
            img.isTemplate = true
            statusItem?.button?.image = img
        } else {
            // Fallback: small filled square so the menu bar item is clickable
            let size = NSSize(width: 18, height: 18)
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.controlTextColor.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)).fill()
            img.unlockFocus()
            img.isTemplate = true
            statusItem?.button?.image = img
        }
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = PopoverContentViewController(
            gammaController: gammaController,
            onQuit: { [weak self] in
                self?.popover?.close()
                NSApp.terminate(nil)
            }
        )
        popover?.contentSize = NSSize(width: 240, height: 180)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
