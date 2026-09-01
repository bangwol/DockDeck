import ApplicationServices
import Cocoa
import CoreGraphics

final class DockCoordinator {
    static let dockPreferencesDomain = "com.apple.dock" as CFString

    private let logger: (String, String) -> Void
    private var cachedHostScreenID: CGDirectDisplayID?

    private(set) var orientation = "bottom"
    private(set) var autoHides = false

    init(logger: @escaping (String, String) -> Void) {
        self.logger = logger
    }

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    func refresh() {
        orientation = dockOrientation()
        autoHides = dockAutoHides()
        let host =
            autoHides
            ? dockWindowHostScreen()
            : (screenReservingBottomStrip() ?? dockWindowHostScreen())
        cachedHostScreenID = host.flatMap(displayID(of:))
    }

    func resolvePresence() -> DockPresence? {
        guard let mainScreen = mainDisplayScreen() ?? NSScreen.screens.first else { return nil }
        let cachedHost = cachedHostScreenID.flatMap(screen(for:)) ?? mainScreen

        guard orientation == "bottom" else { return .untracked(host: cachedHost) }
        guard let tray = dockIconTrayFrame(flippedAgainst: mainScreen) else {
            return .untracked(host: cachedHost)
        }

        guard autoHides else {
            guard let trayHost = screenHosting(tray) else {
                return .untracked(host: cachedHost)
            }
            return .revealed(tray: tray, host: trayHost)
        }

        guard let host = screenHosting(tray) else {
            logger("verdict", "tray \(tray) touches no screen -> concealed")
            return .concealed(host: cachedHost)
        }
        let concealed = tray.maxY <= host.frame.minY + 1
        logger(
            "verdict",
            "tray.maxY=\(tray.maxY) vs host.frame.minY+1=\(host.frame.minY + 1) -> "
                + (concealed ? "concealed" : "revealed"))
        return concealed ? .concealed(host: host) : .revealed(tray: tray, host: host)
    }

    func frames(for presence: DockPresence) -> DockPanelFrames {
        switch presence {
        case .revealed(let tray, let host):
            return DockPanelLayout.frames(tray: tray, hostFrame: host.frame)
        case .concealed(let host), .untracked(let host):
            return fallbackFrames(on: host)
        }
    }

    func fallbackFrames(on screen: NSScreen) -> DockPanelFrames {
        let reserved = screen.visibleFrame.minY - screen.frame.minY
        return DockPanelLayout.fallbackFrames(
            hostFrame: screen.frame, reservedHeight: reserved)
    }

    func mainDisplayScreen() -> NSScreen? {
        screen(for: CGMainDisplayID())
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    func screenWithGreatestIntersection(with rect: NSRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
    }

    func describe(_ displayID: CGDirectDisplayID?) -> String {
        guard let displayID else { return "none" }
        guard let screen = screen(for: displayID) else { return "\(displayID) (gone)" }
        return "\(displayID) \(screen.frame)"
    }

    private func dockOrientation() -> String {
        CFPreferencesAppSynchronize(Self.dockPreferencesDomain)
        return
            (CFPreferencesCopyAppValue("orientation" as CFString, Self.dockPreferencesDomain)
            as? String) ?? "bottom"
    }

    private func dockAutoHides() -> Bool {
        (CFPreferencesCopyAppValue("autohide" as CFString, Self.dockPreferencesDomain) as? Bool)
            ?? false
    }

    private func dockIconTrayFrame(flippedAgainst mainScreen: NSScreen) -> NSRect? {
        guard let dockApp = dockApplication() else { return nil }
        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)

        var childrenRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement],
            let list = children.first(where: { axRole(of: $0) == (kAXListRole as String) }),
            let position = axPoint(list, kAXPositionAttribute as CFString),
            let size = axSize(list, kAXSizeAttribute as CFString)
        else {
            return nil
        }

        let flippedY = mainScreen.frame.maxY - position.y - size.height
        let frame = NSRect(x: position.x, y: flippedY, width: size.width, height: size.height)
        logger("tray", "ax position \(position) size \(size) -> \(frame)")
        return frame
    }

    private func axRole(of element: AXUIElement) -> String? {
        var roleRef: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                == .success
        else {
            return nil
        }
        return roleRef as? String
    }

    private func axPoint(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func axSize(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(
        _ element: AXUIElement, _ attribute: CFString, type: AXValueType
    ) -> AXValue? {
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success,
            let valueRef,
            CFGetTypeID(valueRef) == AXValueGetTypeID()
        else {
            return nil
        }
        let value = valueRef as! AXValue
        guard AXValueGetType(value) == type else { return nil }
        return value
    }

    private func screenHosting(_ rect: NSRect) -> NSScreen? {
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(centre) }) { return hit }
        return screenWithGreatestIntersection(with: rect)
    }

    private func screenReservingBottomStrip() -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.minY - $0.frame.minY > 4 }
    }

    private func dockWindowHostScreen() -> NSScreen? {
        guard let dockApp = dockApplication(), let mainScreen = mainDisplayScreen() else {
            return nil
        }
        guard
            let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return nil
        }

        let matches = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == dockApp.processIdentifier
                && ($0[kCGWindowLayer as String] as? Int) == 20
        }
        guard matches.count == 1,
            let boundsValue = matches[0][kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsValue)
        else {
            logger(
                "dockwindow",
                "expected exactly one layer-20 Dock window, got \(matches.count); "
                    + "falling back to the main display")
            return nil
        }

        let appKitY = mainScreen.frame.maxY - (bounds.origin.y + bounds.height)
        let frame = NSRect(
            x: bounds.origin.x, y: appKitY, width: bounds.width, height: bounds.height)
        logger("dockwindow", "bounds \(bounds) -> \(frame)")
        return screenWithGreatestIntersection(with: frame)
    }

    private func dockApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.dock"
        }
    }
}
