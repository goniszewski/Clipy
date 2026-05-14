# Snippets Window Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add visible close, reorder, cross-folder snippet moves, and clear edit states to the modern snippets editor.

**Architecture:** Keep persistence in `SnippetsEditorViewModel` and UI affordances in `ModernSnippetsEditor.swift` row views. Realm remains the source of truth: folder and snippet `index` values are rewritten after each move, and snippet Realm list membership is updated when moving across folders.

**Tech Stack:** Swift 5.9, SwiftUI, RealmSwift, Quick/Nimble, Xcode macOS app target.

---

## File Structure

- Modify `Clipy/Sources/Snippets/ModernSnippetsEditor.swift`
  - Add view-model move and title sanitizing methods.
  - Add close button overlay.
  - Add drag payload/drop delegate helpers.
  - Add row drag handles and explicit edit styling.
- Modify `ClipyTests/FolderSpec.swift`
  - Add `AsyncSpec` coverage for `SnippetsEditorViewModel` ordering operations without touching the Xcode project file.
- Create `docs/superpowers/plans/2026-05-13-snippets-window-improvements.md`
  - Track this implementation plan.

## Task 1: Add Failing View Model Reorder Tests

**Files:**
- Modify: `ClipyTests/FolderSpec.swift`

- [x] **Step 1: Write failing tests**

Append this class to `ClipyTests/FolderSpec.swift`:

```swift
class SnippetsEditorViewModelSpec: AsyncSpec {
    override class func spec() {
        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describe("Modern snippets editor reordering") {
            it("moves folders and rewrites persisted folder indexes") {
                await MainActor.run {
                    let realm = try! Realm()
                    let first = CPYFolder()
                    first.title = "First"
                    first.index = 0
                    let second = CPYFolder()
                    second.title = "Second"
                    second.index = 1
                    let third = CPYFolder()
                    third.title = "Third"
                    third.index = 2
                    realm.transaction { realm.add([first, second, third]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()
                    viewModel.moveFolder(id: third.identifier, toIndex: 0)

                    let ordered = Array(realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true))
                    expect(ordered.map(\.identifier)) == [third.identifier, first.identifier, second.identifier]
                    expect(ordered.map(\.index)) == [0, 1, 2]
                    expect(viewModel.folders.map(\.id)) == [third.identifier, first.identifier, second.identifier]
                    expect(viewModel.selectedFolderID) == third.identifier
                    expect(viewModel.selectedSnippetID).to(beNil())
                }
            }

            it("moves snippets within the same folder and rewrites persisted snippet indexes") {
                await MainActor.run {
                    let realm = try! Realm()
                    let folder = CPYFolder()
                    folder.title = "Folder"
                    folder.index = 0
                    let first = CPYSnippet()
                    first.title = "First"
                    first.index = 0
                    let second = CPYSnippet()
                    second.title = "Second"
                    second.index = 1
                    let third = CPYSnippet()
                    third.title = "Third"
                    third.index = 2
                    folder.snippets.append(objectsIn: [first, second, third])
                    realm.transaction { realm.add(folder) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()
                    viewModel.moveSnippet(id: third.identifier, toFolderID: folder.identifier, toIndex: 0)

                    let ordered = Array(folder.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
                    expect(ordered.map(\.identifier)) == [third.identifier, first.identifier, second.identifier]
                    expect(ordered.map(\.index)) == [0, 1, 2]
                    expect(viewModel.folders.first?.snippets.map(\.id)) == [third.identifier, first.identifier, second.identifier]
                    expect(viewModel.selectedFolderID) == folder.identifier
                    expect(viewModel.selectedSnippetID) == third.identifier
                }
            }

            it("moves snippets between folders and rewrites both folders' snippet indexes") {
                await MainActor.run {
                    let realm = try! Realm()
                    let source = CPYFolder()
                    source.title = "Source"
                    source.index = 0
                    let destination = CPYFolder()
                    destination.title = "Destination"
                    destination.index = 1
                    let moving = CPYSnippet()
                    moving.title = "Moving"
                    moving.index = 0
                    let remaining = CPYSnippet()
                    remaining.title = "Remaining"
                    remaining.index = 1
                    let existing = CPYSnippet()
                    existing.title = "Existing"
                    existing.index = 0
                    source.snippets.append(objectsIn: [moving, remaining])
                    destination.snippets.append(existing)
                    realm.transaction { realm.add([source, destination]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()
                    viewModel.moveSnippet(id: moving.identifier, toFolderID: destination.identifier, toIndex: 1)

                    let sourceOrdered = Array(source.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
                    let destinationOrdered = Array(destination.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
                    expect(sourceOrdered.map(\.identifier)) == [remaining.identifier]
                    expect(sourceOrdered.map(\.index)) == [0]
                    expect(destinationOrdered.map(\.identifier)) == [existing.identifier, moving.identifier]
                    expect(destinationOrdered.map(\.index)) == [0, 1]
                    expect(viewModel.folders[0].snippets.map(\.id)) == [remaining.identifier]
                    expect(viewModel.folders[1].snippets.map(\.id)) == [existing.identifier, moving.identifier]
                    expect(viewModel.selectedFolderID) == destination.identifier
                    expect(viewModel.selectedSnippetID) == moving.identifier
                }
            }
        }

        afterEach {
            await MainActor.run {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }
        }
    }
}
```

