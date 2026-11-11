import Foundation
import NotchProtocol

/// `calendar`: upcoming events from the calendars on this Mac. Read-only; the
/// methods are those of the Calendar helper it replaced (extensions/calendar/ADAPTER.md).
@MainActor
final class CalendarCapability: JSONRPCCapability {
    private let source: CalendarSource
    private var connecting = false

    init(extensionID: String, send: @escaping @MainActor (JSONValue) -> Void) {
        source = CalendarSource(extensionID: extensionID)
        super.init(send: send)
        source.onChange = { [weak self] status in self?.notify("calendar/state", Self.bounded(status)) }
        source.start()
    }

    override func finish() { source.stop() }

    override func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "calendar/getState":
            source.refresh()
            return Self.bounded(source.status)
        case "calendar/connect":
            guard !connecting else { throw ProtocolError.invalid("Calendar access request is already open") }
            connecting = true
            defer { connecting = false }
            await source.connect()
            return Self.bounded(source.status)
        case "calendar/select":
            guard case let .object(fields)? = params, case let .array(values)? = fields["ids"] else {
                throw ProtocolError.invalid("Expected calendar identifiers")
            }
            let ids = values.compactMap { value -> String? in if case let .string(id) = value { id } else { nil } }
            guard ids.count == values.count else { throw ProtocolError.invalid("Expected calendar identifiers") }
            try source.select(ids)
            return Self.bounded(source.status)
        case "calendar/open":
            try await source.openCalendar()
            return .null
        case "calendar/join":
            guard case let .object(fields)? = params, case let .string(id)? = fields["id"] else {
                throw ProtocolError.invalid("Expected an event identifier")
            }
            try source.join(id)
            return .null
        default:
            throw CapabilityError.unknownMethod
        }
    }

    private static func bounded(_ status: CalendarStatus) -> JSONValue {
        json(status) { status in
            if status.events.count > 1 { status.events.removeLast(); return true }
            if !status.calendars.isEmpty { status.calendars.removeLast(); return true }
            return false
        }
    }
}
