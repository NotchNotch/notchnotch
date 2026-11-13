import type { FileHandle } from "@notchnotch/protocol";
import { command } from "./connections";
export type { FileHandle, FileKind } from "@notchnotch/protocol";

/** One thing dropped on a `DropZone`: a file, a link or text. */
export type DropItem =
  | { kind: "file"; file: FileHandle }
  | { kind: "url"; url: string; title?: string }
  | { kind: "text"; text: string };

/** Uniform type identifiers for `DropZone`'s `accepts`. Any UTI works; these are the common ones. */
export const DropTypes = {
  /** Anything: files, folders, links and text. */
  anything: "public.item",
  files: "public.data",
  folders: "public.folder",
  images: "public.image",
  movies: "public.movie",
  audio: "public.audio",
  pdf: "com.adobe.pdf",
  links: "public.url",
  text: "public.plain-text",
} as const;

type FileRef = FileHandle | string;
const ids = (refs: FileRef | FileRef[]) => (Array.isArray(refs) ? refs : [refs]).map((ref) => typeof ref === "string" ? ref : ref.id);

/**
 * What the app does with the files dropped on your extension. You hold
 * handles, never paths; the app keeps each file's bookmark and acts on it.
 * Handles last across restarts, so you can keep them with `useStoredState`.
 */
export const files = {
  /** Opens the AirDrop sheet for the files. */
  async airDrop(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "airDrop", ids: ids(refs) } }, 120_000);
  },
  /** Opens them with their default app, or the app with this bundle identifier. */
  async open(refs: FileRef | FileRef[], app?: string): Promise<void> {
    await command("", "files", { files: { action: "open", ids: ids(refs), ...(app ? { app } : {}) } });
  },
  /** Selects them in Finder. */
  async reveal(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "reveal", ids: ids(refs) } });
  },
  /** Opens the macOS Share menu for the files, beside the pointer: AirDrop, Messages, Mail, Notes and more. */
  async share(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "share", ids: ids(refs) } }, 120_000);
  },
  /** A menu beside the pointer of the apps that open the files; the person picks one. */
  async openWith(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "openWith", ids: ids(refs) } }, 120_000);
  },
  /** Puts the files on the clipboard, to paste in Finder, Mail or any app. */
  async copyToClipboard(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "clipboard", ids: ids(refs) } });
  },
  /** Shows them in Quick Look. */
  async preview(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "preview", ids: ids(refs) } });
  },
  /** The file's thumbnail, as Finder shows it, as a PNG data URL for `Artwork`. */
  async thumbnail(ref: FileRef, size = 64): Promise<string> {
    return await command("", "files", { files: { action: "thumbnail", ids: ids(ref), size } }) as string;
  },
  /** Copies them into a folder the person picks. False when they cancel. */
  async copy(refs: FileRef | FileRef[]): Promise<boolean> {
    return await command("", "files", { files: { action: "copy", ids: ids(refs) } }, 600_000) === true;
  },
  /** Moves them into a folder the person picks. False when they cancel. */
  async move(refs: FileRef | FileRef[]): Promise<boolean> {
    return await command("", "files", { files: { action: "move", ids: ids(refs) } }, 600_000) === true;
  },
  /**
   * Copies the files into NotchNotch's own folder and returns handles to the
   * copies, in the same order; the originals' handles are released. A copy
   * survives the original being moved or deleted, and is deleted when you
   * release it.
   */
  async keepCopy(refs: FileRef | FileRef[]): Promise<FileHandle[]> {
    const copies = await command("", "files", { files: { action: "keepCopy", ids: ids(refs) } }, 600_000);
    return Array.isArray(copies) ? copies as unknown as FileHandle[] : [];
  },
  /** Lets go of handles you no longer keep, so the app forgets their files. */
  async release(refs: FileRef | FileRef[]): Promise<void> {
    await command("", "files", { files: { action: "release", ids: ids(refs) } });
  },
  /**
   * The file's contents, up to 144 KiB from `offset`. Needs the `file-read`
   * permission. Read a larger file in parts by moving `offset`.
   */
  async read(ref: FileRef, options: { as?: "text" | "base64"; offset?: number; limit?: number } = {}): Promise<string> {
    const { as = "text", offset = 0, limit = 147_456 } = options;
    return await command("", "files", { files: { action: "read", ids: ids(ref), as, offset, limit } }) as string;
  },
  /**
   * Saves base64 contents of up to 144 KiB as `name` in a folder the person
   * picks, and returns a handle to the new file, or undefined when they cancel.
   * Needs the `file-read` permission.
   */
  async save(name: string, base64: string): Promise<FileHandle | undefined> {
    const handle = await command("", "files", { files: { action: "save", name, data: base64 } }, 600_000);
    return handle && typeof handle === "object" ? handle as unknown as FileHandle : undefined;
  },
};

/** The clipboard. Writing needs a click or key press in your extension, like `open`. */
export const clipboard = {
  /** Copies text, up to 64 KiB. Needs NotchNotch 0.14. */
  async copy(text: string): Promise<void> {
    await command("", "files", { files: { action: "clipboard", text } });
  },
};
