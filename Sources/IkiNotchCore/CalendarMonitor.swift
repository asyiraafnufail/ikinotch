import AppKit
import EventKit
import Foundation

public struct CalendarEventInfo: Equatable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let colorHex: String

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        colorHex: String
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
    }

    public func formattedTimeRange(now: Date = Date()) -> String {
        if isAllDay {
            return "All Day"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        if startDate <= now && endDate > now {
            return "Now • until \(end)"
        }
        return "\(start) – \(end)"
    }
}

public enum CalendarAuthState: Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Event-driven Calendar monitor backed by EKEventStore notifications (zero polling).
public final class CalendarMonitor: ObservableObject {
    @Published public private(set) var authState: CalendarAuthState = .notDetermined
    @Published public private(set) var nextEvent: CalendarEventInfo?

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init(startListening: Bool = true) {
        if startListening {
            updateAuthStateAndRefresh()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func updateAuthStateAndRefresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .authorized:
                authState = .authorized
                attachObserverIfNeeded()
                refreshNextEvent()
            case .notDetermined:
                authState = .notDetermined
                nextEvent = nil
            default:
                authState = .denied
                nextEvent = nil
            }
        } else {
            switch status {
            case .authorized:
                authState = .authorized
                attachObserverIfNeeded()
                refreshNextEvent()
            case .notDetermined:
                authState = .notDetermined
                nextEvent = nil
            default:
                authState = .denied
                nextEvent = nil
            }
        }
    }

    public func requestAccess() {
        let completion: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAuthStateAndRefresh()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    private func attachObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refreshNextEvent()
        }
    }

    public func refreshNextEvent(now: Date = Date()) {
        guard authState == .authorized else {
            nextEvent = nil
            return
        }

        let calendar = Calendar.current
        guard let endOfWindow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else {
            return
        }

        let predicate = store.predicateForEvents(withStart: now, end: endOfWindow, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return !lhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }

        guard let first = events.first else {
            nextEvent = nil
            return
        }

        nextEvent = CalendarEventInfo(
            title: first.title?.isEmpty == false ? first.title : "Untitled Event",
            startDate: first.startDate,
            endDate: first.endDate,
            isAllDay: first.isAllDay,
            calendarTitle: first.calendar.title,
            colorHex: Self.hexString(from: first.calendar.cgColor)
        )
    }

    private static func hexString(from cgColor: CGColor?) -> String {
        guard let cgColor,
              let rgb = cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = rgb.components,
              components.count >= 3 else {
            return "#0A84FF"
        }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
