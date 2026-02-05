import Cocoa
import Combine
import SwiftUI

/// App delegate for handling permissions and menubar setup
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    // Managers
    let keyboardSimulator = KeyboardSimulator()
    let joyConManager = JoyConManager()
    let settings = AppSettings.shared

    // Track the previously active app for focus restoration
    private var previousActiveApp: NSRunningApplication?

    // Track when we were last activated (to determine if URL event caused activation)
    private var lastActivationTime: Date?

    // Combine cancellables for observing state
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances — quit if another JoyConCode is already running
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if running.count > 1 {
            NSApplication.shared.terminate(nil)
            return
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        setupMenuBar()
        setupJoyConHandling()
        setupURLHandler()
        setupFocusTracking()
        setupStatusIconObserver()
        checkPermissions()
    }

    /// Track when another app is about to lose focus to us
    private func setupFocusTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillBecomeActive),
            name: NSApplication.willBecomeActiveNotification,
            object: nil
        )
    }

    /// Capture the frontmost app BEFORE we become active (critical for focus restoration)
    @objc private func appWillBecomeActive(_ notification: Notification) {
        // Record activation time to detect if URL event caused this activation
        lastActivationTime = Date()

        // At this moment, we're about to become active but haven't yet
        // So frontmostApplication is still the PREVIOUS app
        let frontmost = NSWorkspace.shared.frontmostApplication

        // Only capture if it's not ourselves (avoid self-reference)
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousActiveApp = frontmost
            print("📍 Captured previous app: \(frontmost?.localizedName ?? "unknown")")
        }
    }

    private func setupStatusIconObserver() {
        Publishers.CombineLatest(settings.$isEnabled, joyConManager.$isConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled, isConnected in
                self?.updateStatusIcon(active: isEnabled && isConnected)
            }
            .store(in: &cancellables)
    }

    /// Register handler for custom URL scheme (joyconcode://, legacy: gesturecode://)
    private func setupURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Handle incoming URL events (joyconcode://joycon/rumble)
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        // Note: previousActiveApp is already captured by appWillBecomeActive notification
        // which fires BEFORE we become active (correct timing for focus restoration)

        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        guard let scheme = url.scheme, scheme == "joyconcode" || scheme == "gesturecode" else {
            print("Unknown URL: \(urlString)")
            return
        }

        if url.host == "joycon" {
            let command = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch command {
            case "rumble":
                joyConManager.rumbleOnce()
            default:
                print("Unknown joycon command: \(command)")
            }
        } else {
            print("Unknown URL: \(urlString)")
            return
        }

        // Only restore focus if we were JUST activated (within last 500ms)
        // This indicates the URL event caused the activation, not a prior user action
        let wasJustActivated = lastActivationTime.map { Date().timeIntervalSince($0) < 0.5 } ?? false
        if wasJustActivated {
            restoreFocusToPreviousApp()
        }
        lastActivationTime = nil
    }

    /// Restore focus to the previous app to prevent focus stealing from URL scheme activation
    private func restoreFocusToPreviousApp() {
        // Use a small delay to ensure URL event is fully processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Deactivate ourselves first
            NSApp.deactivate()

            // Restore focus to the previously tracked app
            if let previous = self.previousActiveApp, !previous.isTerminated {
                let success = previous.activate(options: [.activateIgnoringOtherApps])
                if success {
                    print("✓ Restored focus to \(previous.localizedName ?? "app")")
                } else {
                    print("✗ Failed to restore focus to \(previous.localizedName ?? "app")")
                    // Fallback: hide ourselves to let system restore
                    NSApp.hide(nil)
                }
            } else {
                // No previous app or it terminated, hide ourselves
                NSApp.hide(nil)
                print("⚠ No previous app available, hiding JoyConCode")
            }

            // Clear the tracked app
            self.previousActiveApp = nil
        }
    }

    private func updateStatusIcon(active: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = active ? "gamecontroller.fill" : "gamecontroller"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Joy-Con Control")
    }

    /// Setup the menubar status item and popover
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "Joy-Con Control")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover with SwiftUI content
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView(
                keyboardSimulator: keyboardSimulator,
                joyConManager: joyConManager
            )
        )
    }

    /// Setup Joy-Con handling callbacks
    private func setupJoyConHandling() {
        joyConManager.onKeyChord = { [weak self] chord in
            self?.keyboardSimulator.simulateKey(
                chord: chord,
                description: "Joy-Con: \(chord.displayString())"
            )
        }
    }


    /// Check and request necessary permissions
    private func checkPermissions() {
        // Accessibility permissions
        keyboardSimulator.checkAccessibilityPermissions()
    }

    /// Toggle the popover visibility
    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure popover is focused
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        joyConManager.setMappingMode(false)
    }
}
