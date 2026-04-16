//
//  AccessibilityService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//
//  Created by Econa77 on 2018/10/03.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import os.log

private let logger = Logger(subsystem: "com.clipy-app.Clipy", category: "Accessibility")

final class AccessibilityService {
    private var hasShownAlertThisSession = false
}

// MARK: - Permission
extension AccessibilityService {
    @discardableResult
    func isAccessibilityEnabled(isPrompt: Bool) -> Bool {
        if #available(macOS 10.15, *) {
            let hasPostEventAccess = isPrompt ? CGRequestPostEventAccess() : CGPreflightPostEventAccess()
            if hasPostEventAccess {
                return true
            }
        }

        let checkOptionPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [checkOptionPromptKey: isPrompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func showAccessibilityAuthenticationAlert() {
        // Only show once per session to avoid alert loops
        guard !hasShownAlertThisSession else {
            logger.warning("Accessibility not granted — alert already shown this session")
            return
        }
        hasShownAlertThisSession = true

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        #if DEBUG
        alert.informativeText = "\(Constants.Application.name) needs Accessibility access to paste clipboard items. Please add \(Constants.Application.name) in System Settings → Privacy & Security → Accessibility.\n\nNote: This is a debug build — the release version uses a separate entry named \(Constants.Application.releaseName)."
        #else
        alert.informativeText = "\(Constants.Application.name) needs Accessibility access to paste clipboard items. Please add \(Constants.Application.name) in System Settings → Privacy & Security → Accessibility."
        #endif
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            openAccessibilitySettingWindow()
        }
    }

    @discardableResult
    func openAccessibilitySettingWindow() -> Bool {
        // Modern macOS System Settings URL
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
