//
//  MenuManager.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//
//  Created by Econa77 on 2016/03/08.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import RealmSwift
import Combine

final class MenuManager: NSObject {

    // MARK: - Properties
    // Menus
    fileprivate var clipMenu: NSMenu?
    fileprivate var historyMenu: NSMenu?
    fileprivate var snippetMenu: NSMenu?
    // StatusMenu
    fileprivate var statusItem: NSStatusItem?
    // Icon Cache
    fileprivate let folderIcon = Asset.iconFolder.image
    fileprivate let snippetIcon = Asset.iconText.image
    // Other
    fileprivate let notificationCenter = NotificationCenter.default
    fileprivate let kMaxKeyEquivalents = 10
    fileprivate let shortenSymbol = "..."
    // Realm
    fileprivate var realm: Realm?
    fileprivate var clipToken: NotificationToken?
    fileprivate var snippetToken: NotificationToken?
    // Combine
    fileprivate var cancellables = Set<AnyCancellable>()
    fileprivate var menuKeyMonitor: Any?
    fileprivate var openMenus = [NSMenu]()

    // MARK: - Enum Values
    enum StatusType: Int {
        case none, black, white
    }

    // MARK: - Initialize
    override init() {
        super.init()
        folderIcon.isTemplate = true
        folderIcon.size = NSSize(width: 15, height: 13)
        snippetIcon.isTemplate = true
        snippetIcon.size = NSSize(width: 12, height: 13)
        realm = Realm.safeInstance()
    }

    func setup() {
        bind()
    }

    @MainActor
    func refresh() {
        createClipMenu()
    }

    var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

// MARK: - Popup Menu
extension MenuManager {
    @MainActor
    func popUpMenu(_ type: MenuType) {
        let menu: NSMenu?
        switch type {
        case .main:
            menu = clipMenu
        case .history:
            menu = historyMenu
        case .snippet:
            menu = snippetMenu
        }
        if let menu {
            presentMenu(menu)
        }
    }

    @MainActor
    func popUpSnippetFolder(_ folder: CPYFolder) {
        if folder.isVault && !isVaultUnlocked(folder.identifier) {
            authenticateVault(folderID: folder.identifier, title: folder.title) { [weak self] success in
                guard success else { return }
                Task { @MainActor [weak self] in
                    self?.refresh()
                    self?.popUpSnippetFolder(folder)
                }
            }
            return
        }

        let folderMenu = NSMenu(title: folder.title)
        folderMenu.delegate = self
        let labelItem = NSMenuItem(title: folder.title, action: nil)
        labelItem.isEnabled = false
        folderMenu.addItem(labelItem)
        var index = firstIndexOfMenuItems()
        folder.snippets
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
            .filter { $0.enable }
            .forEach { snippet in
                let subMenuItem = makeSnippetMenuItem(snippet, listNumber: index)
                folderMenu.addItem(subMenuItem)
                index += 1
        }
        presentMenu(folderMenu)
    }