- [x] **Step 2: Run tests to verify RED**

Run:

```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug -destination 'platform=macOS' -only-testing:ClipyTests/SnippetsEditorViewModelSpec test
```

Expected: build fails because `SnippetsEditorViewModel` has no `moveFolder(id:toIndex:)` or `moveSnippet(id:toFolderID:toIndex:)` methods.

## Task 2: Implement View Model Move Operations

**Files:**
- Modify: `Clipy/Sources/Snippets/ModernSnippetsEditor.swift`

- [x] **Step 1: Add title sanitizers and folder selection**

Add private title helpers and a public folder selection method inside `SnippetsEditorViewModel`:

```swift
private func sanitizedFolderTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "untitled folder" : trimmed
}

private func sanitizedSnippetTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "untitled snippet" : trimmed
}

func selectFolder(_ folderID: String) {
    if hasUnsavedChanges { saveCurrentSnippet() }
    selectedFolderID = folderID
    selectedSnippetID = nil
    editingTitle = ""
    editingContent = ""
    hasUnsavedChanges = false
}
```

- [x] **Step 2: Update existing save/rename paths to use sanitizers**

Change `saveCurrentSnippet()` so it assigns:

```swift
let title = sanitizedSnippetTitle(editingTitle)
realm.transaction {
    snippet.title = title
    snippet.content = editingContent
}
editingTitle = title
```

Change `renameFolder(_:to:)` so it assigns:

```swift
let title = sanitizedFolderTitle(newTitle)
realm.transaction { folder.title = title }
```

- [x] **Step 3: Add move methods**

Add these methods inside `SnippetsEditorViewModel`:

```swift
func moveFolder(id folderID: String, toIndex destinationIndex: Int) {
    if hasUnsavedChanges { saveCurrentSnippet() }
    guard let realm = Realm.safeInstance() else { return }
    var orderedFolders = Array(realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true))
    guard let sourceIndex = orderedFolders.firstIndex(where: { $0.identifier == folderID }) else { return }

    let folder = orderedFolders.remove(at: sourceIndex)
    let boundedIndex = min(max(destinationIndex, 0), orderedFolders.count)
    orderedFolders.insert(folder, at: boundedIndex)

    realm.transaction {
        for (index, folder) in orderedFolders.enumerated() {
            folder.index = index
        }
    }

    selectedFolderID = folderID
    selectedSnippetID = nil
    editingTitle = ""
    editingContent = ""
    hasUnsavedChanges = false
    load()
}

func moveSnippet(id snippetID: String, toFolderID destinationFolderID: String, toIndex destinationIndex: Int) {
    if hasUnsavedChanges { saveCurrentSnippet() }
    guard let realm = Realm.safeInstance() else { return }
    let folders = Array(realm.objects(CPYFolder.self))
    guard let sourceFolder = folders.first(where: { folder in
        folder.snippets.contains(where: { $0.identifier == snippetID })
    }),
    let destinationFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: destinationFolderID) else { return }

    var sourceSnippets = Array(sourceFolder.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
    guard let sourceIndex = sourceSnippets.firstIndex(where: { $0.identifier == snippetID }) else { return }
    let snippet = sourceSnippets.remove(at: sourceIndex)

    if sourceFolder.identifier == destinationFolder.identifier {
        let boundedIndex = min(max(destinationIndex, 0), sourceSnippets.count)
        sourceSnippets.insert(snippet, at: boundedIndex)
        realm.transaction {
            sourceFolder.snippets.removeAll()
            sourceFolder.snippets.append(objectsIn: sourceSnippets)
            for (index, snippet) in sourceSnippets.enumerated() {
                snippet.index = index
            }
        }
    } else {
        var destinationSnippets = Array(destinationFolder.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
        let boundedIndex = min(max(destinationIndex, 0), destinationSnippets.count)
        destinationSnippets.insert(snippet, at: boundedIndex)
        realm.transaction {
            sourceFolder.snippets.removeAll()
            sourceFolder.snippets.append(objectsIn: sourceSnippets)
            destinationFolder.snippets.removeAll()
            destinationFolder.snippets.append(objectsIn: destinationSnippets)
            for (index, snippet) in sourceSnippets.enumerated() {
                snippet.index = index
            }
            for (index, snippet) in destinationSnippets.enumerated() {
                snippet.index = index
            }
        }
    }

    selectedFolderID = destinationFolderID
    selectedSnippetID = snippetID
    editingTitle = snippet.title
    editingContent = snippet.content
    hasUnsavedChanges = false
    expandedFolderIDs.insert(destinationFolderID)
    load()
}
```

