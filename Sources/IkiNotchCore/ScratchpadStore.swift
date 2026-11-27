import AppKit
import Foundation

/// Auto-saving quick scratchpad backed by UserDefaults (0% background CPU).
public final class ScratchpadStore: ObservableObject {
    private let key = "ikinotch.scratchpadText"
    private let defaults: UserDefaults

    @Published public var text: String {
        didSet {
            defaults.set(text, forKey: key)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.text = defaults.string(forKey: key) ?? ""
    }

    public func copyToClipboard() {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public func clear() {
        text = ""
    }
}
