import AppKit

let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate

// Belt-and-braces: also set via Info.plist's LSUIElement once bundled as a
// .app. Setting it here means the raw SPM binary behaves correctly too
// (no Dock icon, no app switcher entry) even before it's packaged.
app.setActivationPolicy(.accessory)

app.run()
