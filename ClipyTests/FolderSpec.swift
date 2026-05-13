import Quick
import Nimble
import RealmSwift
@testable import Clipy

// swiftlint:disable function_body_length
class FolderSpec: QuickSpec {
    override class func spec() {

        beforeEach {
            Realm.Configuration.defaultConfiguration.inMemoryIdentifier = NSUUID().uuidString
        }

        describe("Create new") {

            it("deep copy object") {
                // Save Value
                let savedFolder = CPYFolder()
                savedFolder.index = 100
                savedFolder.title = "saved realm folder"

                let savedSnippet = CPYSnippet()
                savedSnippet.index = 10
                savedSnippet.title = "saved realm snippet"
                savedSnippet.content = "content"
                savedFolder.snippets.append(savedSnippet)

                let realm = try! Realm()
                realm.transaction { realm.add(savedFolder) }

                // Saved in Realm
                expect(savedFolder.realm).toNot(beNil())
                expect(savedSnippet.realm).toNot(beNil())

                // Deep copy
                let folder = savedFolder.deepCopy()
                expect(folder.realm).to(beNil())
                expect(folder.index) == savedFolder.index
                expect(folder.enable) == savedFolder.enable
                expect(folder.title) == savedFolder.title
                expect(folder.identifier) == savedFolder.identifier
                expect(folder.snippets.count) == 1

                let snippet = folder.snippets.first!
                expect(snippet.realm).to(beNil())
                expect(snippet.index) == savedSnippet.index
                expect(snippet.enable) == savedSnippet.enable
                expect(snippet.title) == savedSnippet.title
                expect(snippet.content) == savedSnippet.content
                expect(snippet.identifier) == savedSnippet.identifier
            }

            it("Create folder") {
                let folder = CPYFolder.create()
                expect(folder.title) == "untitled folder"
                expect(folder.index) == 0

                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                let folder2 = CPYFolder.create()
                expect(folder2.index) == 1
            }

            it("Create snippet") {
                let folder = CPYFolder()
                let snippet = folder.createSnippet()

                expect(snippet.title) == "untitled snippet"
                expect(snippet.index) == 0

                folder.snippets.append(snippet)

                let snippet2 = folder.createSnippet()
                expect(snippet2.index) == 1
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Sync database") {

            it("Merge snippet") {
                let folder = CPYFolder()
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }
                let copyFolder = folder.deepCopy()

                let snippet = CPYSnippet()
                let snippet2 = CPYSnippet()
                copyFolder.mergeSnippet(snippet)
                copyFolder.mergeSnippet(snippet2)

                expect(snippet.realm).to(beNil())
                expect(snippet2.realm).to(beNil())
                expect(folder.snippets.count) == 2

                let savedSnippet = folder.snippets.first!
                let savedSnippet2 = folder.snippets[1]
                expect(savedSnippet.identifier) == snippet.identifier
                expect(savedSnippet2.identifier) == snippet2.identifier
            }

            it("Insert snippet") {
                let folder = CPYFolder()
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }
                let copyFolder = folder.deepCopy()

                let snippet = CPYSnippet()
                // Don't insert non saved snippt
                copyFolder.insertSnippet(snippet, index: 0)
                expect(folder.snippets.count) == 0

                realm.transaction { realm.add(snippet) }

                // Can insert saved snippet
                copyFolder.insertSnippet(snippet, index: 0)
                expect(folder.snippets.count) == 1
            }

            it("Remove snippet") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                folder.snippets.append(snippet)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                expect(folder.snippets.count) == 1

                let copyFolder = folder.deepCopy()
                copyFolder.removeSnippet(snippet)

                expect(folder.snippets.count) == 0
            }

            it("Merge folder") {
                let realm = try! Realm()
                expect(realm.objects(CPYFolder.self).count) == 0

                let folder = CPYFolder()
                folder.index = 100
                folder.title = "title"
                folder.enable = false
                folder.merge()
                expect(folder.realm).to(beNil())
                expect(realm.objects(CPYFolder.self).count) == 1

                let savedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier)
                expect(savedFolder).toNot(beNil())
                expect(savedFolder?.index) == folder.index
                expect(savedFolder?.title) == folder.title
                expect(savedFolder?.enable) == folder.enable

