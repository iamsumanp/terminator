import AppKit
import SwiftUI
import Carbon
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private let toggleHotKeyID: UInt32 = 1
    private var isToggleHotKeyDown = false
    private var sizeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePanel()
        configureHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "✶"
            button.font = .systemFont(ofSize: 16, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item
    }

    private func configurePanel() {
        let controller = NSHostingController(rootView: ContentView(state: state))
        controller.view.frame.size = NSSize(width: state.panelWidth, height: state.panelHeight)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: state.panelWidth, height: state.panelHeight)
        popover.contentViewController = controller
        self.popover = popover

        sizeCancellable = state.$panelWidth
            .combineLatest(state.$panelHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] width, height in
                guard let self else { return }
                let size = NSSize(width: width, height: height)
                self.popover?.contentSize = size
                controller.view.frame.size = size
            }
    }

    private func configureHotkey() {
        registerHotkeyHandler()
        registerToggleHotkey()
    }

    private func registerHotkeyHandler() {
        var eventSpecs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, hotKeyID.id == appDelegate.toggleHotKeyID {
                    let eventKind = GetEventKind(eventRef)
                    if eventKind == UInt32(kEventHotKeyPressed) {
                        if !appDelegate.isToggleHotKeyDown {
                            appDelegate.isToggleHotKeyDown = true
                            DispatchQueue.main.async {
                                appDelegate.togglePanel()
                            }
                        }
                    } else if eventKind == UInt32(kEventHotKeyReleased) {
                        appDelegate.isToggleHotKeyDown = false
                    }
                }
                return noErr
            },
            eventSpecs.count,
            &eventSpecs,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )
    }

    private func registerToggleHotkey() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("TRMN"), id: toggleHotKeyID)
        let keyCode: UInt32 = 40 // K
        let modifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for scalar in string.utf8.prefix(4) {
            result = (result << 8) + UInt32(scalar)
        }
        return result
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        state.requestInputFocus()
    }
}
