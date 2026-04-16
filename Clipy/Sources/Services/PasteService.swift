//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Sauce

final class PasteService {

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.Pastable")
    fileprivate var isPastePlainText: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pastePlainText) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pastePlainTextModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.deleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.deleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }
    fileprivate var isPasteAndDeleteHistory: Bool {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.Beta.pasteAndDeleteHistory) else { return false }

        let modifierSetting = AppEnvironment.current.defaults.integer(forKey: Constants.Beta.pasteAndDeleteHistoryModifier)
        return isPressedModifier(modifierSetting)
    }

    // MARK: - Modifiers
    private func isPressedModifier(_ flag: Int) -> Bool {
        let flags = NSEvent.modifierFlags
        if flag == 0 && flags.contains(.command) {
            return true
        } else if flag == 1 && flags.contains(.shift) {
            return true
        } else if flag == 2 && flags.contains(.control) {
            return true
        } else if flag == 3 && flags.contains(.option) {
            return true
        }
        return false
    }
}

// MARK: - Copy
extension PasteService {
    func paste(with clip: CPYClip) {
        guard !clip.isInvalidated else { return }
        guard let data: CPYClipData = ArchiveCompatibility.unarchiveObject(withFile: clip.dataPath) else { return }

        let isPastePlainText = self.isPastePlainText
        let isPasteAndDeleteHistory = self.isPasteAndDeleteHistory
        let isDeleteHistory = self.isDeleteHistory
        guard isPastePlainText || isPasteAndDeleteHistory || isDeleteHistory else {
            // We are writing a known history item back to the pasteboard intentionally.
            // Skip re-capturing that change and reorder history explicitly instead.
            AppEnvironment.current.clipService.incrementChangeCount()
            AppEnvironment.current.clipService.markPasted(clip)
            copyToPasteboard(with: clip)
            paste()
            return
        }

        if isPastePlainText {
            AppEnvironment.current.clipService.incrementChangeCount()
            AppEnvironment.current.clipService.markPasted(clip)
            copyToPasteboard(with: data.stringValue)
            paste()
        } else if isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.incrementChangeCount()
            copyToPasteboard(with: clip)
            paste()
        }
        if isDeleteHistory || isPasteAndDeleteHistory {
            AppEnvironment.current.clipService.delete(with: clip)
        }
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.clipyString], owner: nil)
        pasteboard.setString(string, forType: .clipyString)
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data: CPYClipData = ArchiveCompatibility.unarchiveObject(withFile: clip.dataPath) else { return }

        if isPastePlainText {
            copyToPasteboard(with: data.stringValue)
            return
        }

        let pasteboard = NSPasteboard.general
        let types = Array(NSOrderedSet(array: data.types.map(\.normalized)).array as? [NSPasteboard.PasteboardType] ?? data.types)

        if types.contains(where: { $0.isTIFFType() }), let image = data.image {
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([image])

            // Keep TIFF data available explicitly for apps that still read the raw type.
            if let imageData = image.tiffRepresentation {
                pasteboard.setData(imageData, forType: .clipyTIFF)
            }
            return
        }

        pasteboard.declareTypes(types, owner: nil)
        types.forEach { type in
            if type.isStringType() {
                pasteboard.setString(data.stringValue, forType: type)
            } else if type.isRTFDType() {
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: type)
            } else if type.isRTFType() {
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: type)
            } else if type.isPDFType() {
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: type)
            } else if type.isFilenamesType() {
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: type)
            } else if type.isURLType() {
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: type)
            }
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) else { return }

        guard AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            return
        }

        postPasteShortcut()
    }

    private func postPasteShortcut() {
        let vKeyCode = Sauce.shared.keyCode(by: .v)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyVDown?.flags = .maskCommand
            let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyVUp?.flags = .maskCommand
            keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
