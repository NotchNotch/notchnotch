// The message and UI node types are generated from schemas/ into
// generated.ts; this file adds what the schemas don't describe.
export * from "./generated";

export const PROTOCOL_VERSION = 1 as const;
export const MAX_MESSAGE_BYTES = 262_144;

export interface RuntimeNotice {
  protocolVersion: 1;
  type: "error" | "log";
  extensionID: string;
  message: string;
}

export type MediaCommand = "playPause" | "previous" | "next" | "seek" | "volume" | "shuffle" | "repeat" | "openPlayer";
export interface MediaRequest { command: MediaCommand; value?: number }