    @MainActor
    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance(),
              let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip)
    }

    @MainActor
    @objc func selectSnippetMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance(),
              let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }

        let processed = SnippetVariableProcessor.process(snippet.content)
        AppEnvironment.current.pasteService.copyToPasteboard(with: processed)
        AppEnvironment.current.pasteService.paste()
    }

    private func presentMenu(_ menu: NSMenu) {
        presentMenu(menu, relativeTo: nil)
    }

    @MainActor
    @objc func popUpStatusItemMenu(_ sender: Any?) {
        guard let clipMenu else { return }
        if let statusItem {
            statusItem.popUpMenu(clipMenu)
        } else {
            presentMenu(clipMenu)
        }
    }

    private func presentMenu(_ menu: NSMenu, relativeTo view: NSView?) {
        if let view {
            let origin = NSPoint(x: 0, y: view.bounds.maxY + 4)
            menu.popUp(positioning: nil, at: origin, in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

}

// MARK: - Menu Delegation
extension MenuManager: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        openMenus.removeAll { $0 == menu }
        openMenus.append(menu)
        installMenuKeyMonitorIfNeeded()
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.removeAll { $0 == menu }
        if openMenus.isEmpty {
            removeMenuKeyMonitor()
        }
    }

    private func installMenuKeyMonitorIfNeeded() {
        guard menuKeyMonitor == nil else { return }

        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleReturnKey(event) {
                return nil
            }
            return self.remapBackspaceToLeftArrow(event)
        }
    }

    private func removeMenuKeyMonitor() {
        guard let menuKeyMonitor else { return }
        NSEvent.removeMonitor(menuKeyMonitor)
        self.menuKeyMonitor = nil
    }

    private func remapBackspaceToLeftArrow(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              event.keyCode == 51 else {
            return event
        }

        let relevantModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard relevantModifiers.isDisjoint(with: disallowedModifiers) else {
            return event
        }

        let leftArrowCharacter = String(Character(UnicodeScalar(Int(NSLeftArrowFunctionKey))!))

        return NSEvent.keyEvent(with: .keyDown,
                                location: event.locationInWindow,
                                modifierFlags: event.modifierFlags,
                                timestamp: event.timestamp,
                                windowNumber: event.windowNumber,
                                context: nil,
                                characters: leftArrowCharacter,
                                charactersIgnoringModifiers: leftArrowCharacter,
                                isARepeat: event.isARepeat,
                                keyCode: 123)
    }

    private func handleReturnKey(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]

        guard event.type == .keyDown,
              event.keyCode == 36 || event.keyCode == 76,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: disallowedModifiers),
              let activeMenu = openMenus.last,
              let highlightedItem = activeMenu.highlightedItem,
              highlightedItem.isEnabled,
              !highlightedItem.isHidden else {
            return false
        }

        if highlightedItem.hasSubmenu {
            activeMenu.submenuAction(highlightedItem)
            return true
        }

        guard let highlightedIndex = activeMenu.items.firstIndex(of: highlightedItem) else {
            return false
        }

        activeMenu.performActionForItem(at: highlightedIndex)
        return true
    }
}

// MARK: - Vault Helpers
@MainActor
private extension MenuManager {
    func isVaultUnlocked(_ folderID: String) -> Bool {
        VaultAuthService.shared.isUnlocked(folderID)
    }

    func authenticateVault(folderID: String, title: String, completion: @escaping (Bool) -> Void) {
        VaultAuthService.shared.authenticate(folderID: folderID, reason: "Unlock \"\(title)\" vault") { success in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}

// MARK: - Binding
private extension MenuManager {
    func bind() {
        guard let realm = realm else { return }

        // Realm Notifications
        clipToken = realm.objects(CPYClip.self)
                        .observe { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.createClipMenu()
                            }
                        }
        snippetToken = realm.objects(CPYFolder.self)
                        .observe { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.createClipMenu()
                            }
                        }

        let defaults = AppEnvironment.current.defaults

        // Status item icon
        defaults.publisher(for: \.clipyShowStatusItem)
            .compactMap { $0 as? Int }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in
                self?.changeStatusItem(StatusType(rawValue: key) ?? .black)
            }
            .store(in: &cancellables)

        // Sort clips
        defaults.publisher(for: \.clipyReorderClips)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.createClipMenu()
                }
            }
            .store(in: &cancellables)

        // Edit snippets notification
        notificationCenter
            .publisher(for: Notification.Name(rawValue: Constants.Notification.closeSnippetEditor))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.createClipMenu()
                }
            }
            .store(in: &cancellables)

        // Observe menu preference changes
        let menuPreferenceKeys: [String] = [
            Constants.UserDefaults.addClearHistoryMenuItem,
            Constants.UserDefaults.maxHistorySize,
            Constants.UserDefaults.showIconInTheMenu,
            Constants.UserDefaults.numberOfItemsPlaceInline,
            Constants.UserDefaults.numberOfItemsPlaceInsideFolder,
            Constants.UserDefaults.maxMenuItemTitleLength,
            Constants.UserDefaults.menuItemsTitleStartWithZero,
            Constants.UserDefaults.menuItemsAreMarkedWithNumbers,
            Constants.UserDefaults.showToolTipOnMenuItem,
            Constants.UserDefaults.showImageInTheMenu,
            Constants.UserDefaults.addNumericKeyEquivalents,
            Constants.UserDefaults.maxLengthOfToolTip,
            Constants.UserDefaults.showColorPreviewInTheMenu
        ]

        // Use a single publisher merging all preference key observations
        let publishers = menuPreferenceKeys.map { key in
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in key }
        }

        Publishers.MergeMany(publishers)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.createClipMenu()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Menus
