//
//  NSCoding+Archive.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.clipy-app.Clipy", category: "Archive")

enum ArchiveCompatibility {
    static func archivedData(withRootObject object: Any) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
        } catch {
            logger.error("Failed to archive object: \(error.localizedDescription)")
            return nil
        }
    }

    static func archiveRootObject(_ object: Any, toFile path: String) -> Bool {
        guard let data = archivedData(withRootObject: object) else { return false }

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            logger.error("Failed to write archive to \(path): \(error.localizedDescription)")
            return false
        }
    }

    static func unarchiveObject<T>(with data: Data) -> T? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            defer { unarchiver.finishDecoding() }
            return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? T
        } catch {
            logger.error("Failed to unarchive object: \(error.localizedDescription)")
            return nil
        }
    }

    static func unarchiveObject<T>(withFile path: String) -> T? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return unarchiveObject(with: data)
        } catch {
            logger.error("Failed to read archive from \(path): \(error.localizedDescription)")
            return nil
        }
    }
}

extension NSCoding {
    func archive() -> Data {
        return ArchiveCompatibility.archivedData(withRootObject: self) ?? Data()
    }
}

extension Array where Element: NSCoding {
    func archive() -> Data {
        return ArchiveCompatibility.archivedData(withRootObject: self) ?? Data()
    }
}
