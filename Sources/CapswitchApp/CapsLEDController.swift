import CapswitchHID
import Foundation

/// All public methods run on the main thread. HID output can block, so writes
/// are serialized on a worker queue and periodic updates are coalesced.
final class CapsLEDController {
    private let queue = DispatchQueue(label: "macoc.caps-led", qos: .utility)
    private var pending = false
    private var requestedState: Bool?
    private var generation = 0
    private(set) var status = "Inactive"

    func update(enabled: Bool) {
        requestedState = enabled
        guard !pending else { return }
        pending = true
        let generation = self.generation
        queue.async { [weak self] in
            var count: UInt32 = 0
            let result = CapswitchWriteCapsLED(enabled, &count)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.pending = false
                if result != 0 {
                    self.status = "Unavailable on some keyboards (code \(result))"
                } else {
                    self.status = count == 0 ? "No supported LEDs" : (enabled ? "On" : "Off")
                }
                if let latest = self.requestedState, latest != enabled {
                    self.update(enabled: latest)
                }
            }
        }
    }

    func restore() {
        guard requestedState != nil else { return }
        generation += 1
        requestedState = nil
        pending = false
        // Finish outstanding writes before restoring, including on process exit.
        let result: Int32 = queue.sync {
            var locked = false
            let readResult = CapswitchReadCapsLock(&locked)
            guard readResult == 0 else { return readResult }
            var count: UInt32 = 0
            return CapswitchWriteCapsLED(locked, &count)
        }
        status = result == 0 ? "Inactive" : "Restore failed (code \(result))"
    }
}
