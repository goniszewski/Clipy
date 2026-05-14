# Snippets Window Improvements Design

Date: 2026-05-13

## Goal

Improve the modern snippets editor so common window and organization actions are visible and direct:

- Close the snippets window without relying on Escape.
- Reorder folders.
- Reorder snippets within a folder and move snippets between folders.
- Make snippet and folder title editing visibly distinct from normal row/title display.

## Current Context

The active snippets editor is implemented in `Clipy/Sources/Snippets/ModernSnippetsEditor.swift`. It loads `CPYFolder` objects sorted by `CPYFolder.index`, and each folder loads `CPYSnippet` objects sorted by `CPYSnippet.index`.

The older AppKit outline editor already contains drag/drop behavior for folders and snippets in `CPYSnippetsEditorWindowController.swift`, and persistence helpers already exist on `CPYFolder`:

- `CPYFolder.rearrangesIndex(_:)`
- `CPYFolder.rearrangesSnippetIndex()`
- `CPYFolder.insertSnippet(_:index:)`
- `CPYFolder.removeSnippet(_:)`

The modern SwiftUI window hides standard macOS window buttons and currently only closes through the Escape key monitor.

## User Experience

### Close Button

Add a compact icon button to the top-right of the SwiftUI window surface. The button uses the existing `onClose` callback so it follows the same close path as Escape.

### Reordering

Use option B from the visual companion: row drag handles plus clear drop behavior.

Folders:

- Show a restrained drag-handle affordance on folder rows.
- Allow top-level folder reordering.
- Persist new order by rewriting folder `index` values.

Snippets:

- Show a restrained drag-handle affordance on snippet rows.
- Allow snippet reordering within the same folder.
- Allow moving a snippet to another folder by dropping onto that folder or into a position among that folder's snippets.
- Persist new order by rewriting snippet `index` values in affected folders.
- Keep selection on the moved item after a successful move.

Filtered sidebar behavior:

- Drag/reorder is disabled while a sidebar filter is active, because filtered positions do not map cleanly to full persisted order.

Vault behavior:

- Snippets inside locked vault folders remain unavailable for drag/drop until the folder is unlocked and expanded.
- Dropping into a locked vault folder is not offered.

### Rename/Edit Visibility

Folder inline rename mode:

- Replace the plain row title with a styled text field.
- Use a visible border, subtle focused background, and insertion cursor.
- Commit on Return or focus loss.
- Keep the existing window-level Escape close behavior unchanged.

Snippet title editing:

- Style the editor header title field so focused edit state is visible.
- Continue to mark the snippet as having unsaved changes when the title changes.

Empty names:

- Prevent blank persisted titles. If a title edit resolves to empty whitespace, persist `untitled folder` for folders and `untitled snippet` for snippets.

## Architecture

Extend `SnippetsEditorViewModel` with focused move operations that mutate Realm and reload the published folder tree:

- `moveFolder(id:toIndex:)`
- `moveSnippet(id:toFolderID:toIndex:)`

The move methods should:

- Save the current snippet first if there are unsaved edits.
- Resolve source and destination from Realm, not only from view snapshots.
- Normalize destination indexes for same-folder moves where removal shifts the target position.
- Update Realm list membership when moving across folders.
- Rewrite contiguous `index` values for all affected folders/snippets.
- Preserve `selectedFolderID`, `selectedSnippetID`, and expansion state where possible.

SwiftUI row views remain responsible for visual drag/drop affordances, while the view model owns persistence and selection updates.

## Components

- `ModernSnippetsEditorView`
  - Adds the close button overlay.
  - Passes move closures into folder/snippet rows.
  - Disables reorder affordances when `sidebarFilter` is non-empty.

- `SnippetFolderRow`
  - Displays folder drag handle.
  - Accepts folder and snippet drops where valid.
  - Applies clear rename styling.

- `SnippetItemRow`
  - Displays snippet drag handle.
  - Exposes snippet drag payload.
  - Applies stable row sizing so drag handles and hover controls do not shift layout.

- `SnippetsEditorViewModel`
  - Adds order mutation methods and any small helper types needed to identify drag payloads.

## Testing

Add focused tests around ordering and persistence behavior:

- Folder move rewrites contiguous folder indexes and `load()` returns the new order.
- Same-folder snippet move rewrites contiguous snippet indexes.
- Cross-folder snippet move removes from the source folder, inserts into the destination folder, and rewrites indexes for both folders.

Run a compile check for the SwiftUI changes after implementation.

## Out of Scope

- Reworking the full snippets editor layout.
- Adding a separate organize mode.
- Import/export format changes.
- New keyboard shortcuts for move up/down.
- Dragging locked vault snippets.

## Risks

- SwiftUI drag/drop APIs vary by macOS deployment target, so implementation should stay compatible with the project's current target.
- Same-folder moves can create off-by-one errors when the destination index is after the source index.
- Filtered lists can produce ambiguous drop positions, so reorder is intentionally disabled while filtering.
