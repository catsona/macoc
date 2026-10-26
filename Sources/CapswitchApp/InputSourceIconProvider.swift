import AppKit
import Carbon

final class InputSourceIconProvider {
    private static let imageSelector = NSSelectorFromString("imageForTISInputSource:")
    private let systemIconManager: NSObject?

    convenience init() {
        self.init(systemIconManager: Self.makeSystemIconManager())
    }

    init(systemIconManager: NSObject?) {
        self.systemIconManager = systemIconManager
    }

    func icon(for source: TISInputSource) -> NSImage? {
        if let manager = systemIconManager,
           manager.responds(to: Self.imageSelector),
           let image = manager.perform(Self.imageSelector, with: source)?
            .takeUnretainedValue() as? NSImage,
           image.isValid {
            // The manager owns its cached images. Preserve template rendering and
            // the native aspect ratio (e.g. 22 x 16 for the US and RU badges).
            return image.copy() as? NSImage
        }

        // Custom input methods can supply their own artwork through the public API.
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) else {
            return nil
        }
        let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
        guard let image = NSImage(contentsOf: url), image.isValid,
              image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        image.size = NSSize(width: 16 * image.size.width / image.size.height, height: 16)
        return image
    }

    private static func makeSystemIconManager() -> NSObject? {
        // TIS IconRef can be the same generic keyboard for different locales.
        // macOS's input menu gets locale badges from this private framework.
        // Resolve it at runtime so a missing framework/API falls back to text.
        guard let bundle = Bundle(
            path: "/System/Library/PrivateFrameworks/KeyboardLayouts.framework"
        ), bundle.load(),
            let managerClass = NSClassFromString("KLInputSourceIconManager") as? NSObject.Type else {
            return nil
        }
        let factory = NSSelectorFromString("managerWithAllInputSources")
        guard managerClass.responds(to: factory) else {
            return nil
        }
        return managerClass.perform(factory)?.takeUnretainedValue() as? NSObject
    }
}
