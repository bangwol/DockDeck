import Cocoa

if let control = DockDeckControl.parse(Array(CommandLine.arguments.dropFirst())) {
    exit(control.run())
}
if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--login-item") || $0.hasPrefix("--enable-login") || $0.hasPrefix("--disable-login") || $0.hasPrefix("--stop-installed") }) {
    FileHandle.standardError.write(Data("Invalid DockDeck control arguments.\n".utf8))
    exit(2)
}
if DockDeckControl.activateExistingApp() { exit(0) }
DockDeckControl.prepareLog()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
