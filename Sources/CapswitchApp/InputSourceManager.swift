import AppKit
import Carbon
import Foundation

final class InputSourceManager {
    private struct Source {
        let inputSource: TISInputSource
        let id: String
    }

    private var orderedSources: [Source] = []
    private var sourceIcons: [String: NSImage] = [:]

    var currentDisplayName: String {
        guard let source = currentSource() else {
            return "-"
        }
        return property(source, key: kTISPropertyLocalizedName)
            ?? property(source, key: kTISPropertyInputSourceID)
            ?? "-"
    }

    var currentShortName: String {
        let name = currentDisplayName
        if let first = name.split(whereSeparator: { $0 == " " || $0 == "-" }).first,
           !first.isEmpty {
            return String(first).uppercased()
        }
        return name
    }

    var currentIcon: NSImage? {
        guard let source = currentSource(),
              let id = property(source, key: kTISPropertyInputSourceID) else {
            return nil
        }
        if let icon = sourceIcons[id] {
            return icon
        }

        var icon: NSImage?
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
            icon = NSImage(contentsOf: url)
        }
        if icon?.isValid != true,
           let pointer = TISGetInputSourceProperty(source, kTISPropertyIconRef) {
            // Keyboard layouts may expose only the legacy IconRef representation.
            icon = NSImage(iconRef: OpaquePointer(pointer))
        }
        guard let icon, icon.isValid else {
            return nil
        }

        icon.size = NSSize(width: 16, height: 16)
        // Preserve the source icon's colors, including flags and custom layouts.
        icon.isTemplate = false
        sourceIcons[id] = icon
        return icon
    }

    func refresh() {
        orderedSources = enabledKeyboardSourcesInUserOrder()
        sourceIcons.removeAll()
    }

    @discardableResult
    func selectNextInputSource() -> Bool {
        let sources = orderedSources
        guard sources.count > 1 else {
            return false
        }

        let currentID = currentSource().flatMap {
            property($0, key: kTISPropertyInputSourceID)
        }

        let currentIndex = currentID.flatMap { id in
            sources.firstIndex { $0.id == id }
        }
        let nextIndex = ((currentIndex ?? -1) + 1) % sources.count
        return TISSelectInputSource(sources[nextIndex].inputSource) == noErr
    }

    private func enabledKeyboardSourcesInUserOrder() -> [Source] {
        let allSources = TISCreateInputSourceList(nil, false)
            .takeRetainedValue() as NSArray as! [TISInputSource]

        let sources = allSources.compactMap { inputSource -> Source? in
            guard isEnabled(inputSource),
                  property(inputSource, key: kTISPropertyInputSourceCategory)
                    == (kTISCategoryKeyboardInputSource as String),
                  let id = property(inputSource, key: kTISPropertyInputSourceID) else {
                return nil
            }

            return Source(inputSource: inputSource, id: id)
        }

        var byID: [String: Source] = [:]
        for source in sources {
            byID[source.id] = source
        }

        let configuredIDs = configuredInputSourceIDs()
        var usedIDs: Set<String> = []
        var ordered: [Source] = []

        for id in configuredIDs {
            if let source = byID[id], usedIDs.insert(id).inserted {
                ordered.append(source)
            }
        }

        ordered.append(contentsOf: sources.filter {
            usedIDs.insert($0.id).inserted
        })
        return ordered
    }

    private func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func configuredInputSourceIDs() -> [String] {
        guard let entries = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .array(forKey: "AppleEnabledInputSources") as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { $0["InputSourceID"] as? String }
    }

    private func isEnabled(_ inputSource: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyInputSourceIsEnabled
        ) else {
            return false
        }

        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func property(
        _ inputSource: TISInputSource,
        key: CFString
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(pointer)
            .takeUnretainedValue() as String
    }
}