private extension MenuManager {
    @MainActor
     func createClipMenu() {
        clipMenu = NSMenu(title: Constants.Application.name)
        historyMenu = NSMenu(title: Constants.Menu.history)
        snippetMenu = NSMenu(title: Constants.Menu.snippet)
        clipMenu?.delegate = self
        historyMenu?.delegate = self
        snippetMenu?.delegate = self

        addHistoryItems(clipMenu!)
        addHistoryItems(historyMenu!)
        addSnippetItems(clipMenu!, separateMenu: true)
        addSnippetItems(snippetMenu!, separateMenu: false)

        let isCollecting = ClipboardQueueService.shared.isCollecting
        clipMenu?.addItem(NSMenuItem.separator())
        if isCollecting {
            let stopItem = NSMenuItem(title: "Stop Collecting (\(ClipboardQueueService.shared.itemCount))", action: #selector(AppDelegate.stopCollectMode), keyEquivalent: "")
            stopItem.target = appDelegate
            if let stopImage = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stop") {
                stopImage.isTemplate = true
                stopItem.image = stopImage
            }
            clipMenu?.addItem(stopItem)

            if ClipboardQueueService.shared.hasItems {
                let pasteAllItem = NSMenuItem(title: "Paste All (\(ClipboardQueueService.shared.itemCount) items)", action: #selector(AppDelegate.pasteCollectedItems), keyEquivalent: "")
                pasteAllItem.target = appDelegate
                if let pasteImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste All") {
                    pasteImage.isTemplate = true
                    pasteAllItem.image = pasteImage
                }
                clipMenu?.addItem(pasteAllItem)
            }
        } else {
            let startItem = NSMenuItem(title: "Start Collect Mode", action: #selector(AppDelegate.startCollectMode), keyEquivalent: "")
            startItem.target = appDelegate
            if let startImage = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Collect") {
                startImage.isTemplate = true
                startItem.image = startImage
            }
            clipMenu?.addItem(startItem)
        }

        if AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addClearHistoryMenuItem) {
            clipMenu?.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: L10n.clearHistory, action: #selector(AppDelegate.clearAllHistory), keyEquivalent: "")
            clearItem.target = appDelegate
            if let clearImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear") {
                clearImage.isTemplate = true
                clearItem.image = clearImage
            }
            clipMenu?.addItem(clearItem)
        }

        let snippetItem = NSMenuItem(title: L10n.editSnippets, action: #selector(AppDelegate.showSnippetEditorWindow), keyEquivalent: "")
        snippetItem.target = appDelegate
        if let editImage = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Snippets") {
            editImage.isTemplate = true
            snippetItem.image = editImage
        }
        clipMenu?.addItem(snippetItem)

        let prefItem = NSMenuItem(title: L10n.preferences, action: #selector(AppDelegate.showPreferenceWindow), keyEquivalent: ",")
        prefItem.target = appDelegate
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Preferences") {
            gearImage.isTemplate = true
            prefItem.image = gearImage
        }
        clipMenu?.addItem(prefItem)

        clipMenu?.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit \(Constants.Application.name)", action: #selector(AppDelegate.terminate), keyEquivalent: "q")
        quitItem.target = NSApp.delegate
        clipMenu?.addItem(quitItem)

        statusItem?.menu = nil
    }

    func menuItemTitle(_ title: String, listNumber: NSInteger, isMarkWithNumber: Bool) -> String {
        return (isMarkWithNumber) ? "\(listNumber). \(title)" : title
    }

    func applyMenuItemTitle(_ menuItem: NSMenuItem,
                            title: String,
                            listNumber: Int? = nil,
                            isMarkWithNumber: Bool,
                            leadingPrefix: String? = nil) {
        let prefix = leadingPrefix ?? ""
        let resolvedTitle: String
        if let listNumber {
            resolvedTitle = prefix + menuItemTitle(title, listNumber: listNumber, isMarkWithNumber: isMarkWithNumber)
        } else {
            resolvedTitle = prefix + title
        }

        menuItem.title = resolvedTitle

        guard isMarkWithNumber, let listNumber else { return }

        let attributedTitle = NSMutableAttributedString()
        if !prefix.isEmpty {
            attributedTitle.append(NSAttributedString(string: prefix))
        }

        attributedTitle.append(NSAttributedString(
            string: "\(listNumber). ",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        ))
        attributedTitle.append(NSAttributedString(string: title))
        menuItem.attributedTitle = attributedTitle
    }

    func makeSubmenuItem(_ count: Int, start: Int, end: Int, numberOfItems: Int, listNumber: Int? = nil) -> NSMenuItem {
        var count = count
        if start == 0 {
            count -= 1
        }
        var lastNumber = count + numberOfItems
        if end < lastNumber {
            lastNumber = end
        }
        let rangeTitle = "\(count + 1) - \(lastNumber)"
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)
        let keyEquivalent = addNumbericKeyEquivalents ? (listNumber.flatMap(numericKeyEquivalent(forListNumber:)) ?? "") : ""
        let subMenuItem = makeSubmenuItem(rangeTitle, keyEquivalent: keyEquivalent)
        applyMenuItemTitle(subMenuItem,
                           title: rangeTitle,
                           listNumber: listNumber ?? count + 1,
                           isMarkWithNumber: isMarkWithNumber)
        return subMenuItem
    }

    func makeSubmenuItem(_ title: String, keyEquivalent: String = "") -> NSMenuItem {
        let subMenu = NSMenu(title: "")
        subMenu.delegate = self
        let subMenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            subMenuItem.keyEquivalentModifierMask = []
        }
        subMenuItem.submenu = subMenu
        subMenuItem.image = (AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)) ? folderIcon : nil
        return subMenuItem
    }

    func incrementListNumber(_ listNumber: NSInteger, max: NSInteger, start: NSInteger) -> NSInteger {
        var listNumber = listNumber + 1
        if listNumber == max && max == 10 && start == 1 {
            listNumber = 0
        }
        return listNumber
    }

    func trimTitle(_ title: String?) -> String {
        if title == nil { return "" }
        let theString = title!.trimmingCharacters(in: .whitespacesAndNewlines) as NSString

        let aRange = NSRange(location: 0, length: 0)
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        theString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: aRange)

        var titleString = (lineEnd == theString.length) ? theString as String : theString.substring(to: contentsEnd)

        var maxMenuItemTitleLength = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxMenuItemTitleLength)
        if maxMenuItemTitleLength < shortenSymbol.count {
            maxMenuItemTitleLength = shortenSymbol.count
        }

        if titleString.utf16.count > maxMenuItemTitleLength {
            titleString = (titleString as NSString).substring(to: maxMenuItemTitleLength - shortenSymbol.count) + shortenSymbol
        }

        return titleString as String
    }

    func numericKeyEquivalent(forListNumber listNumber: Int) -> String? {
        guard (0..<kMaxKeyEquivalents).contains(listNumber) else { return nil }
        return "\(listNumber)"
    }

}

