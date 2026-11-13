import {
  Activity, Button, Column, DropTypes, DropZone, FileGrid, ListItem, Row, Spacer, Symbol, Text, clipboard,
  files as fileActions, getPreferenceValues, open, useStoredState, type DropItem, type FileHandle,
} from "@notchnotch/sdk";
import { useState } from "react";
import { start } from "@notchnotch/runtime";

const { keepCopy, removeAfterDrag } = getPreferenceValues<{ keepCopy?: boolean; removeAfterDrag?: boolean }>();
/** Links and text show as rows, up to this many; the rest wait behind a count. */
const maximumRows = 4;

function Shelf() {
  // Handles survive restarts, so the shelf does too.
  const [items, setItems] = useStoredState<DropItem[]>("items", []);
  const [selected, setSelected] = useState<string[]>([]);
  const files = items.flatMap((item) => item.kind === "file" ? [item.file] : []);
  // The buttons act on the selection, or on every file when nothing is selected.
  const chosen = files.filter((file) => selected.includes(file.id));
  const targets = chosen.length ? chosen : files;
  const count = items.length;
  function keep(dropped: DropItem[]) {
    setItems((before) => [...before, ...dropped].slice(-200));
    const originals = dropped.flatMap((item) => item.kind === "file" ? [item.file] : []);
    if (!keepCopy || !originals.length) return;
    // Swap each file for the Shelf's own copy once it's made.
    void fileActions.keepCopy(originals).then((copies) => {
      const byOriginal = new Map(originals.map((file, index) => [file.id, copies[index]]));
      setItems((before) => before.map((item) =>
        item.kind === "file" && byOriginal.get(item.file.id) ? { kind: "file", file: byOriginal.get(item.file.id)! } : item));
    }).catch(() => {});
  }
  function removeAt(index: number) { setItems((before) => before.filter((_, at) => at !== index)); }
  const others = items.flatMap((item, index) => item.kind === "file" ? [] : [{ item, index }]);
  function remove(gone: FileHandle[]) {
    const ids = gone.map((file) => file.id);
    void fileActions.release(ids).catch(() => {});
    setItems((before) => before.filter((item) => item.kind !== "file" || !ids.includes(item.file.id)));
    setSelected((before) => before.filter((id) => !ids.includes(id)));
  }
  function draggedOut(gone: FileHandle[]) { if (removeAfterDrag) remove(gone); }
  function copy(text: string) { void clipboard.copy(text).catch(() => {}); }
  return <>
    <DropZone id="keep" title="Shelf" icon="tray.and.arrow.down.fill" accepts={[DropTypes.anything]} multiple
      opens="shelf" onDrop={keep} />
    {/* A glance: the app opens it after a drop, so it never needs the wings. */}
    <Activity id="shelf" title="Shelf" phase="paused">
      <Activity.Compact leading={<Symbol name="tray.full.fill" />} trailing={<Text size="caption">{`${count}`}</Text>} />
      {/* The stack drags every file out of Home at once; a click opens the Shelf. */}
      <Activity.Tile size={files.length ? "wide" : "small"}>
        {files.length ? <FileGrid files={files} onDragOut={draggedOut} /> : null}
        <Column spacing="none">
          <Text size="caption" tone="secondary">SHELF</Text>
          <Text size={count ? "title" : "body"} tone={count ? "primary" : "secondary"}>
            {count ? `${count} ${count === 1 ? "item" : "items"}` : "Empty"}
          </Text>
        </Column>
      </Activity.Tile>
      <Activity.Expanded>
        {count ? null : <Text tone="secondary">Drag files, links or text to the notch and let go on Shelf.</Text>}
        {files.length ? <FileGrid files={files} selected={selected} onSelect={setSelected}
          onRemove={remove} onDragOut={draggedOut} /> : null}
        {others.length ? <Column spacing="tight">
          {others.slice(-maximumRows).reverse().map(({ item, index }) => item.kind === "url"
            ? <ListItem key={`u${index}`} icon="link" title={item.title ?? hostOf(item.url)} subtitle={item.url} drag={item.url}>
                <Button icon="arrow.up.right" label="Open" onPress={() => void open(item.url).catch(() => {})} />
                <Button icon="doc.on.doc" label="Copy" onPress={() => copy(item.url)} />
                <Button icon="xmark" label="Remove" onPress={() => removeAt(index)} />
              </ListItem>
            : item.kind === "text"
              ? <ListItem key={`t${index}`} icon="text.quote" title={item.text.replace(/\s+/g, " ").slice(0, 120)} drag={item.text}>
                  <Button icon="doc.on.doc" label="Copy" onPress={() => copy(item.text)} />
                  <Button icon="xmark" label="Remove" onPress={() => removeAt(index)} />
                </ListItem>
              : null)}
          {others.length > maximumRows ? <Text size="caption" tone="secondary">{`${others.length - maximumRows} more links and texts`}</Text> : null}
        </Column> : null}
        {count ? <Row>
          <Text size="caption" tone="secondary">{chosen.length ? `${chosen.length} selected` : summary(files.length, count - files.length)}</Text>
          <Spacer />
          {chosen.length
            ? <Button icon="minus.circle" label={`Remove ${chosen.length}`} onPress={() => remove(chosen)} />
            : <Button icon="trash" label="Clear" onPress={() => {
                void fileActions.release(files).catch(() => {});
                setItems([]);
                setSelected([]);
              }} />}
          {targets.length ? <Button icon="doc.on.doc" label="Copy" onPress={() => void fileActions.copyToClipboard(targets).catch(() => {})} /> : null}
          {targets.length ? <Button icon="arrow.up.forward.app" label="Open With" onPress={() => void fileActions.openWith(targets).catch(() => {})} /> : null}
          {targets.length ? <Button icon="eye" label="Quick Look" onPress={() => void fileActions.preview(targets).catch(() => {})} /> : null}
          {targets.length ? <Button title="Share" icon="square.and.arrow.up" tone="accent" onPress={() => void fileActions.share(targets).catch(() => {})} /> : null}
        </Row> : null}
      </Activity.Expanded>
    </Activity>
  </>;
}
/** "3 files · 2 more", "5 files", "2 more" for the bar when nothing is selected. */
function summary(fileCount: number, otherCount: number) {
  const parts = [fileCount ? `${fileCount} ${fileCount === 1 ? "file" : "files"}` : "", otherCount ? `${otherCount} ${otherCount === 1 ? "link or text" : "links and texts"}` : ""];
  return parts.filter(Boolean).join(" · ");
}
function hostOf(url: string) {
  // The extension runtime has no URL class.
  return /^[a-z][a-z0-9+.-]*:\/\/(?:www\.)?([^/?#:]+)/i.exec(url)?.[1] ?? url;
}

start(<Shelf />);
