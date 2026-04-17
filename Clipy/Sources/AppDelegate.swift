//
//  AppDelegate.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import Combine
import RealmSwift
import TipKit
import Magnet
import ServiceManagement
import Security
import Sparkle
import os.log

private let logger = Logger(subsystem: "com.clipy-app.Clipy", category: "App")

private enum UpdaterAvailability {
    case available(teamIdentifier: String)
    case unavailable(reason: String)
}

private enum ManualReleaseState {
    case idle
    case updateAvailable(version: String, url: URL)
    case upToDate(version: String, url: URL)
    case failed(message: String)
}

private struct GitHubRelease: Decodable {
    let htmlURL: URL
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
        case tagName = "tag_name"
    }

    var version: String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
    }
}

private enum CodeSigningInspector {
    static func teamIdentifier(for bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )

        guard infoStatus == errSecSuccess,
              let signingInformation = signingInformation as? [String: Any] else {
            return nil
        }

        return signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

final class SparkleUpdaterDriver: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdaterDriver()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var feedURL = Constants.Application.appcastURL
    @Published private(set) var availabilityReason: String?
    @Published private var manualReleaseState: ManualReleaseState = .idle

    private let updaterAvailability = SparkleUpdaterDriver.resolveUpdaterAvailability()
    private let installedVersion = Bundle.main.appVersion
    private var manualReleaseCheckTask: Task<Void, Never>?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
        if case .available = updaterAvailability {
            migrateLegacyFeedURLIfNeeded()
        } else if case let .unavailable(reason) = updaterAvailability {
            logger.info("Sparkle disabled for this build: \(reason, privacy: .public)")
        }
        refreshState()
    }

    private func migrateLegacyFeedURLIfNeeded() {
        if let previousFeedURL = updaterController.updater.clearFeedURLFromUserDefaults(),
           previousFeedURL != Constants.Application.appcastURL {
            logger.info("Cleared legacy Sparkle feed URL override: \(previousFeedURL.absoluteString, privacy: .public)")
        }
    }

    func refreshState() {
        switch updaterAvailability {
        case .available:
            availabilityReason = nil
            canCheckForUpdates = updaterController.updater.canCheckForUpdates
            isCheckingForUpdates = updaterController.updater.sessionInProgress
            automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
            automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
            feedURL = updaterController.updater.feedURL ?? Constants.Application.appcastURL

        case let .unavailable(reason):
            availabilityReason = reason
            canCheckForUpdates = false
            isCheckingForUpdates = false
            automaticallyChecksForUpdates = false
            automaticallyDownloadsUpdates = false
            feedURL = Constants.Application.appcastURL
        }
    }

    func checkForUpdates() {
        switch updaterAvailability {
        case .available:
            updaterController.checkForUpdates(nil)
            refreshState()

        case .unavailable:
            checkGitHubRelease()
        }
    }

    func openLatestReleasePage() {
        switch manualReleaseState {
        case let .updateAvailable(_, url), let .upToDate(_, url):
            NSWorkspace.shared.open(url)

        case .idle, .failed:
            NSWorkspace.shared.open(Constants.Application.releasesURL)
        }
    }

    var usesSparkle: Bool {
        if case .available = updaterAvailability {
            return true
        }
        return false
    }

    var canTriggerUpdateCheck: Bool {
        usesSparkle ? canCheckForUpdates : !isCheckingForUpdates
    }

    var latestReleaseVersion: String? {
        switch manualReleaseState {
        case let .updateAvailable(version, _), let .upToDate(version, _):
            return version

        case .idle, .failed:
            return nil
        }
    }

    var isManualUpdateAvailable: Bool {
        if case .updateAvailable = manualReleaseState {
            return true
        }
        return false
    }

    var didManualReleaseCheckFail: Bool {
        if case .failed = manualReleaseState {
            return true
        }
        return false
    }

    var manualReleaseFailureMessage: String? {
        if case let .failed(message) = manualReleaseState {
            return message
        }
        return nil
    }

    var manualReleaseStatusText: String {
        switch manualReleaseState {
        case .idle:
            return "Not checked"

        case let .updateAvailable(version, _):
            return "Version \(version) available"

        case let .upToDate(version, _):
            return "Up to date (\(version))"

        case let .failed(message):
            return message
        }
    }

    private func checkGitHubRelease() {
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        manualReleaseState = .idle
        manualReleaseCheckTask?.cancel()
        manualReleaseCheckTask = Task { [weak self] in
            guard let self else { return }

            do {
                let release = try await Self.fetchLatestGitHubRelease()
                guard !Task.isCancelled else { return }

                DispatchQueue.main.async {
                    self.isCheckingForUpdates = false

                    if release.version.isVersion(newerThan: self.installedVersion) {
                        self.manualReleaseState = .updateAvailable(version: release.version, url: release.htmlURL)
                    } else {
                        self.manualReleaseState = .upToDate(version: release.version, url: release.htmlURL)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.isCheckingForUpdates = false
                    self.manualReleaseState = .failed(message: message)
                }
            }
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        refreshState()
    }

    private static func fetchLatestGitHubRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Constants.Application.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Clipy/\(Bundle.main.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorBadServerResponse,
                userInfo: [NSLocalizedDescriptionKey: "GitHub did not return a valid release response."]
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let statusError = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NSError(
                domain: NSURLErrorDomain,
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub release lookup failed: \(statusError)."]
            )
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private static func resolveUpdaterAvailability() -> UpdaterAvailability {
        #if DEBUG
            return .unavailable(reason: "Debug builds use local signing and do not publish Sparkle updates.")
        #else
            guard let teamIdentifier = CodeSigningInspector.teamIdentifier(for: Bundle.main.bundleURL) else {
                return .unavailable(reason: "This build is not Developer ID-signed, so automatic updates are unavailable.")
            }

            return .available(teamIdentifier: teamIdentifier)
        #endif
    }
}

private extension String {
    func isVersion(newerThan otherVersion: String) -> Bool {
        compare(otherVersion, options: .numeric) == .orderedDescending
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSMenuItemValidation {

    // MARK: - Properties
    private var cancellables = Set<AnyCancellable>()
    private let updaterDriver = SparkleUpdaterDriver.shared

    // MARK: - Init
    override func awakeFromNib() {
        super.awakeFromNib()
        Realm.migration()
    }

    // MARK: - NSMenuItem Validation
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(AppDelegate.clearAllHistory) {
            guard let realm = Realm.safeInstance() else { return false }
            return !realm.objects(CPYClip.self).isEmpty
        }
        if menuItem.action == #selector(AppDelegate.checkForUpdates(_:)) {
            return updaterDriver.canTriggerUpdateCheck && !updaterDriver.isCheckingForUpdates
        }
        return true
    }

    // MARK: - Class Methods
    static func storeTypesDictinary() -> [String: NSNumber] {
        var storeTypes = [String: NSNumber]()
        CPYClipData.availableTypesString.forEach { storeTypes[$0] = NSNumber(value: true) }
        return storeTypes
    }

    // MARK: - Menu Actions
    @objc func showPreferenceWindow() {
        ModernPreferencesWindowController.shared.showWindow(self)
    }

    @objc func showSnippetEditorWindow() {
        ModernSnippetsWindowController.shared.showWindow(self)
    }

    @objc func showSearchPanel() {
        ClipSearchWindowController.shared.show()
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let credits = NSAttributedString(
            string: Constants.Application.aboutLineage,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraphStyle
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Constants.Application.name,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc func unlockVaultFolder(_ sender: NSMenuItem) {
        guard let folderID = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance(),
              let folder = realm.object(ofType: CPYFolder.self, forPrimaryKey: folderID) else {
            NSSound.beep()
            return
        }

        VaultAuthService.shared.authenticate(folderID: folder.identifier, reason: "Unlock \"\(folder.title)\" vault") { success in
            DispatchQueue.main.async {
                guard success else { return }
                AppEnvironment.current.menuManager.refresh()
                AppEnvironment.current.menuManager.popUpSnippetFolder(folder)
            }
        }
    }

    @objc func pasteAsPlainText() {
        let pasteboard = NSPasteboard.general
        guard let string = pasteboard.string(forType: .string) else { return }
        // Re-set as plain text only, stripping all formatting
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        AppEnvironment.current.pasteService.paste()
    }

    @objc func startCollectMode() {
        ClipboardQueueService.shared.startCollecting()
    }

    @objc func stopCollectMode() {
        ClipboardQueueService.shared.stopCollecting()
    }

    @objc func pasteCollectedItems() {
        ClipboardQueueService.shared.pasteMerged()
    }

    @objc func terminate() {
        terminateApplication()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterDriver.checkForUpdates()
    }

    @objc func clearAllHistory() {
        let isShowAlert = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
        if isShowAlert {
            let alert = NSAlert()
            alert.messageText = L10n.clearHistory
            alert.informativeText = L10n.areYouSureYouWantToClearYourClipboardHistory
            alert.addButton(withTitle: L10n.clearHistory)
            alert.addButton(withTitle: L10n.cancel)
            alert.showsSuppressionButton = true

            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result != NSApplication.ModalResponse.alertFirstButtonReturn { return }

            if alert.suppressionButton?.state == NSControl.StateValue.on {
                AppEnvironment.current.defaults.set(false, forKey: Constants.UserDefaults.showAlertBeforeClearHistory)
            }
        }

        AppEnvironment.current.clipService.clearAll()
    }

    @objc func selectClipMenuItem(_ sender: NSMenuItem) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance() else {
            NSSound.beep()
            return
        }
        guard let clip = realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }

        AppEnvironment.current.pasteService.paste(with: clip)
    }

    @objc func selectSnippetMenuItem(_ sender: AnyObject) {
        guard let primaryKey = sender.representedObject as? String else {
            NSSound.beep()
            return
        }
        guard let realm = Realm.safeInstance() else {
            NSSound.beep()
            return
        }
        guard let snippet = realm.object(ofType: CPYSnippet.self, forPrimaryKey: primaryKey) else {
            NSSound.beep()
            return
        }
        let processed = SnippetVariableProcessor.process(snippet.content)
        AppEnvironment.current.pasteService.copyToPasteboard(with: processed)
        AppEnvironment.current.pasteService.paste()
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Login Item Methods
    private func promptToAddLoginItems() {
        let alert = NSAlert()
        alert.messageText = "Launch \(Constants.Application.name) on system startup?"
        alert.informativeText = L10n.youCanChangeThisSettingInThePreferencesIfYouWant
        alert.addButton(withTitle: L10n.launchOnSystemStartup)
        alert.addButton(withTitle: L10n.donTLaunch)
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.loginItem)
            reflectLoginItemState()
        }
        if alert.suppressionButton?.state == NSControl.StateValue.on {
            AppEnvironment.current.defaults.set(true, forKey: Constants.UserDefaults.suppressAlertForLoginItem)
        }
    }

    private func toggleAddingToLoginItems(_ isEnable: Bool) {
        do {
            if isEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription)")
        }
    }

    private func reflectLoginItemState() {
        let isInLoginItems = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem)
        toggleAddingToLoginItems(isInLoginItems)
    }
}

