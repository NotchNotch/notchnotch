import type { ConnectionCommand, ConnectionEvent, ConnectionResponse, JSONValue } from "@notchnotch/protocol";

// The SDK's channel to the app. Internal: the message shapes may change, so
// extensions use the APIs built on it, never this.

declare global {
  var __notchnotchSend: (json: string) => void;
  var __notchnotchExtensionID: string;
  var __notchnotchConnectionDispatch: ((message: ConnectionResponse | ConnectionEvent) => void) | undefined;
}

let serial = 0;
/** A number no other request or stream in this extension has used. */
export function nextSerial() { return ++serial; }
const pending = new Map<string, { resolve: (value: JSONValue) => void; reject: (error: Error) => void; timer: number }>();
export const listeners = new Set<(event: ConnectionEvent) => void>();

globalThis.__notchnotchConnectionDispatch = (message) => {
  if (message.type === "connectionEvent") {
    for (const listener of listeners) listener(message);
    return;
  }
  const request = pending.get(message.requestID);
  if (!request) return;
  clearTimeout(request.timer);
  pending.delete(message.requestID);
  if (message.error) request.reject(new Error(message.error));
  else request.resolve(message.result ?? null);
};

export function command(connectionID: string, operation: ConnectionCommand["operation"],
                 fields: Pick<ConnectionCommand, "request" | "fetch" | "secret" | "url" | "message" | "sessionID" | "interactive" | "files"> = {}, timeoutMs = 35_000): Promise<JSONValue> {
  if (pending.size >= 32) return Promise.reject(new Error("Too many pending connection operations"));
  const requestID = `connection-${nextSerial()}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(requestID);
      reject(new Error(`Connection operation timed out: ${connectionID || operation}`));
    }, timeoutMs);
    pending.set(requestID, { resolve, reject, timer });
    try {
      globalThis.__notchnotchSend(JSON.stringify({ protocolVersion: 1, type: "connectionCommand",
        extensionID: globalThis.__notchnotchExtensionID, requestID, connectionID, operation, ...fields } satisfies ConnectionCommand));
    } catch (error) {
      clearTimeout(timer); pending.delete(requestID);
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}
