import Foundation
import NotchConnections
import NotchProtocol

/// The app's system capabilities: data an extension would otherwise need a
/// native helper for. `NotchConnections` hands each consented stream to `session`.
public enum SystemCapabilities {
    @MainActor
    public static func session(for capability: SystemCapability, extensionID: String,
                               send: @escaping @MainActor (JSONValue) -> Void) -> (any CapabilitySession)? {
        switch capability {
        case .calendar: CalendarCapability(extensionID: extensionID, send: send)
        case .nowPlaying: NowPlayingCapability(send: send)
        case .battery: BatteryCapability(send: send)
        case .system: SystemStatusCapability(send: send)
        }
    }

    /// Whether a capability kept anything for this extension, such as chosen calendars.
    public static func hasSavedData(extensionID: String) -> Bool {
        CalendarSelections.ids(for: extensionID) != nil
    }

    /// Deletes what the capabilities saved for an extension that was uninstalled.
    public static func forget(extensionID: String) {
        CalendarSelections.set(nil, for: extensionID)
    }
}

enum CapabilityError: Error { case unknownMethod }

/// The JSON-RPC 2.0 side shared by every capability: it checks each request,
/// bounds the work in flight and answers it. Capabilities only handle methods.
@MainActor
class JSONRPCCapability: CapabilitySession {
    private let send: @MainActor (JSONValue) -> Void
    private var pending = 0
    private(set) var stopped = false

    init(send: @escaping @MainActor (JSONValue) -> Void) { self.send = send }

    /// Answers one method call; throw `CapabilityError.unknownMethod` for methods it doesn't have.
    func handle(_ method: String, _ params: JSONValue?) async throws -> JSONValue { throw CapabilityError.unknownMethod }
    /// Releases what the capability holds; called once.
    func finish() {}

    func receive(_ message: JSONValue) {
        guard !stopped else { return }
        guard case let .object(fields) = message, fields["jsonrpc"] == .string("2.0"),
              case let .string(method)? = fields["method"] else {
            reject(.null, code: -32600, message: "Invalid JSON-RPC request"); return
        }
        // Notifications from the extension need no answer, and no capability takes any.
        guard let id = fields["id"] else { return }
        switch id {
        case .string, .number: break
        default: reject(.null, code: -32600, message: "Invalid request id"); return
        }
        guard pending < 32 else { reject(id, code: -32000, message: "Too many pending requests"); return }
        pending += 1
        Task { [self] in
            defer { pending -= 1 }
            do {
                let result = try await handle(method, fields["params"])
                emit(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
            } catch CapabilityError.unknownMethod {
                reject(id, code: -32601, message: "Unknown method: \(method)")
            } catch {
                reject(id, code: -32602, message: error.localizedDescription)
            }
        }
    }

    func notify(_ method: String, _ params: JSONValue) {
        emit(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]))
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        finish()
    }

    private func reject(_ id: JSONValue, code: Int, message: String) {
        emit(.object(["jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(String(message.prefix(1024)))])]))
    }

    private func emit(_ value: JSONValue) {
        guard !stopped, let data = try? JSONEncoder().encode(value), data.count <= maximumConnectionPayloadBytes else { return }
        send(value)
    }

    /// Encodes a result, giving `shrink` a chance to drop detail until it fits
    /// inside one stream message with room for the JSON-RPC fields.
    static func json<T: Encodable>(_ value: T, shrink: (inout T) -> Bool = { _ in false }) -> JSONValue {
        var bounded = value
        while let data = try? JSONEncoder().encode(bounded) {
            if data.count <= maximumConnectionPayloadBytes - 1024 {
                return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
            }
            guard shrink(&bounded) else { return .null }
        }
        return .null
    }
}