- [x] **Step 4: Run tests to verify GREEN**

Run the same `xcodebuild ... -only-testing:ClipyTests/SnippetsEditorViewModelSpec test` command.

Expected: the new view model reorder tests pass.

## Task 3: Add SwiftUI Reorder Affordances and Drop Handling

**Files:**
- Modify: `Clipy/Sources/Snippets/ModernSnippetsEditor.swift`

- [x] **Step 1: Add drag payload and drop target helpers**

Add file-private helpers below the view model:

```swift
private enum SnippetDragPayload {
    case folder(String)
    case snippet(String)

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "folder": self = .folder(parts[1])
        case "snippet": self = .snippet(parts[1])
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .folder(let id): return "folder:\(id)"
        case .snippet(let id): return "snippet:\(id)"
        }
    }
}

private enum SnippetDropTarget {
    case folder(folderID: String, folderIndex: Int, snippetCount: Int)
    case snippet(folderID: String, snippetIndex: Int)
    case snippetEnd(folderID: String, snippetCount: Int)
}

private extension UTType {
    static let clipySnippetReorderPayload = UTType(exportedAs: "com.clipy.snippet-editor.reorder-payload")
}

private struct SnippetDropDelegate: DropDelegate {
    let isEnabled: Bool
    let target: SnippetDropTarget
    let onDropPayload: (SnippetDragPayload, SnippetDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [.clipySnippetReorderPayload])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled,
              let provider = info.itemProviders(for: [.clipySnippetReorderPayload]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.clipySnippetReorderPayload.identifier) { data, _ in
            guard let data,
                  let rawValue = String(data: data, encoding: .utf8),
                  let payload = SnippetDragPayload(rawValue: rawValue) else { return }
            DispatchQueue.main.async {
                onDropPayload(payload, target)
            }
        }
        return true
    }
}
```

- [x] **Step 2: Add payload provider and drop router methods**

Add view helpers to `ModernSnippetsEditorView`:

```swift
private var reorderEnabled: Bool {
    viewModel.sidebarFilter.isEmpty
}

private func dragProvider(for payload: SnippetDragPayload) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: UTType.clipySnippetReorderPayload.identifier, visibility: .all) { completion in
        completion(payload.rawValue.data(using: .utf8), nil)
        return nil
    }
    return provider
}

private func handleDrop(payload: SnippetDragPayload, target: SnippetDropTarget) {
    guard reorderEnabled else { return }
    switch (payload, target) {
    case (.folder(let folderID), .folder(_, let folderIndex, _)):
        viewModel.moveFolder(id: folderID, toIndex: folderIndex)
    case (.snippet(let snippetID), .folder(let folderID, _, let snippetCount)):
        viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetCount)
    case (.snippet(let snippetID), .snippet(let folderID, let snippetIndex)):
        viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetIndex)
    case (.snippet(let snippetID), .snippetEnd(let folderID, let snippetCount)):
        viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetCount)
    case (.folder, .snippet), (.folder, .snippetEnd):
        return
    }
}
```

- [x] **Step 3: Pass reorder hooks into rows**

Change folder iteration to enumerate folders:

```swift
ForEach(Array(viewModel.filteredFolders.enumerated()), id: \.element.id) { folderIndex, folder in
    SnippetFolderRow(
        folder: folder,
        folderIndex: folderIndex,
        isSelected: viewModel.selectedFolderID == folder.id,
        selectedSnippetID: viewModel.selectedSnippetID,
        reorderEnabled: reorderEnabled,
        dragProvider: dragProvider,
        onDropPayload: handleDrop,
        onSelectFolder: { viewModel.selectFolder(folder.id) },
        ...
    )
}
```

- [x] **Step 4: Update row structs**

Add folder row properties:

```swift
let folderIndex: Int
let reorderEnabled: Bool
let dragProvider: (SnippetDragPayload) -> NSItemProvider
let onDropPayload: (SnippetDragPayload, SnippetDropTarget) -> Void
```

Add snippet row properties:

```swift
let folderID: String
let snippetIndex: Int
let reorderEnabled: Bool
let dragProvider: (SnippetDragPayload) -> NSItemProvider
let onDropPayload: (SnippetDragPayload, SnippetDropTarget) -> Void
```