// MARK: - NSApplication Delegate
extension AppDelegate: NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Environments
        AppEnvironment.replaceCurrent(environment: AppEnvironment.fromStorage())
        // UserDefaults
        CPYUtilities.registerUserDefaultKeys()
        // Don't prompt on launch. If accessibility is missing, we prompt on the first
        // paste attempt so users aren't nagged every time the app starts.
        _ = AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false)

        // Show Login Item
        if !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.loginItem) && !AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.suppressAlertForLoginItem) {
            promptToAddLoginItems()
        }

        // Binding Events
        bind()

        // Services
        AppEnvironment.current.clipService.startMonitoring()
        AppEnvironment.current.dataCleanService.startMonitoring()
        AppEnvironment.current.excludeAppService.startMonitoring()
        AppEnvironment.current.hotKeyService.setupDefaultHotKeys()

        // Managers
        AppEnvironment.current.menuManager.setup()
        updaterDriver.refreshState()

        // Initialize collect mode indicator (observes queue state)
        _ = CollectModeIndicatorController.shared

        // TipKit onboarding — show max one tip per week to avoid overwhelming new users
        try? Tips.configure([.displayFrequency(.weekly)])

        #if DEBUG
        logger.info("\(Constants.Application.name) (debug build) launched")
        #else
        logger.info("\(Constants.Application.name) launched successfully")
        #endif
    }

}

// MARK: - Bind
private extension AppDelegate {
    func bind() {
        // Login Item
        AppEnvironment.current.defaults
            .publisher(for: \.clipyLoginItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reflectLoginItemState()
            }
            .store(in: &cancellables)
    }
}

// MARK: - UserDefaults KVO Bridge
private extension UserDefaults {
    @objc var clipyLoginItem: Bool {
        return bool(forKey: Constants.UserDefaults.loginItem)
    }
}
