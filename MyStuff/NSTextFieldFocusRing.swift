#if os(macOS)
import AppKit

/// Hides the default focus ring on NSTextField (used by SwiftUI TextField with .roundedBorder).
extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
#endif
