import Cocoa
import CoreGraphics

extension AppDelegate {
    func mainDisplayScreen() -> NSScreen? {
        dockCoordinator.mainDisplayScreen()
    }

    func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        dockCoordinator.screen(for: displayID)
    }

    func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        dockCoordinator.displayID(of: screen)
    }

    func screenWithGreatestIntersection(with rect: NSRect) -> NSScreen? {
        dockCoordinator.screenWithGreatestIntersection(with: rect)
    }

    func describe(_ displayID: CGDirectDisplayID?) -> String {
        dockCoordinator.describe(displayID)
    }
}
