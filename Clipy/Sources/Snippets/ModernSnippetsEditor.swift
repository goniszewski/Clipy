// swiftlint:disable file_length
//
//  ModernSnippetsEditor.swift
//
//  Clipy
//
//  Modern SwiftUI snippets editor — liquid glass design matching the search panel.
//

import SwiftUI
import RealmSwift
import UniformTypeIdentifiers
import LocalAuthentication
import TipKit

// MARK: - Snippets ViewModel
@MainActor
class SnippetsEditorViewModel: ObservableObject {
    typealias ScriptTestRunner = @MainActor (SnippetExecutionRequest, @escaping @MainActor (ScriptExecutionResult) -> Void) -> Void

    @Published var folders = [FolderItem]()
    @Published var selectedFolderID: String?
    @Published var selectedSnippetID: String?
    @Published var editingTitle = ""
    @Published var editingContent = ""
    @Published var editingSnippetType = CPYSnippet.SnippetType.plainText
    @Published var editingScriptShell = CPYSnippet.defaultScriptShell
    @Published var editingScriptTimeout = CPYSnippet.defaultScriptTimeout
    @Published var editingIsEphemeral = true
    @Published var isRunningScriptTest = false
    @Published var scriptTestResult: ScriptExecutionResult?
    @Published var sidebarFilter = ""
    @Published var hasUnsavedChanges = false
    @Published var expandedFolderIDs = Set<String>()
    @Published var needsRefocus = false
    @Published var showingTemplateGallery = false

    struct FolderItem: Identifiable, Hashable {
        let id: String
        var title: String
        var enabled: Bool
        var isVault: Bool
        var snippets: [SnippetItem]
    }

    struct SnippetItem: Identifiable, Hashable {
        let id: String
        var title: String
        var content: String
        var enabled: Bool
        var type: CPYSnippet.SnippetType
        var scriptShell: String
        var scriptTimeout: Int
        var isEphemeral: Bool

        var isScript: Bool {
            type == .script
        }
    }

    private let scriptTestRunner: ScriptTestRunner
    private var activeScriptTestRunID: UUID?
    static let defaultTemplateFolderTitle = "Script Snippets"

    init(scriptTestRunner: @escaping ScriptTestRunner = { request, completion in
        SnippetExecutionService.shared.testRun(request) { result in
            Task { @MainActor in
                completion(result)
            }
        }
    }) {
        self.scriptTestRunner = scriptTestRunner
    }

