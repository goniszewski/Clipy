//
//  NSBundle+Version.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/03/29.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Unknown"
    }

    var appBuildVersion: String? {
        (infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    var appDisplayVersion: String {
        guard let build = appBuildVersion, build != appVersion else { return appVersion }
        return "\(appVersion) (\(build))"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