// MARK: - Clips
private extension MenuManager {
    func addHistoryItems(_ menu: NSMenu) {
        guard let realm = realm else { return }
        let placeInLine = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInline)
        let placeInsideFolder = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.numberOfItemsPlaceInsideFolder)
        let maxHistory = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        // History title
        let labelItem = NSMenuItem(title: L10n.history, action: nil)
        labelItem.isEnabled = false
        if let historyImage = NSImage(systemSymbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90", accessibilityDescription: "History") {
            historyImage.isTemplate = true
            labelItem.image = historyImage
        }
        menu.addItem(labelItem)

        // History
        let firstIndex = firstIndexOfMenuItems()
        var listNumber = firstIndex
        var subMenuCount = placeInLine
        var subMenuIndex = 1 + placeInLine
        var parentListNumber = firstIndex

        let ascending = !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
        // Show pinned items first, then sort by time
        let clipResults = realm.objects(CPYClip.self).sorted(by: [
            SortDescriptor(keyPath: #keyPath(CPYClip.isPinned), ascending: false),
            SortDescriptor(keyPath: #keyPath(CPYClip.updateTime), ascending: ascending)
        ])
        let currentSize = Int(clipResults.count)
        var i = 0
        for clip in clipResults {
            if placeInLine < 1 || placeInLine - 1 < i {
                if i == subMenuCount {
                    let subMenuItem = makeSubmenuItem(subMenuCount,
                                                      start: firstIndex,
                                                      end: currentSize,
                                                      numberOfItems: placeInsideFolder,
                                                      listNumber: parentListNumber)
                    menu.addItem(subMenuItem)
                    listNumber = firstIndex
                    parentListNumber = incrementListNumber(parentListNumber, max: kMaxKeyEquivalents, start: firstIndex)
                }

                if let subMenu = menu.item(at: subMenuIndex)?.submenu {
                    let menuItem = makeClipMenuItem(clip, listNumber: listNumber)
                    subMenu.addItem(menuItem)
                    listNumber = incrementListNumber(listNumber, max: placeInsideFolder, start: firstIndex)
                }
            } else {
                let menuItem = makeClipMenuItem(clip, listNumber: listNumber)
                menu.addItem(menuItem)
                listNumber = incrementListNumber(listNumber, max: placeInLine, start: firstIndex)
            }

            i += 1
            if i == subMenuCount + placeInsideFolder {
                subMenuCount += placeInsideFolder
                subMenuIndex += 1
            }

            if maxHistory <= i { break }
        }
    }

    func makeClipMenuItem(_ clip: CPYClip, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowToolTip = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showToolTipOnMenuItem)
        let isShowImage = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showImageInTheMenu)
        let isShowColorCode = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showColorPreviewInTheMenu)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        var keyEquivalent = ""

        if addNumbericKeyEquivalents, let numericKeyEquivalent = numericKeyEquivalent(forListNumber: listNumber) {
            keyEquivalent = numericKeyEquivalent
        }

        let primaryPboardType = NSPasteboard.PasteboardType(rawValue: clip.primaryType)
        let clipString = clip.title
        let title = trimTitle(clipString)
        var displayTitle = title

        let menuItem = NSMenuItem(title: title, action: #selector(MenuManager.selectClipMenuItem(_:)), keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            menuItem.keyEquivalentModifierMask = []
        }
        menuItem.target = self
        menuItem.representedObject = clip.dataHash

        if isShowToolTip {
            let maxLengthOfToolTip = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxLengthOfToolTip)
            let toIndex = (clipString.count < maxLengthOfToolTip) ? clipString.count : maxLengthOfToolTip
            menuItem.toolTip = (clipString as NSString).substring(to: toIndex)
        }

        // Type-specific icons and titles using SF Symbols
        if primaryPboardType.isTIFFType() {
            displayTitle = "(Image)"
            if menuItem.image == nil, let img = NSImage(systemSymbolName: "photo", accessibilityDescription: "Image") {
                img.isTemplate = true
                menuItem.image = img
            }
        } else if primaryPboardType.isPDFType() {
            displayTitle = "(PDF)"
            if menuItem.image == nil, let img = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "PDF") {
                img.isTemplate = true
                menuItem.image = img
            }
        } else if primaryPboardType.isFilenamesType() && title.isEmpty {
            displayTitle = "(Filenames)"
            if menuItem.image == nil, let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Files") {
                img.isTemplate = true
                menuItem.image = img
            }
        } else if primaryPboardType.isURLType() {
            if menuItem.image == nil, let img = NSImage(systemSymbolName: "link", accessibilityDescription: "URL") {
                img.isTemplate = true
                menuItem.image = img
            }
        }

        if !clip.thumbnailPath.isEmpty && !clip.isColorCode && isShowImage {
            if let cached = ClipService.cachedThumbnail(forKey: clip.thumbnailPath) {
                menuItem.image = cached
            }
        }
        if !clip.thumbnailPath.isEmpty && clip.isColorCode && isShowColorCode {
            if let cached = ClipService.cachedThumbnail(forKey: clip.thumbnailPath) {
                menuItem.image = cached
            }
        }

        applyMenuItemTitle(menuItem,
                           title: displayTitle,
                           listNumber: listNumber,
                           isMarkWithNumber: isMarkWithNumber,
                           leadingPrefix: clip.isPinned ? "\u{1F4CC} " : nil)

        return menuItem
    }
}