    private func sanitizedFolderTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "untitled folder" : trimmed
    }

    private func sanitizedSnippetTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "untitled snippet" : trimmed
    }

    private func loadedSnippet(id snippetID: String) -> (folder: FolderItem, snippet: SnippetItem)? {
        for folder in folders {
            if let snippet = folder.snippets.first(where: { $0.id == snippetID }) {
                return (folder, snippet)
            }
        }
        return nil
    }

    private func clearSnippetEditor() {
        selectedSnippetID = nil
        editingTitle = ""
        editingContent = ""
        resetScriptEditingState()
        hasUnsavedChanges = false
    }

    private func resetScriptEditingState() {
        editingSnippetType = .plainText
        editingScriptShell = CPYSnippet.defaultScriptShell
        editingScriptTimeout = CPYSnippet.defaultScriptTimeout
        editingIsEphemeral = true
        clearScriptTestResult()
    }

    private func loadEditingState(from snippet: SnippetItem) {
        selectedSnippetID = snippet.id
        editingTitle = snippet.title
        editingContent = snippet.content
        editingSnippetType = snippet.type
        editingScriptShell = snippet.scriptShell
        editingScriptTimeout = snippet.scriptTimeout
        editingIsEphemeral = snippet.isEphemeral
        clearScriptTestResult()
        hasUnsavedChanges = false
    }

    func load() {
        guard let realm = Realm.safeInstance() else { return }
        let results = realm.objects(CPYFolder.self)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)

        folders = results.map { folder in
            let snippets = folder.snippets
                .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                .map { snippet in
                    SnippetItem(
                        id: snippet.identifier,
                        title: snippet.title,
                        content: snippet.content,
                        enabled: snippet.enable,
                        type: snippet.type,
                        scriptShell: snippet.scriptShell,
                        scriptTimeout: snippet.scriptTimeout,
                        isEphemeral: snippet.isEphemeral
                    )
                }
            return FolderItem(id: folder.identifier, title: folder.title, enabled: folder.enable, isVault: folder.isVault, snippets: Array(snippets))
        }

        // Initialize expanded state for new folders (non-vault start expanded)
        for folder in folders where !expandedFolderIDs.contains(folder.id) && !folder.isVault {
            expandedFolderIDs.insert(folder.id)
        }

        if let folderID = selectedFolderID, !folders.contains(where: { $0.id == folderID }) {
            selectedFolderID = nil
        }

        if selectedFolderID == nil {
            selectedFolderID = folders.first?.id
        }

        if let snippetID = selectedSnippetID {
            guard let loaded = loadedSnippet(id: snippetID) else {
                clearSnippetEditor()
                return
            }
            selectedFolderID = loaded.folder.id
            loadEditingState(from: loaded.snippet)
        }
    }

    func selectSnippet(_ snippet: SnippetItem) {
        if hasUnsavedChanges { saveCurrentSnippet() }
        if let loaded = loadedSnippet(id: snippet.id) {
            selectedFolderID = loaded.folder.id
            loadEditingState(from: loaded.snippet)
            return
        }
        loadEditingState(from: snippet)
    }

    func selectFolder(_ folderID: String) {
        if hasUnsavedChanges { saveCurrentSnippet() }
        selectedFolderID = folderID
        clearSnippetEditor()
    }

    func saveCurrentSnippet() {
        guard let snippetID = selectedSnippetID else { return }
        guard let realm = Realm.safeInstance() else { return }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: snippetID) else { return }
        let title = sanitizedSnippetTitle(editingTitle)
        let scriptConfig = ScriptSnippetConfig(
            shell: editingScriptShell,
            timeoutSeconds: editingScriptTimeout,
            isEphemeral: editingIsEphemeral
        )
        realm.transaction {
            snippet.title = title
            snippet.content = editingContent
            snippet.type = editingSnippetType
            snippet.scriptShell = scriptConfig.shell
            snippet.scriptTimeout = scriptConfig.timeoutSeconds
            snippet.isEphemeral = scriptConfig.isEphemeral
        }
        editingTitle = title
        editingScriptShell = scriptConfig.shell
        editingScriptTimeout = scriptConfig.timeoutSeconds
        hasUnsavedChanges = false
        load()
    }

    func clearScriptTestResult() {
        activeScriptTestRunID = nil
        scriptTestResult = nil
        isRunningScriptTest = false
    }

    func runScriptTest() {
        guard selectedSnippetID != nil, editingSnippetType == .script, !isRunningScriptTest else { return }
        let scriptConfig = ScriptSnippetConfig(
            shell: editingScriptShell,
            timeoutSeconds: editingScriptTimeout,
            isEphemeral: editingIsEphemeral
        )
        let request = SnippetExecutionRequest(content: editingContent, type: .script, scriptConfig: scriptConfig)
        let runID = UUID()
        activeScriptTestRunID = runID
        isRunningScriptTest = true
        scriptTestResult = nil

        scriptTestRunner(request) { [weak self] result in
            guard self?.activeScriptTestRunID == runID else { return }
            self?.scriptTestResult = result
            self?.isRunningScriptTest = false
            self?.activeScriptTestRunID = nil
        }
    }

    func addFolder() {
        let folder = CPYFolder.create()
        folder.merge()
        load()
        selectedFolderID = folder.identifier
        clearSnippetEditor()
    }

    func removeFolder(_ folderID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        let removesSelectedSnippet = selectedSnippetID.map { selectedSnippetID in
            folder.snippets.contains(where: { $0.identifier == selectedSnippetID })
        } ?? false
        folder.remove()
        if selectedFolderID == folderID || removesSelectedSnippet {
            selectedFolderID = nil
            clearSnippetEditor()
        }
        load()
    }

    func addSnippet(to folderID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        let snippet = folder.createSnippet()
        folder.mergeSnippet(snippet)
        load()
        if let folderItem = folders.first(where: { $0.id == folderID }),
           let newSnippet = folderItem.snippets.last {
            selectSnippet(newSnippet)
        }
    }

    func installTemplate(_ template: SnippetTemplate) -> String? {
        if hasUnsavedChanges { saveCurrentSnippet() }
        guard let realm = Realm.safeInstance() else { return nil }
        guard let folder = templateInstallFolder(in: realm) else { return nil }

        let snippet = folder.createSnippet()
        snippet.title = template.name
        snippet.content = template.content
        snippet.type = .script
        snippet.scriptShell = template.shell
        snippet.scriptTimeout = template.timeoutSeconds
        snippet.isEphemeral = template.isEphemeral
        let installedID = snippet.identifier

        folder.mergeSnippet(snippet)
        selectedFolderID = folder.identifier
        expandedFolderIDs.insert(folder.identifier)
        load()

        if let installed = loadedSnippet(id: installedID) {
            selectedFolderID = installed.folder.id
            loadEditingState(from: installed.snippet)
        }

        showingTemplateGallery = false
        return installedID
    }

    private func templateInstallFolder(in realm: Realm) -> CPYFolder? {
        if let selectedFolderID,
           let selectedFolder = realm.object(ofType: CPYFolder.self, forPrimaryKey: selectedFolderID),
           !selectedFolder.isVault {
            return selectedFolder
        }

        if let existingFolder = realm.objects(CPYFolder.self)
            .filter("title == %@ AND isVault == false", Self.defaultTemplateFolderTitle)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
            .first {
            return existingFolder
        }

        let folder = CPYFolder.create()
        folder.title = Self.defaultTemplateFolderTitle
        realm.transaction { realm.add(folder, update: .all) }
        return realm.object(ofType: CPYFolder.self, forPrimaryKey: folder.identifier)
    }

    func removeSnippet(_ snippetID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: snippetID) else { return }
        snippet.remove()
        if selectedSnippetID == snippetID {
            clearSnippetEditor()
        }
        load()
    }

    func toggleFolder(_ folderID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        realm.transaction { folder.enable = !folder.enable }
        load()
    }

    func toggleSnippet(_ snippetID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: snippetID) else { return }
        realm.transaction { snippet.enable = !snippet.enable }
        load()
    }

    func toggleVault(_ folderID: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        realm.transaction { folder.isVault = !folder.isVault }
        if !folder.isVault {
            VaultAuthService.shared.lock(folderID)
        }
        load()
    }

    func renameFolder(_ folderID: String, to newTitle: String) {
        guard let realm = Realm.safeInstance() else { return }
        guard let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else { return }
        let title = sanitizedFolderTitle(newTitle)
        realm.transaction { folder.title = title }
        load()
    }

    var selectedFolder: FolderItem? {
        folders.first { $0.id == selectedFolderID }
    }

    var totalSnippetCount: Int {
        folders.reduce(0) { $0 + $1.snippets.count }
    }
}

extension SnippetsEditorViewModel {

    // MARK: - Arrow Key Navigation

    /// Flat list of all selectable items (folders and their snippets) for arrow key navigation
    private var flatItems: [(kind: String, id: String, folderID: String?)] {
        var items = [(kind: String, id: String, folderID: String?)]()
        for folder in filteredFolders {
            items.append(("folder", folder.id, nil))
            if expandedFolderIDs.contains(folder.id) {
                for snippet in folder.snippets {
                    items.append(("snippet", snippet.id, folder.id))
                }
            }
        }
        return items
    }

    func moveSelectionUp() {
        let items = flatItems
        guard !items.isEmpty else { return }

        // Find current position
        let currentIndex: Int?
        if let sid = selectedSnippetID {
            currentIndex = items.firstIndex(where: { $0.kind == "snippet" && $0.id == sid })
        } else if let fid = selectedFolderID {
            currentIndex = items.firstIndex(where: { $0.kind == "folder" && $0.id == fid })
        } else {
            currentIndex = nil
        }

        let targetIndex = (currentIndex ?? items.count) - 1
        guard targetIndex >= 0 else { return }
        selectItem(items[targetIndex])
    }

    func moveSelectionDown() {
        let items = flatItems
        guard !items.isEmpty else { return }

        let currentIndex: Int?
        if let sid = selectedSnippetID {
            currentIndex = items.firstIndex(where: { $0.kind == "snippet" && $0.id == sid })
        } else if let fid = selectedFolderID {
            currentIndex = items.firstIndex(where: { $0.kind == "folder" && $0.id == fid })
        } else {
            currentIndex = nil
        }

        let targetIndex = (currentIndex ?? -1) + 1
        guard targetIndex < items.count else { return }
        selectItem(items[targetIndex])
    }

