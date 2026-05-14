import Quick
import Nimble
@testable import Clipy

class SnippetXMLCoderSpec: QuickSpec {
    override class func spec() {
        describeXMLExport()
        describeXMLImport()
        describeXMLRoundTrip()
    }

    private class func describeXMLExport() {
        describe("Snippet XML export") {

            it("exports script snippet fields with shared XML element names") {
                let folder = CPYFolder()
                folder.title = "Scripts"
                let snippet = CPYSnippet()
                snippet.title = "Format JSON"
                snippet.content = "python -m json.tool"
                snippet.type = .script
                snippet.scriptShell = "/bin/zsh"
                snippet.scriptTimeout = 7
                snippet.isEphemeral = false
                folder.snippets.append(snippet)

                let xml = SnippetXMLCoder.xmlDocument(from: [folder]).xml

                expect(xml).to(contain("<\(Constants.Xml.snippetTypeElement)>1</\(Constants.Xml.snippetTypeElement)>"))
                expect(xml).to(contain("<\(Constants.Xml.scriptShellElement)>/bin/zsh</\(Constants.Xml.scriptShellElement)>"))
                expect(xml).to(contain("<\(Constants.Xml.scriptTimeoutElement)>7</\(Constants.Xml.scriptTimeoutElement)>"))
                expect(xml).to(contain("<\(Constants.Xml.isEphemeralElement)>false</\(Constants.Xml.isEphemeralElement)>"))
            }

            it("can skip vault folders during export") {
                let publicFolder = CPYFolder()
                publicFolder.title = "Public"
                let publicSnippet = CPYSnippet()
                publicSnippet.title = "Visible"
                publicFolder.snippets.append(publicSnippet)

                let vaultFolder = CPYFolder()
                vaultFolder.title = "Vault"
                vaultFolder.isVault = true
                let vaultSnippet = CPYSnippet()
                vaultSnippet.title = "Secret"
                vaultFolder.snippets.append(vaultSnippet)

                let xml = SnippetXMLCoder.xmlDocument(
                    from: [publicFolder, vaultFolder],
                    includeVaultFolders: false
                ).xml

                expect(xml).to(contain("<title>Public</title>"))
                expect(xml).toNot(contain("<title>Vault</title>"))
                expect(xml).toNot(contain("<title>Secret</title>"))
            }
        }
    }

    private class func describeXMLImport() {
        describe("Snippet XML import") {

            it("imports script snippet fields and defaults legacy snippets") {
                let xml = """
                <folders>
                  <folder>
                    <title>Imported</title>
                    <snippets>
                      <snippet>
                        <title>Script</title>
                        <content>printf hello</content>
                        <snippetType>1</snippetType>
                        <scriptShell>/bin/zsh</scriptShell>
                        <scriptTimeout>8</scriptTimeout>
                        <isEphemeral>false</isEphemeral>
                      </snippet>
                      <snippet>
                        <title>Legacy</title>
                        <content>plain body</content>
                      </snippet>
                    </snippets>
                  </folder>
                </folders>
                """

                let folders = try! SnippetXMLCoder.importFolders(from: Data(xml.utf8), startingAt: 3)

                expect(folders.count) == 1
                expect(folders.first?.index) == 3
                expect(folders.first?.snippets.count) == 2

                let script = folders[0].snippets[0]
                expect(script.index) == 0
                expect(script.title) == "Script"
                expect(script.content) == "printf hello"
                expect(script.type) == .script
                expect(script.scriptShell) == "/bin/zsh"
                expect(script.scriptTimeout) == 8
                expect(script.isEphemeral) == false

                let legacy = folders[0].snippets[1]
                expect(legacy.index) == 1
                expect(legacy.type) == .plainText
                expect(legacy.scriptShell) == CPYSnippet.defaultScriptShell
                expect(legacy.scriptTimeout) == CPYSnippet.defaultScriptTimeout
                expect(legacy.isEphemeral) == true
            }

            it("normalizes invalid imported script settings") {
                let xml = """
                <folders>
                  <folder>
                    <title>Imported</title>
                    <snippets>
                      <snippet>
                        <title>Script</title>
                        <content>printf hello</content>
                        <snippetType>1</snippetType>
                        <scriptShell>   </scriptShell>
                        <scriptTimeout>999</scriptTimeout>
                        <isEphemeral>maybe</isEphemeral>
                      </snippet>
                    </snippets>
                  </folder>
                </folders>
                """

                let snippet = try! SnippetXMLCoder.importFolders(from: Data(xml.utf8), startingAt: 0)[0].snippets[0]

                expect(snippet.type) == .script
                expect(snippet.scriptShell) == CPYSnippet.defaultScriptShell
                expect(snippet.scriptTimeout) == CPYSnippet.defaultScriptTimeout
                expect(snippet.isEphemeral) == true
            }
        }
    }

    private class func describeXMLRoundTrip() {
        describe("Snippet XML round-trip") {

            it("round-trips escaped characters and preserves text whitespace") {
                let folder = CPYFolder()
                folder.title = " Tools & <Scripts> "
                let snippet = CPYSnippet()
                snippet.title = "Echo <hello> & \"quotes\""
                snippet.content = "  line 1\nline <2> & '3'\n  "
                snippet.type = .script
                snippet.scriptShell = "/bin/sh"
                snippet.scriptTimeout = 4
                snippet.isEphemeral = true
                folder.snippets.append(snippet)

                let xml = SnippetXMLCoder.xmlDocument(from: [folder]).xml
                let imported = try! SnippetXMLCoder.importFolders(from: Data(xml.utf8), startingAt: 0)
                let importedSnippet = imported[0].snippets[0]

                expect(imported[0].title) == folder.title
                expect(importedSnippet.title) == snippet.title
                expect(importedSnippet.content) == snippet.content
                expect(importedSnippet.type) == .script
                expect(importedSnippet.scriptShell) == "/bin/sh"
                expect(importedSnippet.scriptTimeout) == 4
                expect(importedSnippet.isEphemeral) == true
            }
        }
    }
}