// MARK: - Snippets
private extension MenuManager {
    @MainActor
    func addSnippetItems(_ menu: NSMenu, separateMenu: Bool) {
        guard let realm = realm else { return }
        let folderResults = realm.objects(CPYFolder.self).sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        guard !folderResults.isEmpty else { return }
        if separateMenu {
            menu.addItem(NSMenuItem.separator())
        }

        let labelItem = NSMenuItem(title: L10n.snippet, action: nil)
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        let firstIndex = firstIndexOfMenuItems()
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)
        var folderListNumber = firstIndex

        folderResults
            .filter { $0.enable }
            .forEach { folder in
                let folderTitle = folder.title
                let keyEquivalent = addNumbericKeyEquivalents ? (numericKeyEquivalent(forListNumber: folderListNumber) ?? "") : ""

                if folder.isVault && !isVaultUnlocked(folder.identifier) {
                    let vaultItem = NSMenuItem(title: folderTitle, action: #selector(AppDelegate.unlockVaultFolder(_:)), keyEquivalent: keyEquivalent)
                    vaultItem.target = appDelegate
                    vaultItem.representedObject = folder.identifier
                    if !keyEquivalent.isEmpty {
                        vaultItem.keyEquivalentModifierMask = []
                    }
                    applyMenuItemTitle(vaultItem,
                                       title: folderTitle,
                                       listNumber: folderListNumber,
                                       isMarkWithNumber: isMarkWithNumber)
                    if let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked Vault") {
                        lockImage.isTemplate = true
                        vaultItem.image = lockImage
                    }
                    menu.addItem(vaultItem)
                } else {
                    let folderItem = makeSubmenuItem(folderTitle, keyEquivalent: keyEquivalent)
                    applyMenuItemTitle(folderItem,
                                       title: folderTitle,
                                       listNumber: folderListNumber,
                                       isMarkWithNumber: isMarkWithNumber)
                    menu.addItem(folderItem)

                    var i = firstIndex
                    folder.snippets
                        .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
                        .filter { $0.enable }
                        .forEach { snippet in
                            let subMenuItem = makeSnippetMenuItem(snippet, listNumber: i)
                            if let subMenu = folderItem.submenu {
                                subMenu.addItem(subMenuItem)
                                i += 1
                            }
                        }
                }

                folderListNumber = incrementListNumber(folderListNumber, max: kMaxKeyEquivalents, start: firstIndex)
            }
    }

    func makeSnippetMenuItem(_ snippet: CPYSnippet, listNumber: Int) -> NSMenuItem {
        let isMarkWithNumber = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsAreMarkedWithNumbers)
        let isShowIcon = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showIconInTheMenu)
        let addNumbericKeyEquivalents = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.addNumericKeyEquivalents)

        let title = trimTitle(snippet.title)
        let keyEquivalent = addNumbericKeyEquivalents ? (numericKeyEquivalent(forListNumber: listNumber) ?? "") : ""

        let menuItem = NSMenuItem(title: title, action: #selector(MenuManager.selectSnippetMenuItem(_:)), keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            menuItem.keyEquivalentModifierMask = []
        }
        menuItem.target = self
        menuItem.representedObject = snippet.identifier
        menuItem.toolTip = snippet.content
        menuItem.image = (isShowIcon) ? snippetIcon : nil
        applyMenuItemTitle(menuItem,
                           title: title,
                           listNumber: listNumber,
                           isMarkWithNumber: isMarkWithNumber)

        return menuItem
    }
}

