import { useState } from "react";
import { Activity, DropTypes, DropZone, FileItem, Text, type DropItem } from "@notchnotch/sdk";
import { start } from "@notchnotch/runtime";

function Shelf() {
  const [items, setItems] = useState<DropItem[]>([]);
  const files = items.flatMap((item) => item.kind === "file" ? [item.file] : []);
  const text = items.find((item) => item.kind === "text");
  return <>
    <DropZone id="keep" title="Shelf" icon="tray" accepts={[DropTypes.anything]} multiple opens="shelf"
      onDrop={(dropped) => setItems((before) => [...before, ...dropped])} />
    <Activity id="shelf" title="Shelf" phase="paused" initialView="expanded">
      <Activity.Expanded>
        <Text>{`${items.length} items`}</Text>
        {text?.kind === "text" ? <Text>{`${text.text.length} characters`}</Text> : null}
        {files.map((file) => <FileItem key={file.id} file={file} />)}
      </Activity.Expanded>
    </Activity>
  </>;
}
start(<Shelf />);