    func expandSelected() {
        guard let fid = selectedFolderID, selectedSnippetID == nil else { return }
        if !expandedFolderIDs.contains(fid) {
            if let folder = folders.first(where: { $0.id == fid }), folder.isVault, !VaultAuthService.shared.isUnlocked(fid) {
                // Vault folder — authenticate first
                VaultAuthService.shared.authenticate(folderID: fid, reason: "Unlock \"\(folder.title)\" vault") { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            withAnimation(.easeOut(duration: 0.15)) { _ = self?.expandedFolderIDs.insert(fid) }
                        }
                        // Force app activation and window focus after Touch ID
                        NSApp.activate(ignoringOtherApps: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            ModernSnippetsWindowController.shared.window?.makeKeyAndOrderFront(nil)
                            self?.needsRefocus = true
                        }
                    }
                }
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { expandedFolderIDs.insert(fid) }
        } else {
            // Already expanded — move into first snippet
            if let folder = filteredFolders.first(where: { $0.id == fid }), let first = folder.snippets.first {
                selectSnippet(first)
            }
        }
    }

    func collapseSelected() {
        if let sid = selectedSnippetID {
            // On a snippet — jump back to its folder
            if let folder = folders.first(where: { $0.snippets.contains(where: { $0.id == sid }) }) {
                selectedFolderID = folder.id
                clearSnippetEditor()
            }
        } else if let fid = selectedFolderID, expandedFolderIDs.contains(fid) {
            withAnimation(.easeOut(duration: 0.15)) { expandedFolderIDs.remove(fid) }
        }
    }

    private func selectItem(_ item: (kind: String, id: String, folderID: String?)) {
        if item.kind == "folder" {
            selectFolder(item.id)
        } else if let snippet = folders.flatMap({ $0.snippets }).first(where: { $0.id == item.id }) {
            selectSnippet(snippet)
        }
    }

    var filteredFolders: [FolderItem] {
        guard !sidebarFilter.isEmpty else { return folders }
        let query = sidebarFilter.lowercased()
        return folders.compactMap { folder in
            let matchingSnippets = folder.snippets.filter {
                $0.title.lowercased().contains(query) || $0.content.lowercased().contains(query)
            }
            let folderMatches = folder.title.lowercased().contains(query)
            if folderMatches || !matchingSnippets.isEmpty {
                return FolderItem(
                    id: folder.id,
                    title: folder.title,
                    enabled: folder.enabled,
                    isVault: folder.isVault,
                    snippets: folderMatches ? folder.snippets : matchingSnippets
                )
            }
            return nil
        }
    }

    // MARK: - Import / Export

    func exportSnippets() {
        guard let realm = Realm.safeInstance() else { return }
        let realmFolders = realm.objects(CPYFolder.self)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        let xmlDocument = SnippetXMLCoder.xmlDocument(from: realmFolders, includeVaultFolders: false)

        let panel = NSSavePanel()
        panel.canSelectHiddenExtension = true
        panel.allowedContentTypes = [.xml]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = "snippets"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = xmlDocument.xml.data(using: .utf8) else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowedContentTypes = [.xml]

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        do {
            guard let realm = Realm.safeInstance() else { return }
            let lastFolder = realm.objects(CPYFolder.self)
                .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true).last
            let folderIndex = (lastFolder?.index ?? -1) + 1
            let importedFolders = try SnippetXMLCoder.importFolders(from: data, startingAt: folderIndex)

            realm.transaction {
                importedFolders.forEach { realm.add($0) }
            }
            load()
        } catch {
            NSSound.beep()
        }
    }
}

extension SnippetsEditorViewModel {
    private struct SnippetLocation {
        let folderID: String
        let snippetID: String
        let index: Int
    }

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
        clearSnippetEditor()
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
        editingSnippetType = snippet.type
        editingScriptShell = snippet.scriptShell
        editingScriptTimeout = snippet.scriptTimeout
        editingIsEphemeral = snippet.isEphemeral
        clearScriptTestResult()
        hasUnsavedChanges = false
        expandedFolderIDs.insert(destinationFolderID)
        load()
    }

    func dropIndicator(for payload: SnippetDragPayload, target: SnippetDropTarget) -> SnippetDropIndicator? {
        switch payload {
        case .folder(let sourceFolderID):
            guard case let .folder(targetFolderID, targetIndex, _, _) = target,
                  sourceFolderID != targetFolderID,
                  let sourceIndex = folders.firstIndex(where: { $0.id == sourceFolderID }) else { return nil }

            return .folder(folderID: targetFolderID, edge: sourceIndex < targetIndex ? .after : .before)
        case .snippet(let snippetID):
            guard let sourceLocation = snippetLocation(for: snippetID) else { return nil }

            switch target {
            case let .folder(folderID, _, _, true):
                guard !isSameFolderEnd(sourceLocation: sourceLocation, folderID: folderID) else { return nil }
                return .snippetEnd(folderID: folderID)
            case let .snippet(folderID, snippetIndex):
                guard let targetSnippet = snippet(inFolderID: folderID, at: snippetIndex),
                      targetSnippet.snippetID != snippetID else { return nil }

                let edge: SnippetDropIndicatorEdge
                if sourceLocation.folderID == folderID {
                    edge = sourceLocation.index < snippetIndex ? .after : .before
                } else {
                    edge = .before
                }
                return .snippet(snippetID: targetSnippet.snippetID, edge: edge)
            case let .snippetEnd(folderID, _):
                guard !isSameFolderEnd(sourceLocation: sourceLocation, folderID: folderID) else { return nil }
                return .snippetEnd(folderID: folderID)
            case .folder(_, _, _, false):
                return nil
            }
        }
    }

    private func snippetLocation(for snippetID: String) -> SnippetLocation? {
        for folder in folders {
            if let index = folder.snippets.firstIndex(where: { $0.id == snippetID }) {
                return SnippetLocation(folderID: folder.id, snippetID: snippetID, index: index)
            }
        }
        return nil
    }

    private func snippet(inFolderID folderID: String, at index: Int) -> SnippetLocation? {
        guard let folder = folders.first(where: { $0.id == folderID }),
              folder.snippets.indices.contains(index) else { return nil }

        return SnippetLocation(folderID: folderID, snippetID: folder.snippets[index].id, index: index)
    }

    private func isSameFolderEnd(sourceLocation: SnippetLocation, folderID: String) -> Bool {
        guard sourceLocation.folderID == folderID,
              let folder = folders.first(where: { $0.id == folderID }) else { return false }

        return sourceLocation.index == folder.snippets.count - 1
    }
}

