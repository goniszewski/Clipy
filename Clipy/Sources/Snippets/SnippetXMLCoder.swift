//
//  SnippetXMLCoder.swift
//
//  Clipy
//

import AEXML
import Foundation

enum SnippetXMLCoder {
    static func xmlDocument<Folders: Sequence>(
        from folders: Folders,
        includeVaultFolders: Bool = true
    ) -> AEXMLDocument where Folders.Element == CPYFolder {
        let xmlDocument = AEXMLDocument()
        let rootElement = xmlDocument.addChild(name: Constants.Xml.rootElement)

        folders.forEach { folder in
            guard includeVaultFolders || !folder.isVault else { return }

            let folderElement = rootElement.addChild(name: Constants.Xml.folderElement)
            folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

            let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
            sortedSnippets(in: folder).forEach { snippet in
                addSnippet(snippet, to: snippetsElement)
            }
        }

        return xmlDocument
    }

    static func importFolders(from data: Data, startingAt startingFolderIndex: Int) throws -> [CPYFolder] {
        var options = AEXMLOptions()
        options.parserSettings.shouldTrimWhitespace = false
        let xmlDocument = try AEXMLDocument(xml: data, options: options)

        var folderIndex = startingFolderIndex
        return xmlDocument[Constants.Xml.rootElement].children.map { folderElement in
            let folder = CPYFolder()
            folder.title = folderElement[Constants.Xml.titleElement].value ?? "untitled folder"
            folder.index = folderIndex

            folderElement[Constants.Xml.snippetsElement][Constants.Xml.snippetElement]
                .all?
                .enumerated()
                .forEach { snippetIndex, snippetElement in
                    folder.snippets.append(snippet(from: snippetElement, index: snippetIndex))
                }

            folderIndex += 1
            return folder
        }
    }

    private static func addSnippet(_ snippet: CPYSnippet, to snippetsElement: AEXMLElement) {
        let snippetElement = snippetsElement.addChild(name: Constants.Xml.snippetElement)
        snippetElement.addChild(name: Constants.Xml.titleElement, value: snippet.title)
        snippetElement.addChild(name: Constants.Xml.contentElement, value: snippet.content)
        snippetElement.addChild(name: Constants.Xml.snippetTypeElement, value: String(snippet.type.rawValue))
        snippetElement.addChild(name: Constants.Xml.scriptShellElement, value: snippet.scriptShell)
        snippetElement.addChild(name: Constants.Xml.scriptTimeoutElement, value: String(snippet.scriptTimeout))
        snippetElement.addChild(name: Constants.Xml.isEphemeralElement, value: String(snippet.isEphemeral))
    }

    private static func snippet(from snippetElement: AEXMLElement, index: Int) -> CPYSnippet {
        let snippet = CPYSnippet()
        snippet.title = snippetElement[Constants.Xml.titleElement].value ?? "untitled snippet"
        snippet.content = snippetElement[Constants.Xml.contentElement].value ?? ""
        snippet.index = index
        snippet.type = snippetType(from: snippetElement[Constants.Xml.snippetTypeElement].value)

        let scriptConfig = ScriptSnippetConfig(
            shell: snippetElement[Constants.Xml.scriptShellElement].value ?? CPYSnippet.defaultScriptShell,
            timeoutSeconds: intValue(snippetElement[Constants.Xml.scriptTimeoutElement].value) ?? CPYSnippet.defaultScriptTimeout,
            isEphemeral: boolValue(snippetElement[Constants.Xml.isEphemeralElement].value) ?? true
        )
        snippet.scriptShell = scriptConfig.shell
        snippet.scriptTimeout = scriptConfig.timeoutSeconds
        snippet.isEphemeral = scriptConfig.isEphemeral

        return snippet
    }

    private static func sortedSnippets(in folder: CPYFolder) -> [CPYSnippet] {
        folder.snippets.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.index == rhs.element.index {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.index < rhs.element.index
            }
            .map(\.element)
    }

    private static func snippetType(from value: String?) -> CPYSnippet.SnippetType {
        guard let value = intValue(value), let type = CPYSnippet.SnippetType(rawValue: value) else {
            return .plainText
        }
        return type
    }

    private static func intValue(_ value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Int(value)
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }

        switch value {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}