// MARK: - Status Item
private extension MenuManager {
    func changeStatusItem(_ type: StatusType) {
        removeStatusItem()
        if type == .none { return }

        #if DEBUG
        statusItem = NSStatusBar.system.statusItem(withLength: 44)
        if let button = statusItem?.button {
            let image: NSImage?
            switch type {
            case .black:
                image = Asset.statusbarMenuBlack.image
            case .white:
                image = Asset.statusbarMenuWhite.image
            case .none: return
            }
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            // Add orange "DEV" badge
            let devLabel = NSTextField(labelWithString: "DEV")
            devLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
            devLabel.textColor = .orange
            devLabel.sizeToFit()
            devLabel.frame.origin = CGPoint(x: 20, y: 2)
            button.addSubview(devLabel)
            button.toolTip = "\(Constants.Application.name) \(Bundle.main.appVersion) (Debug Build)"
            button.target = self
            button.action = #selector(MenuManager.popUpStatusItemMenu(_:))
        }
        #else
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image: NSImage?
            switch type {
            case .black:
                image = Asset.statusbarMenuBlack.image
            case .white:
                image = Asset.statusbarMenuWhite.image
            case .none: return
            }
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(Constants.Application.name) \(Bundle.main.appVersion)"
            button.target = self
            button.action = #selector(MenuManager.popUpStatusItemMenu(_:))
        }
        #endif
        statusItem?.menu = nil
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - Settings
private extension MenuManager {
    func firstIndexOfMenuItems() -> NSInteger {
        return AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.menuItemsTitleStartWithZero) ? 0 : 1
    }
}

// MARK: - UserDefaults KVO Bridge
private extension UserDefaults {
    @objc var clipyShowStatusItem: Any? {
        return object(forKey: Constants.UserDefaults.showStatusItem)
    }
    @objc var clipyReorderClips: Bool {
        return bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting)
    }
}