Use `ForEach(Array(folder.snippets.enumerated()), id: \.element.id)` when building snippet rows so each row receives `snippetIndex`.

- [x] **Step 5: Add drag handles and modifiers**

Add a fixed-width handle image near the start of folder and snippet rows:

```swift
Image(systemName: "line.3.horizontal")
    .font(.system(size: 10, weight: .semibold))
    .foregroundStyle(reorderEnabled ? .quaternary : .clear)
    .frame(width: 12)
```

Add to folder row:

```swift
.onDrag {
    dragProvider(.folder(folder.id))
}
.onDrop(
    of: [.clipySnippetReorderPayload],
    delegate: SnippetDropDelegate(
        isEnabled: reorderEnabled,
        target: .folder(folderID: folder.id, folderIndex: folderIndex, snippetCount: folder.snippets.count),
        onDropPayload: onDropPayload
    )
)
```

Add to snippet row:

```swift
.onDrag {
    dragProvider(.snippet(snippet.id))
}
.onDrop(
    of: [.clipySnippetReorderPayload],
    delegate: SnippetDropDelegate(
        isEnabled: reorderEnabled,
        target: .snippet(folderID: folderID, snippetIndex: snippetIndex),
        onDropPayload: onDropPayload
    )
)
```

Add a small end drop zone below expanded snippets:

```swift
Color.clear
    .frame(height: 6)
    .onDrop(
        of: [.clipySnippetReorderPayload],
        delegate: SnippetDropDelegate(
            isEnabled: reorderEnabled,
            target: .snippetEnd(folderID: folder.id, snippetCount: folder.snippets.count),
            onDropPayload: onDropPayload
        )
    )
```

## Task 4: Add Close Button and Visible Edit Styling

**Files:**
- Modify: `Clipy/Sources/Snippets/ModernSnippetsEditor.swift`

- [x] **Step 1: Add snippet title focus state**

Add to `ModernSnippetsEditorView`:

```swift
@FocusState private var snippetTitleFocused: Bool
```

- [x] **Step 2: Add close button overlay**

Add a top-right overlay near the existing window overlay:

```swift
.overlay(alignment: .topTrailing) {
    Button(action: onClose) {
        Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }
    .buttonStyle(.plain)
    .help("Close")
    .padding(8)
}
```

- [x] **Step 3: Style snippet title editing**

Wrap the editor header title field with focus styling:

```swift
TextField("Snippet title", text: $viewModel.editingTitle)
    .textFieldStyle(.plain)
    .font(.system(size: 15, weight: .medium))
    .focused($snippetTitleFocused)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(snippetTitleFocused ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(SwiftUI.Color.clear))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(snippetTitleFocused ? SwiftUI.Color.accentColor.opacity(0.65) : .white.opacity(0.08), lineWidth: 1)
    )
    .onChange(of: viewModel.editingTitle) { _, _ in
        viewModel.hasUnsavedChanges = true
    }
```

- [x] **Step 4: Style folder inline rename editing**

In `SnippetFolderRow`, add:

```swift
@FocusState private var titleFieldFocused: Bool
```

Replace the editing `TextField` with:

```swift
TextField("", text: $editedTitle, onCommit: commitRename)
    .textFieldStyle(.plain)
    .font(.system(size: 12, weight: .medium))
    .focused($titleFieldFocused)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(.white.opacity(0.09))
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(titleFieldFocused ? SwiftUI.Color.accentColor.opacity(0.75) : .white.opacity(0.12), lineWidth: 1)
    )
    .onAppear {
        DispatchQueue.main.async {
            titleFieldFocused = true
        }
    }
    .onChange(of: titleFieldFocused) { _, focused in
        if !focused && isEditing {
            commitRename()
        }
    }
```

Add helper:

```swift
private func commitRename() {
    onRenameFolder(editedTitle)
    isEditing = false
}
```

## Task 5: Verification

**Files:**
- Verify all modified files.

- [x] **Step 1: Run targeted tests**

Run:

```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug -destination 'platform=macOS' -only-testing:ClipyTests/SnippetsEditorViewModelSpec test
```

Expected: test action succeeds.

- [x] **Step 2: Run full test suite**

Run:

```bash
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug -destination 'platform=macOS' test
```

Expected: test action succeeds.

- [x] **Step 3: Review final diff**

Run:

```bash
git diff -- Clipy/Sources/Snippets/ModernSnippetsEditor.swift ClipyTests/FolderSpec.swift docs/superpowers/plans/2026-05-13-snippets-window-improvements.md
```

Expected: diff is limited to the approved snippets window improvements and implementation plan.
