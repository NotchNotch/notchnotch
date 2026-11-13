import Testing
import NotchProtocol
@testable import NotchCore

private func file(_ id: String, _ type: String, folder: Bool = false) -> DroppedFile {
    .init(id: id, name: id, type: type, size: 1, kind: folder ? .folder : .file)
}

@Test func theFileGridWidensBeforeItGrowsPastThreeRows() {
    #expect(FileGridLayout.columns(for: 1) == 4)
    #expect(FileGridLayout.columns(for: 5) == 5)
    #expect(FileGridLayout.columns(for: 6) == 6, "six files in one row")
    #expect(FileGridLayout.columns(for: 13) == 6, "then rows grow; it never narrows")
    #expect(!FileGridLayout.stacks(18) && FileGridLayout.stacks(19))
    #expect(FileGridLayout.visible(18) == (18, 0))
    #expect(FileGridLayout.visible(41) == (17, 24), "an open stack too big for the grid ends with +N")
}

@Test func filesGatherIntoStacksByKindInAFixedOrder() {
    let files = [file("a", "public.jpeg"), file("b", "com.adobe.pdf"), file("c", "public.heic"), file("d", "public.folder", folder: true),
                 file("e", "com.apple.quicktime-movie"), file("f", "public.zip-archive"), file("g", "org.openxmlformats.wordprocessingml.document"),
                 file("h", "dyn.unknown"), file("i", "public.plain-text")]
    let stacks = FileStack.group(files)
    #expect(stacks.map(\.kind) == [.folders, .images, .movies, .pdfs, .documents, .archives, .other])
    #expect(stacks.first { $0.kind == .images }?.files.map(\.id) == ["a", "c"])
    #expect(stacks.first { $0.kind == .documents }?.files.map(\.id) == ["g", "i"])
}
