import AppKit
import Carbon

// Runs without XCTest so Command Line Tools alone can check the native icon API.
@main
enum InputSourceIconTests {
    static func main() {
        let sources = TISCreateInputSourceList(nil, true)
            .takeRetainedValue() as NSArray as! [TISInputSource]
        let provider = InputSourceIconProvider()
        let unavailableProvider = InputSourceIconProvider(systemIconManager: nil)
        let incompatibleProvider = InputSourceIconProvider(systemIconManager: NSObject())
        var pixelsByScale: [Int: [Data]] = [1: [], 2: []]

        for id in ["com.apple.keylayout.US", "com.apple.keylayout.Russian", "com.apple.keylayout.British"] {
            guard let source = sources.first(where: { inputSourceID($0) == id }),
                  let icon = provider.icon(for: source) else {
                fatalError("Missing system locale badge: \(id)")
            }
            precondition(icon.isValid && icon.isTemplate, "Badge must adapt to menu bar appearance")
            precondition(icon.size.width > icon.size.height, "Do not squash the locale badge to a square")

            for scale in [1, 2] {
                let pixels = render(icon, scale: scale)
                precondition(!pixelsByScale[scale]!.contains(pixels), "Locales have identical icons: \(id)")
                pixelsByScale[scale]!.append(pixels)
            }

            // Built-in layouts have no public icon URL. Missing private API must
            // yield nil so the caller displays a name, not a generic keyboard.
            precondition(TISGetInputSourceProperty(source, kTISPropertyIconImageURL) == nil)
            precondition(unavailableProvider.icon(for: source) == nil)
            precondition(incompatibleProvider.icon(for: source) == nil)

            // Resizing a returned image must not corrupt the system manager's cache.
            let originalSize = icon.size
            icon.size = NSSize(width: 1, height: 1)
            precondition(provider.icon(for: source)?.size == originalSize)
        }
        print("Input source icons: PASS (US/Russian/British differ at 1x and 2x; fallback and image ownership)")
    }

    private static func inputSourceID(_ source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func render(_ icon: NSImage, scale: Int) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32 * scale,
            pixelsHigh: 24 * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("Cannot create icon rendering context")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        icon.draw(in: NSRect(origin: .zero, size: icon.size))

        let visible = (0..<rep.pixelsHigh).contains { y in
            (0..<rep.pixelsWide).contains { x in
                (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }
        precondition(visible, "Locale badge rendered empty")
        return rep.representation(using: .png, properties: [:])!
    }
}