enum SnippetDragPayload: Equatable {
    private static let prefix = "clipy-snippet-editor-reorder:"
    private static let processToken = UUID().uuidString
    static let contentType = UTType(exportedAs: "com.clipyapp.clipy.snippet-reorder")
    static let fallbackContentType = UTType.utf8PlainText

    case folder(String)
    case snippet(String)

    init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix) else { return nil }

        let payload = rawValue.dropFirst(Self.prefix.count)
        let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == Self.processToken else { return nil }

        switch parts[1] {
        case "folder":
            self = .folder(parts[2])
        case "snippet":
            self = .snippet(parts[2])
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .folder(let identifier):
            return "\(Self.prefix)\(Self.processToken):folder:\(identifier)"
        case .snippet(let identifier):
            return "\(Self.prefix)\(Self.processToken):snippet:\(identifier)"
        }
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        [Self.contentType, Self.fallbackContentType].forEach { type in
            provider.registerDataRepresentation(
                forTypeIdentifier: type.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(rawValue.data(using: .utf8), nil)
                return nil
            }
        }
        provider.suggestedName = "Clipy Snippet Reorder"
        return provider
    }
}

enum SnippetDropIndicatorEdge {
    case before
    case after
}

enum SnippetDropIndicator: Equatable {
    case folder(folderID: String, edge: SnippetDropIndicatorEdge)
    case snippet(snippetID: String, edge: SnippetDropIndicatorEdge)
    case snippetEnd(folderID: String)
}

enum SnippetDropTarget {
    case folder(folderID: String, folderIndex: Int, snippetCount: Int, acceptsSnippets: Bool)
    case snippet(folderID: String, snippetIndex: Int)
    case snippetEnd(folderID: String, snippetCount: Int)

    var acceptedTypes: [UTType] {
        [SnippetDragPayload.fallbackContentType, SnippetDragPayload.contentType]
    }
}

enum SnippetDropPayloadResolution {
    static func resolve(activePayload: SnippetDragPayload?, hasConformingItems: Bool) -> SnippetDragPayload? {
        guard hasConformingItems else { return nil }
        return activePayload
    }
}

private struct SnippetDropDelegate: DropDelegate {
    let target: SnippetDropTarget
    let actions: SnippetDropActions

    func validateDrop(info: DropInfo) -> Bool {
        SnippetDropPayloadResolution.resolve(
            activePayload: actions.activePayload(),
            hasConformingItems: info.hasItemsConforming(to: target.acceptedTypes)
        ) != nil
    }

    func dropEntered(info: DropInfo) {
        actions.entered(target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        actions.exited(target)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let payload = SnippetDropPayloadResolution.resolve(
            activePayload: actions.activePayload(),
            hasConformingItems: info.hasItemsConforming(to: target.acceptedTypes)
        ) else {
            actions.ended()
            return false
        }

        // This drag starts inside the editor, so the process-local payload is already
        // authoritative; the item provider only lets SwiftUI route compatible drops.
        actions.payload(payload, target)
        actions.ended()
        return true
    }
}

private struct SnippetDropActions {
    let activePayload: () -> SnippetDragPayload?
    let payload: (SnippetDragPayload, SnippetDropTarget) -> Void
    let entered: (SnippetDropTarget) -> Void
    let exited: (SnippetDropTarget) -> Void
    let ended: () -> Void
}

private extension View {
    @ViewBuilder
    func snippetReorderDrag(enabled: Bool, provider: @escaping () -> NSItemProvider) -> some View {
        if enabled {
            self.onDrag(provider)
        } else {
            self
        }
    }

    @ViewBuilder
    func snippetReorderDrop(
        enabled: Bool,
        target: SnippetDropTarget,
        actions: SnippetDropActions
    ) -> some View {
        if enabled {
            self.onDrop(
                of: target.acceptedTypes,
                delegate: SnippetDropDelegate(target: target, actions: actions)
            )
        } else {
            self
        }
    }
}

private struct SnippetDragHandle: View {
    let reorderEnabled: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(reorderEnabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(SwiftUI.Color.clear))
            .frame(width: 12, height: 16)
            .contentShape(Rectangle())
            .help(reorderEnabled ? "Drag to reorder" : "Reordering is disabled while filtering")
    }
}

private struct SnippetInsertionIndicatorLine: View {
    var body: some View {
        Capsule()
            .fill(SwiftUI.Color.accentColor)
            .frame(height: 2)
            .shadow(color: SwiftUI.Color.accentColor.opacity(0.45), radius: 3, y: 1)
            .padding(.horizontal, 8)
            .transition(.opacity)
    }
}

