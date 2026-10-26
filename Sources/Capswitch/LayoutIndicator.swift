/// Use stable TIS identifiers rather than localized names or language tags:
/// British and other English layouts must still light the indicator.
public enum LayoutIndicator {
    public static func capsLEDEnabled(inputSourceID: String?) -> Bool? {
        guard let inputSourceID, !inputSourceID.isEmpty else {
            return nil
        }
        return inputSourceID != "com.apple.keylayout.US"
            && inputSourceID != "com.apple.keylayout.ABC"
    }
}
