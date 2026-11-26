import AppKit

enum OrbitBrandIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "OrbitMenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        if let url = Bundle.main.url(forResource: "orbit-menu-icon", withExtension: "svg"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        return NSApplication.shared.applicationIconImage
    }()
}
