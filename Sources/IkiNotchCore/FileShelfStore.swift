import Foundation

public struct ShelfFileItem: Identifiable, Equatable {
    public let id: UUID
    public let url: URL

    public var fileName: String {
        url.lastPathComponent
    }

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }
}

/// Lightweight in-memory File Drop Shelf (zero disk copy, zero background CPU).
public final class FileShelfStore: ObservableObject {
    @Published public private(set) var items: [ShelfFileItem] = []

    public init() {}

    public func add(urls: [URL]) {
        for rawURL in urls {
            let standardized = rawURL.standardizedFileURL
            guard standardized.isFileURL else { continue }
            if !items.contains(where: { $0.url == standardized }) {
                items.insert(ShelfFileItem(url: standardized), at: 0)
            }
        }
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clear() {
        items.removeAll()
    }
}