private extension View {
    @ViewBuilder
    func snippetInsertionIndicator(_ edge: SnippetDropIndicatorEdge?, leadingPadding: CGFloat) -> some View {
        if let edge {
            self.overlay(alignment: edge == .before ? .top : .bottom) {
                SnippetInsertionIndicatorLine()
                    .padding(.leading, leadingPadding)
            }
        } else {
            self
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

enum SnippetWindowChromeItem: Hashable {
    case devBadge
    case closeButton
}

enum SnippetWindowChromeLayout {
    static let edgePadding: CGFloat = 8
    static let closeButtonSize: CGFloat = 24
    static let controlSpacing: CGFloat = 8
    static let contentGap: CGFloat = 12

    #if DEBUG
    private static let devBadgeWidth: CGFloat = 32
    #else
    private static let devBadgeWidth: CGFloat = 0
    #endif

    static var topTrailingControlsWidth: CGFloat {
        closeButtonSize + devBadgeWidth + (devBadgeWidth > 0 ? controlSpacing : 0)
    }

    static var controlOrder: [SnippetWindowChromeItem] {
        #if DEBUG
        [.devBadge, .closeButton]
        #else
        [.closeButton]
        #endif
    }

    static var headerTrailingReserve: CGFloat {
        edgePadding + topTrailingControlsWidth + contentGap
    }
}

// MARK: - Main Editor View
// swiftlint:disable:next type_body_length
struct ModernSnippetsEditorView: View {
    @StateObject private var viewModel = SnippetsEditorViewModel()
    @State private var draggedPayload: SnippetDragPayload?
    @State private var dropIndicator: SnippetDropIndicator?
    @FocusState private var sidebarFocused: Bool
    @FocusState private var snippetTitleFocused: Bool
    let onClose: () -> Void

    private var reorderEnabled: Bool {
        viewModel.sidebarFilter.isEmpty
    }

    private var scriptShellOptions: [String] {
        [CPYSnippet.defaultScriptShell, "/bin/zsh", "/bin/bash"]
    }

    private var scriptTestOutputPreviewLimit: Int {
        8_000
    }

    private var snippetTypeBinding: Binding<CPYSnippet.SnippetType> {
        Binding(
            get: { viewModel.editingSnippetType },
            set: { newValue in
                viewModel.editingSnippetType = newValue
                viewModel.hasUnsavedChanges = true
                viewModel.clearScriptTestResult()
            }
        )
    }

    private var scriptShellBinding: Binding<String> {
        Binding(
            get: { viewModel.editingScriptShell },
            set: { newValue in
                viewModel.editingScriptShell = newValue
                viewModel.hasUnsavedChanges = true
                viewModel.clearScriptTestResult()
            }
        )
    }

    private var scriptTimeoutBinding: Binding<Int> {
        Binding(
            get: { viewModel.editingScriptTimeout },
            set: { newValue in
                viewModel.editingScriptTimeout = newValue
                viewModel.hasUnsavedChanges = true
                viewModel.clearScriptTestResult()
            }
        )
    }

    private var scriptEphemeralBinding: Binding<Bool> {
        Binding(
            get: { viewModel.editingIsEphemeral },
            set: { newValue in
                viewModel.editingIsEphemeral = newValue
                viewModel.hasUnsavedChanges = true
                viewModel.clearScriptTestResult()
            }
        )
    }

    private var dropActions: SnippetDropActions {
        SnippetDropActions(
            activePayload: { reorderEnabled ? draggedPayload : nil },
            payload: handleDrop,
            entered: handleDropEntered,
            exited: handleDropExited,
            ended: clearDropPreview
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider().opacity(0.4)
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 740, height: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .overlay(alignment: .top) {
            WindowDragRegion()
                .frame(height: 8)
        }
        .overlay(alignment: .topTrailing) { topTrailingChrome }
        .onAppear { viewModel.load() }
        .onChange(of: viewModel.needsRefocus) { _, needs in
            if needs {
                viewModel.needsRefocus = false
                sidebarFocused = true
            }
        }
    }

    private var topTrailingChrome: some View {
        HStack(spacing: SnippetWindowChromeLayout.controlSpacing) {
            ForEach(SnippetWindowChromeLayout.controlOrder, id: \.self) { item in
                topTrailingChromeItem(item)
            }
        }
        .padding(SnippetWindowChromeLayout.edgePadding)
    }

    @ViewBuilder
    private func topTrailingChromeItem(_ item: SnippetWindowChromeItem) -> some View {
        switch item {
        case .devBadge:
            #if DEBUG
            Text("DEV")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            #else
            EmptyView()
            #endif
        case .closeButton:
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: SnippetWindowChromeLayout.closeButtonSize,
                        height: SnippetWindowChromeLayout.closeButtonSize
                    )
                    .background(.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search/filter bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.tertiary)
                TextField("Filter snippets\u{2026}", text: $viewModel.sidebarFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .light))
                if !viewModel.sidebarFilter.isEmpty {
                    Button { viewModel.sidebarFilter = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.4)

            // Folder list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.filteredFolders.enumerated()), id: \.element.id) { folderIndex, folder in
                        SnippetFolderRow(
                            folder: folder,
                            folderIndex: folderIndex,
                            isSelected: viewModel.selectedFolderID == folder.id,
                            selectedSnippetID: viewModel.selectedSnippetID,
                            reorderEnabled: reorderEnabled,
                            dropIndicator: dropIndicator,
                            dragProvider: dragProvider,
                            dropActions: dropActions,
                            onSelectFolder: { viewModel.selectFolder(folder.id) },
                            onSelectSnippet: { viewModel.selectSnippet($0) },
                            onAddSnippet: { viewModel.addSnippet(to: folder.id) },
                            onDeleteFolder: { viewModel.removeFolder(folder.id) },
                            onDeleteSnippet: { viewModel.removeSnippet($0.id) },
                            onToggleFolder: { viewModel.toggleFolder(folder.id) },
                            onToggleSnippet: { viewModel.toggleSnippet($0.id) },
                            onRenameFolder: { viewModel.renameFolder(folder.id, to: $0) },
                            onToggleVault: { viewModel.toggleVault(folder.id) },
                            isExpanded: Binding(
                                get: { viewModel.expandedFolderIDs.contains(folder.id) },
                                set: { newValue in
                                    if newValue {
                                        viewModel.expandedFolderIDs.insert(folder.id)
                                    } else {
                                        viewModel.expandedFolderIDs.remove(folder.id)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(6)
            }

            Divider().opacity(0.4)

            // Footer toolbar
            sidebarFooter
        }
        .background(.black.opacity(0.03))
        .focusable()
        .focusEffectDisabled()
        .focused($sidebarFocused)
        .onAppear { sidebarFocused = true }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in viewModel.moveSelectionUp(); return .handled }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in viewModel.moveSelectionDown(); return .handled }
        .onKeyPress(.rightArrow, phases: .down) { _ in viewModel.expandSelected(); return .handled }
        .onKeyPress(.leftArrow, phases: .down) { _ in viewModel.collapseSelected(); return .handled }
    }

    private func dragProvider(for payload: SnippetDragPayload) -> NSItemProvider {
        draggedPayload = payload
        return payload.itemProvider()
    }

    private func handleDropEntered(target: SnippetDropTarget) {
        guard reorderEnabled, let draggedPayload else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            dropIndicator = viewModel.dropIndicator(for: draggedPayload, target: target)
        }
    }

    private func handleDropExited(target _: SnippetDropTarget) {
        withAnimation(.easeInOut(duration: 0.08)) {
            dropIndicator = nil
        }
    }

    private func clearDropPreview() {
        withAnimation(.easeInOut(duration: 0.08)) {
            draggedPayload = nil
            dropIndicator = nil
        }
    }

    private func handleDrop(payload: SnippetDragPayload, target: SnippetDropTarget) {
        guard reorderEnabled else { return }

        switch payload {
        case .folder(let folderID):
            guard case let .folder(_, folderIndex, _, _) = target else { return }
            viewModel.moveFolder(id: folderID, toIndex: folderIndex)
        case .snippet(let snippetID):
            switch target {
            case let .folder(folderID, _, snippetCount, true):
                viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetCount)
            case let .snippet(folderID, snippetIndex):
                viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetIndex)
            case let .snippetEnd(folderID, snippetCount):
                viewModel.moveSnippet(id: snippetID, toFolderID: folderID, toIndex: snippetCount)
            case .folder(_, _, _, false):
                return
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            // Add folder
            SnippetToolbarButton(icon: "folder.badge.plus", help: "Add Folder") {
                viewModel.addFolder()
            }

            // Add snippet to current folder
            if viewModel.selectedFolderID != nil {
                SnippetToolbarButton(icon: "doc.badge.plus", help: "Add Snippet") {
                    if let folderID = viewModel.selectedFolderID {
                        viewModel.addSnippet(to: folderID)
                    }
                }
            }

            SnippetToolbarButton(icon: "terminal.fill", help: "Add Script Template") {
                viewModel.showingTemplateGallery = true
            }
            .popover(isPresented: $viewModel.showingTemplateGallery, arrowEdge: .bottom) {
                SnippetTemplateGalleryView(viewModel: viewModel)
            }

            Spacer()

            Text("\(viewModel.totalSnippetCount) snippets")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            SnippetToolbarButton(icon: "square.and.arrow.down", help: "Import") {
                viewModel.importSnippets()
            }
            SnippetToolbarButton(icon: "square.and.arrow.up", help: "Export") {
                viewModel.exportSnippets()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Editor Pane
    private var editorPane: some View {
        Group {
            if let snippetID = viewModel.selectedSnippetID,
               let folder = viewModel.folders.first(where: { $0.snippets.contains(where: { $0.id == snippetID }) }),
               let snippet = folder.snippets.first(where: { $0.id == snippetID }) {
                VStack(spacing: 0) {
                    editorHeader(snippet: snippet, folder: folder)
                    Divider().opacity(0.3)
                    editorBody
                    Divider().opacity(0.3)
                    if viewModel.editingSnippetType == .script {
                        scriptTestPanel
                    } else {
                        variablesBar
                    }
                    Divider().opacity(0.3)
                    editorFooter
                }
            } else {
                emptyEditor
            }
        }
        .background(.black.opacity(0.02))
    }

    private func editorHeader(snippet: SnippetsEditorViewModel.SnippetItem, folder: SnippetsEditorViewModel.FolderItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.editingSnippetType == .script ? "terminal.fill" : "doc.text.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(viewModel.editingSnippetType == .script ? .green : .blue)
                    .frame(width: 26, height: 26)
                    .background((viewModel.editingSnippetType == .script ? SwiftUI.Color.green : .blue).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                TextField("Snippet title", text: $viewModel.editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($snippetTitleFocused)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        snippetTitleFocused
                            ? AnyShapeStyle(.white.opacity(0.08))
                            : AnyShapeStyle(SwiftUI.Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                snippetTitleFocused ? SwiftUI.Color.accentColor.opacity(0.65) : .white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .onChange(of: viewModel.editingTitle) { _, _ in
                        viewModel.hasUnsavedChanges = true
                    }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8))
                    Text(folder.title)
                        .font(.system(size: 9, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .foregroundStyle(.secondary)

                Circle()
                    .fill(snippet.enabled ? SwiftUI.Color.green : SwiftUI.Color.gray)
                    .frame(width: 7, height: 7)
                    .help(snippet.enabled ? "Enabled" : "Disabled")
            }
            .padding(.trailing, SnippetWindowChromeLayout.headerTrailingReserve)

            VStack(alignment: .leading, spacing: 7) {
                Picker("", selection: snippetTypeBinding) {
                    Text("Text").tag(CPYSnippet.SnippetType.plainText)
                    Text("Script").tag(CPYSnippet.SnippetType.script)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 132)

                if viewModel.editingSnippetType == .script {
                    HStack(spacing: 10) {
                        Picker("", selection: scriptShellBinding) {
                            ForEach(scriptShellOptions, id: \.self) { shell in
                                Text(shell).tag(shell)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 96)
                        .help("Shell")

                        Stepper(value: scriptTimeoutBinding, in: ScriptSnippetConfig.minimumTimeoutSeconds...ScriptSnippetConfig.maximumTimeoutSeconds) {
                            Label("\(viewModel.editingScriptTimeout)s", systemImage: "timer")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 104)
                        .help("Timeout")

                        Toggle(isOn: scriptEphemeralBinding) {
                            Text("Ephemeral output")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .toggleStyle(.checkbox)
                        .help("Do not save script output to clipboard history")

                        Spacer(minLength: 4)

                        Button {
                            viewModel.runScriptTest()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: viewModel.isRunningScriptTest ? "hourglass" : "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(viewModel.isRunningScriptTest ? "Running" : "Test Run")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.07))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isRunningScriptTest)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var editorBody: some View {
        TextEditor(text: $viewModel.editingContent)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: viewModel.editingContent) { _, _ in
                viewModel.hasUnsavedChanges = true
                if viewModel.editingSnippetType == .script {
                    viewModel.clearScriptTestResult()
                }
            }
    }

    private var variablesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Image(systemName: "percent")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)

                ForEach(SnippetVariableProcessor.availableVariables, id: \.name) { variable in
                    Button {
                        viewModel.editingContent += variable.name
                        viewModel.hasUnsavedChanges = true
                    } label: {
                        Text(variable.name)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(variable.desc)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private var scriptTestPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: scriptTestStatusIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(scriptTestStatusColor)

                Text(scriptTestStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let result = viewModel.scriptTestResult {
                    Text("exit \(result.exitCode)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if result.timedOut {
                        Text("timeout")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let result = viewModel.scriptTestResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        scriptTestOutputBlock(title: "stdout", value: previewScriptTestOutput(result.output))
                        scriptTestOutputBlock(title: "stderr", value: previewScriptTestOutput(result.stderr))
                        if let launchError = result.launchError {
                            scriptTestOutputBlock(title: "launch", value: previewScriptTestOutput(launchError))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 92)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.025))
    }

    private var scriptTestStatusIcon: String {
        if viewModel.isRunningScriptTest { return "hourglass" }
        guard let result = viewModel.scriptTestResult else { return "play.circle" }
        if result.timedOut { return "timer" }
        return result.exitCode == 0 && result.launchError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var scriptTestStatusText: String {
        if viewModel.isRunningScriptTest { return "Running script" }
        guard let result = viewModel.scriptTestResult else { return "No test run" }
        if result.timedOut { return "Timed out" }
        if result.launchError != nil { return "Launch failed" }
        return result.exitCode == 0 ? "Finished" : "Failed"
    }

    private var scriptTestStatusColor: SwiftUI.Color {
        if viewModel.isRunningScriptTest { return .secondary }
        guard let result = viewModel.scriptTestResult else { return .secondary.opacity(0.55) }
        if result.timedOut { return .orange }
        return result.exitCode == 0 && result.launchError == nil ? .green : .red
    }

    private func previewScriptTestOutput(_ value: String) -> String {
        guard value.count > scriptTestOutputPreviewLimit else { return value }
        let visible = value.prefix(scriptTestOutputPreviewLimit)
        return "\(visible)\n... truncated \(value.count - scriptTestOutputPreviewLimit) characters"
    }

    private func scriptTestOutputBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value.isEmpty ? "(empty)" : value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 12) {
            snippetKBHint("\u{2318}S", "save")
            snippetKBHint("\u{2318}N", "new")

            Spacer()

            if viewModel.hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 5, height: 5)
                    Text("Unsaved")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .transition(.opacity)
            }

            Button {
                viewModel.saveCurrentSnippet()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(viewModel.hasUnsavedChanges ? SwiftUI.Color.accentColor : .white.opacity(0.06))
                .foregroundStyle(viewModel.hasUnsavedChanges ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var emptyEditor: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("Select a snippet to edit")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            if viewModel.selectedFolderID != nil {
                Button {
                    if let folderID = viewModel.selectedFolderID {
                        viewModel.addSnippet(to: folderID)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New Snippet")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(SwiftUI.Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func snippetKBHint(_ key: String, _ label: String) -> some View {
        KeyboardHintView(key: key, label: label)
    }
}

// MARK: - Template Gallery
private struct SnippetTemplateGalleryView: View {
    @ObservedObject var viewModel: SnippetsEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Script Templates")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    viewModel.showingTemplateGallery = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SnippetTemplateLibrary.categories, id: \.self) { category in
                        templateSection(category)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 420, height: 420)
        .background(.regularMaterial)
    }

    private func templateSection(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            ForEach(SnippetTemplateLibrary.templates(in: category)) { template in
                templateRow(template)
            }
        }
    }

    private func templateRow(_ template: SnippetTemplate) -> some View {
        HStack(spacing: 9) {
            Image(systemName: template.systemImageName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
                .background(SwiftUI.Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(template.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button {
                _ = viewModel.installTemplate(template)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
                    .background(SwiftUI.Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Add")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Folder Row
private struct SnippetFolderRow: View {
    let folder: SnippetsEditorViewModel.FolderItem
    let folderIndex: Int
    let isSelected: Bool
    let selectedSnippetID: String?
    let reorderEnabled: Bool
    let dropIndicator: SnippetDropIndicator?
    let dragProvider: (SnippetDragPayload) -> NSItemProvider
    let dropActions: SnippetDropActions
    let onSelectFolder: () -> Void
    let onSelectSnippet: (SnippetsEditorViewModel.SnippetItem) -> Void
    let onAddSnippet: () -> Void
    let onDeleteFolder: () -> Void
    let onDeleteSnippet: (SnippetsEditorViewModel.SnippetItem) -> Void
    let onToggleFolder: () -> Void
    let onToggleSnippet: (SnippetsEditorViewModel.SnippetItem) -> Void
    let onRenameFolder: (String) -> Void
    let onToggleVault: () -> Void

    @Binding var isExpanded: Bool
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var isHovered = false
    @State private var isVaultUnlocked = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        VStack(spacing: 1) {
            // Folder header
            HStack(spacing: 6) {
                SnippetDragHandle(reorderEnabled: reorderEnabled)

                Button {
                    if folder.isVault && !isVaultUnlocked && !isExpanded {
                        VaultAuthService.shared.authenticate(folderID: folder.id, reason: "Unlock \"\(folder.title)\" vault") { success in
                            DispatchQueue.main.async {
                                if success {
                                    isVaultUnlocked = true
                                    withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
                                }
                                NSApp.activate(ignoringOtherApps: true)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    ModernSnippetsWindowController.shared.window?.makeKeyAndOrderFront(nil)
                                }
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isExpanded.toggle()
                            if !isExpanded && folder.isVault {
                                isVaultUnlocked = false
                                VaultAuthService.shared.lock(folder.id)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                Image(systemName: folder.isVault ? (isVaultUnlocked ? "lock.open.fill" : "lock.fill") : folder.enabled ? "folder.fill" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(folder.isVault ? (isVaultUnlocked ? SwiftUI.Color.green : SwiftUI.Color.orange) : folder.enabled ? SwiftUI.Color.accentColor : .secondary)

                if isEditing {
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
                                .strokeBorder(
                                    titleFieldFocused ? SwiftUI.Color.accentColor.opacity(0.75) : .white.opacity(0.12),
                                    lineWidth: 1
                                )
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
                } else {
                    Text(folder.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(folder.enabled ? .primary : .secondary)
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            editedTitle = folder.title
                            isEditing = true
                        }
                }

                Spacer()

                // Hover: add snippet button
                if isHovered {
                    Button { onAddSnippet() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                Text("\(folder.snippets.count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? AnyShapeStyle(SwiftUI.Color.accentColor.opacity(0.85))
                    : isHovered
                        ? AnyShapeStyle(.white.opacity(0.05))
                        : AnyShapeStyle(SwiftUI.Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .snippetInsertionIndicator(folderHeaderIndicatorEdge, leadingPadding: 0)
            .onTapGesture { onSelectFolder() }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
            }
            .snippetReorderDrag(enabled: reorderEnabled) {
                dragProvider(.folder(folder.id))
            }
            .snippetReorderDrop(
                enabled: reorderEnabled,
                target: .folder(
                    folderID: folder.id,
                    folderIndex: folderIndex,
                    snippetCount: folder.snippets.count,
                    acceptsSnippets: !folder.isVault || isVaultUnlocked
                ),
                actions: dropActions
            )
            .contextMenu {
                Button("Add Snippet") { onAddSnippet() }
                Button(folder.enabled ? "Disable" : "Enable") { onToggleFolder() }
                Divider()
                Button(folder.isVault ? "Remove Vault Protection" : "Set as Vault (Touch ID)") {
                    onToggleVault()
                    if !folder.isVault {
                        // Becoming vault — collapse and lock
                        isExpanded = false
                        isVaultUnlocked = false
                    }
                }
                Divider()
                Button("Rename") {
                    editedTitle = folder.title
                    isEditing = true
                }
                Button("Delete", role: .destructive) { onDeleteFolder() }
            }

            // Snippet rows (vault folders require auth to see snippets)
            if isExpanded && (!folder.isVault || isVaultUnlocked) {
                ForEach(Array(folder.snippets.enumerated()), id: \.element.id) { snippetIndex, snippet in
                    SnippetItemRow(
                        snippet: snippet,
                        folderID: folder.id,
                        snippetIndex: snippetIndex,
                        isSelected: selectedSnippetID == snippet.id,
                        reorderEnabled: reorderEnabled,
                        dropIndicator: dropIndicator,
                        dragProvider: dragProvider,
                        dropActions: dropActions,
                        onSelect: { onSelectSnippet(snippet) },
                        onDelete: { onDeleteSnippet(snippet) },
                        onToggle: { onToggleSnippet(snippet) }
                    )
                }

                ZStack {
                    if showsSnippetEndIndicatorInExpandedFolder {
                        SnippetInsertionIndicatorLine()
                            .padding(.leading, 26)
                    }
                }
                .frame(height: 6)
                .snippetReorderDrop(
                    enabled: reorderEnabled,
                    target: .snippetEnd(folderID: folder.id, snippetCount: folder.snippets.count),
                    actions: dropActions
                )
            }
        }
    }

    private func commitRename() {
        onRenameFolder(editedTitle)
        isEditing = false
    }

    private var folderHeaderIndicatorEdge: SnippetDropIndicatorEdge? {
        if case let .folder(folderID, edge) = dropIndicator, folderID == folder.id {
            return edge
        }
        if case let .snippetEnd(folderID) = dropIndicator,
           folderID == folder.id,
           !showsSnippetEndIndicatorInExpandedFolder {
            return .after
        }
        return nil
    }

    private var showsSnippetEndIndicatorInExpandedFolder: Bool {
        if case let .snippetEnd(folderID) = dropIndicator,
           folderID == folder.id,
           isExpanded,
           !folder.isVault || isVaultUnlocked {
            return true
        }
        return false
    }
}

// MARK: - Snippet Item Row
private struct SnippetItemRow: View {
    let snippet: SnippetsEditorViewModel.SnippetItem
    let folderID: String
    let snippetIndex: Int
    let isSelected: Bool
    let reorderEnabled: Bool
    let dropIndicator: SnippetDropIndicator?
    let dragProvider: (SnippetDragPayload) -> NSItemProvider
    let dropActions: SnippetDropActions
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 8)

            SnippetDragHandle(reorderEnabled: reorderEnabled)

            Image(systemName: snippet.isScript ? "terminal.fill" : snippet.enabled ? "doc.text.fill" : "doc.text")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(.white)
                        : !snippet.enabled
                            ? AnyShapeStyle(.quaternary)
                            : snippet.isScript
                            ? AnyShapeStyle(SwiftUI.Color.green)
                            : AnyShapeStyle(.blue)
                )
                .frame(width: 22, height: 22)
                .background(
                    isSelected
                        ? AnyShapeStyle(.white.opacity(0.15))
                        : AnyShapeStyle(
                            !snippet.enabled
                                ? SwiftUI.Color.clear
                                : snippet.isScript
                                ? SwiftUI.Color.green.opacity(0.08)
                                : SwiftUI.Color.blue.opacity(0.08)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : snippet.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)

                if !snippet.content.isEmpty {
                    Text(snippet.content.prefix(60).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.quaternary))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button { onDelete() } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected
                ? AnyShapeStyle(SwiftUI.Color.accentColor.opacity(0.75))
                : isHovered
                    ? AnyShapeStyle(.white.opacity(0.04))
                    : AnyShapeStyle(SwiftUI.Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .snippetInsertionIndicator(snippetIndicatorEdge, leadingPadding: 26)
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .snippetReorderDrag(enabled: reorderEnabled) {
            dragProvider(.snippet(snippet.id))
        }
        .snippetReorderDrop(
            enabled: reorderEnabled,
            target: .snippet(folderID: folderID, snippetIndex: snippetIndex),
            actions: dropActions
        )
        .contextMenu {
            Button(snippet.enabled ? "Disable" : "Enable") { onToggle() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var snippetIndicatorEdge: SnippetDropIndicatorEdge? {
        if case let .snippet(snippetID, edge) = dropIndicator, snippetID == snippet.id {
            return edge
        }
        return nil
    }
}

// MARK: - Toolbar Button
struct SnippetToolbarButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(isHovered ? .white.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Window Controller
class ModernSnippetsWindowController: NSWindowController {
    static let shared = ModernSnippetsWindowController()
    private var keyMonitor: Any?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Snippets"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.collectionBehavior = .canJoinAllSpaces

        super.init(window: window)

        let hostView = NSHostingView(rootView: ModernSnippetsEditorView(onClose: { [weak self] in
            self?.close()
        }))
        window.contentView = hostView
        window.delegate = self
        DispatchQueue.main.async {
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = .clear
            hostView.layer?.isOpaque = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        let hostView = NSHostingView(rootView: ModernSnippetsEditorView(onClose: { [weak self] in
            self?.close()
        }))
        window?.contentView = hostView
        DispatchQueue.main.async {
            hostView.wantsLayer = true
            hostView.layer?.backgroundColor = .clear
            hostView.layer?.isOpaque = false
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }
    }

    override func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        super.close()
    }
}

extension ModernSnippetsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor), object: nil)
        NSApp.deactivate()
    }
}
