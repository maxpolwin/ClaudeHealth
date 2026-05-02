import SwiftUI
import AppKit

/// PNG export + native share-sheet helpers. Renders a SwiftUI view to an NSImage
/// at @3x and presents NSSharingServicePicker with the result, OR saves to disk
/// via NSSavePanel.
@MainActor
enum Sharing {

    /// Render the given SwiftUI view to a Retina NSImage.
    static func render<V: View>(_ view: V, scale: CGFloat = 3.0) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.nsImage
    }

    /// Show the system share sheet anchored to a view's bounds, with the rendered image as the payload.
    static func share<V: View>(view: V, anchor: NSView, edge: NSRectEdge = .minY) {
        guard let image = render(view) else {
            NSSound.beep(); return
        }
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

    /// "Save as PNG…" panel.
    static func savePNG<V: View>(view: V, suggestedName: String = "ClaudeHealth.png") {
        guard let image = render(view),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            NSSound.beep(); return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.title = "Save Dashboard PNG"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
            } catch {
                Log.sharing.error("Save PNG failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