                folder.index = 1
                folder.title = "change title"
                folder.enable = true
                folder.merge()
                expect(realm.objects(CPYFolder.self).count) == 1

                expect(savedFolder?.index) == folder.index
                expect(savedFolder?.title) == folder.title
                expect(savedFolder?.enable) == folder.enable
            }

            it("Remove folder") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                folder.snippets.append(snippet)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                expect(realm.objects(CPYFolder.self).count) == 1
                expect(realm.objects(CPYSnippet.self).count) == 1

                let copyFolder = folder.deepCopy()
                expect(copyFolder.realm).to(beNil())
                copyFolder.remove()

                expect(realm.objects(CPYFolder.self).count) == 0
                expect(realm.objects(CPYSnippet.self).count) == 0
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

        describe("Rearrange Index") {

            it("Rearrange folder index") {
                let folder = CPYFolder()
                folder.index = 100
                let folder2 = CPYFolder()
                folder2.index = 10

                let folders = [folder, folder2]
                let realm = try! Realm()
                realm.transaction { realm.add(folders) }

                let copyFolder = folder.deepCopy()
                let copyFolder2 = folder2.deepCopy()

                CPYFolder.rearrangesIndex([copyFolder, copyFolder2])

                expect(copyFolder.index) == 0
                expect(copyFolder2.index) == 1
                expect(folder.index) == 0
                expect(folder2.index) == 1
            }

            it("Rearrange snippet index") {
                let folder = CPYFolder()
                let snippet = CPYSnippet()
                snippet.index = 10
                let snippet2 = CPYSnippet()
                snippet2.index = 100
                folder.snippets.append(snippet)
                folder.snippets.append(snippet2)
                let realm = try! Realm()
                realm.transaction { realm.add(folder) }

                let copyFolder = folder.deepCopy()
                copyFolder.rearrangesSnippetIndex()

                let copySnippet = copyFolder.snippets.first!
                let copySnippet2 = copyFolder.snippets[1]
                expect(copySnippet.index) == 0
                expect(copySnippet2.index) == 1
                expect(snippet.index) == 0
                expect(snippet2.index) == 1
            }

            afterEach {
                let realm = try! Realm()
                realm.transaction { realm.deleteAll() }
            }

        }

    }
}

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

            it("moves snippets downward within the same folder") {
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
                    viewModel.moveSnippet(id: first.identifier, toFolderID: folder.identifier, toIndex: 1)

                    let ordered = Array(folder.snippets.sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true))
                    expect(ordered.map(\.identifier)) == [second.identifier, first.identifier, third.identifier]
                    expect(ordered.map(\.index)) == [0, 1, 2]
                    expect(viewModel.folders.first?.snippets.map(\.id)) == [second.identifier, first.identifier, third.identifier]
                    expect(viewModel.selectedFolderID) == folder.identifier
                    expect(viewModel.selectedSnippetID) == first.identifier
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

        describe("Modern snippets editor selection state") {
            it("keeps selected folder in sync when selecting a snippet from another folder") {
                await MainActor.run {
                    let realm = try! Realm()
                    let firstFolder = CPYFolder()
                    firstFolder.title = "First folder"
                    firstFolder.index = 0
                    let secondFolder = CPYFolder()
                    secondFolder.title = "Second folder"
                    secondFolder.index = 1
                    let secondSnippet = CPYSnippet()
                    secondSnippet.title = "Second snippet"
                    secondSnippet.content = "Snippet body"
                    secondSnippet.index = 0
                    secondFolder.snippets.append(secondSnippet)
                    realm.transaction { realm.add([firstFolder, secondFolder]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()
                    viewModel.selectedFolderID = firstFolder.identifier

                    let snippetItem = viewModel.folders[1].snippets[0]
                    viewModel.selectSnippet(snippetItem)

                    expect(viewModel.selectedFolderID) == secondFolder.identifier
                    expect(viewModel.selectedSnippetID) == secondSnippet.identifier
                    expect(viewModel.editingTitle) == "Second snippet"
                    expect(viewModel.editingContent) == "Snippet body"
                }
            }

            it("clears stale snippet selection when the selected snippet's folder is removed") {
                await MainActor.run {
                    let realm = try! Realm()
                    let firstFolder = CPYFolder()
                    firstFolder.title = "First folder"
                    firstFolder.index = 0
                    let secondFolder = CPYFolder()
                    secondFolder.title = "Second folder"
                    secondFolder.index = 1
                    let secondSnippet = CPYSnippet()
                    secondSnippet.title = "Second snippet"
                    secondSnippet.content = "Snippet body"
                    secondSnippet.index = 0
                    secondFolder.snippets.append(secondSnippet)
                    realm.transaction { realm.add([firstFolder, secondFolder]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()
                    viewModel.selectedFolderID = firstFolder.identifier
                    viewModel.selectedSnippetID = secondSnippet.identifier
                    viewModel.editingTitle = "Second snippet"
                    viewModel.editingContent = "Snippet body"

                    viewModel.removeFolder(secondFolder.identifier)

                    expect(viewModel.selectedFolderID) == firstFolder.identifier
                    expect(viewModel.selectedSnippetID).to(beNil())
                    expect(viewModel.editingTitle).to(beEmpty())
                    expect(viewModel.editingContent).to(beEmpty())
                }
            }
        }

        describe("Modern snippets editor drop indicators") {
            it("shows a snippet insertion line after the hovered row when moving downward") {
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
                    folder.snippets.append(objectsIn: [first, second])
                    realm.transaction { realm.add(folder) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()

                    let indicator = viewModel.dropIndicator(
                        for: .snippet(first.identifier),
                        target: .snippet(folderID: folder.identifier, snippetIndex: 1)
                    )

                    expect(indicator) == .snippet(snippetID: second.identifier, edge: .after)
                }
            }

            it("shows a snippet insertion line before the hovered row when moving upward") {
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
                    folder.snippets.append(objectsIn: [first, second])
                    realm.transaction { realm.add(folder) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()

                    let indicator = viewModel.dropIndicator(
                        for: .snippet(second.identifier),
                        target: .snippet(folderID: folder.identifier, snippetIndex: 0)
                    )

                    expect(indicator) == .snippet(snippetID: first.identifier, edge: .before)
                }
            }

            it("shows a snippet insertion line at the destination folder end") {
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
                    let existing = CPYSnippet()
                    existing.title = "Existing"
                    existing.index = 0
                    source.snippets.append(moving)
                    destination.snippets.append(existing)
                    realm.transaction { realm.add([source, destination]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()

                    let indicator = viewModel.dropIndicator(
                        for: .snippet(moving.identifier),
                        target: .folder(
                            folderID: destination.identifier,
                            folderIndex: 1,
                            snippetCount: 1,
                            acceptsSnippets: true
                        )
                    )

                    expect(indicator) == .snippetEnd(folderID: destination.identifier)
                }
            }

            it("shows a folder insertion line after the hovered row when moving downward") {
                await MainActor.run {
                    let realm = try! Realm()
                    let first = CPYFolder()
                    first.title = "First"
                    first.index = 0
                    let second = CPYFolder()
                    second.title = "Second"
                    second.index = 1
                    realm.transaction { realm.add([first, second]) }

                    let viewModel = SnippetsEditorViewModel()
                    viewModel.load()

                    let indicator = viewModel.dropIndicator(
                        for: .folder(first.identifier),
                        target: .folder(
                            folderID: second.identifier,
                            folderIndex: 1,
                            snippetCount: 0,
                            acceptsSnippets: true
                        )
                    )

                    expect(indicator) == .folder(folderID: second.identifier, edge: .after)
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
