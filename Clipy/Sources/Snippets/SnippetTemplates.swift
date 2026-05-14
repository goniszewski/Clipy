//
//  SnippetTemplates.swift
//
//  Clipy
//

import Foundation

struct SnippetTemplate: Identifiable, Hashable {
    private let identifier: String
    let name: String
    let summary: String
    let category: String
    let systemImageName: String
    let shell: String
    let content: String
    let timeoutSeconds: Int
    let isEphemeral: Bool

    // swiftlint:disable:next identifier_name
    var id: String {
        identifier
    }

    init(
        identifier: String,
        name: String,
        summary: String,
        category: String,
        systemImageName: String,
        shell: String = CPYSnippet.defaultScriptShell,
        content: String,
        timeoutSeconds: Int = CPYSnippet.defaultScriptTimeout,
        isEphemeral: Bool = true
    ) {
        self.identifier = identifier
        self.name = name
        self.summary = summary
        self.category = category
        self.systemImageName = systemImageName
        self.shell = shell
        self.content = content
        self.timeoutSeconds = timeoutSeconds
        self.isEphemeral = isEphemeral
    }
}

enum SnippetTemplateLibrary {
    static let builtInTemplates: [SnippetTemplate] = [
        SnippetTemplate(
            identifier: "json-pretty-print",
            name: "JSON Pretty Print",
            summary: "Format clipboard JSON with indentation.",
            category: "Format",
            systemImageName: "curlybraces",
            content: """
            if ! command -v python3 >/dev/null 2>&1; then
                echo "python3 is required for this template" >&2
                exit 127
            fi
            printf '%s' "$CLIPBOARD" | python3 -c 'import json, sys; sys.stdout.write(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "json-minify",
            name: "JSON Minify",
            summary: "Compress clipboard JSON to one line.",
            category: "Format",
            systemImageName: "curlybraces.square",
            content: """
            if ! command -v python3 >/dev/null 2>&1; then
                echo "python3 is required for this template" >&2
                exit 127
            fi
            printf '%s' "$CLIPBOARD" | python3 -c 'import json, sys; sys.stdout.write(json.dumps(json.load(sys.stdin), separators=(",", ":"), ensure_ascii=False))'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "base64-encode",
            name: "Base64 Encode",
            summary: "Encode clipboard text as Base64.",
            category: "Encode",
            systemImageName: "lock.fill",
            content: """
            printf '%s' "$CLIPBOARD" | base64 | tr -d '\\n'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "base64-decode",
            name: "Base64 Decode",
            summary: "Decode Base64 clipboard text.",
            category: "Decode",
            systemImageName: "lock.open.fill",
            content: """
            printf '%s' "$CLIPBOARD" | base64 -D
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "url-encode",
            name: "URL Encode",
            summary: "Percent-encode clipboard text.",
            category: "Encode",
            systemImageName: "link",
            content: """
            if ! command -v python3 >/dev/null 2>&1; then
                echo "python3 is required for this template" >&2
                exit 127
            fi
            printf '%s' "$CLIPBOARD" | python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.quote(sys.stdin.read(), safe=""))'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "jwt-payload-decode",
            name: "JWT Payload Decode",
            summary: "Decode and format a JWT payload.",
            category: "Decode",
            systemImageName: "key.horizontal.fill",
            content: """
            if ! command -v python3 >/dev/null 2>&1; then
                echo "python3 is required for this template" >&2
                exit 127
            fi
            printf '%s' "$CLIPBOARD" | python3 -c 'import base64, json, sys
            token = sys.stdin.read().strip()
            parts = token.split(".")
            if len(parts) < 2:
                raise SystemExit("Invalid JWT")
            payload = parts[1] + "=" * (-len(parts[1]) % 4)
            decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
            sys.stdout.write(json.dumps(json.loads(decoded), indent=2, ensure_ascii=False))'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "epoch-to-date",
            name: "Epoch to Date",
            summary: "Convert a Unix timestamp to a local date.",
            category: "Convert",
            systemImageName: "clock.fill",
            content: """
            if ! command -v python3 >/dev/null 2>&1; then
                echo "python3 is required for this template" >&2
                exit 127
            fi
            printf '%s' "$CLIPBOARD" | python3 -c 'import datetime, sys
            value = float(sys.stdin.read().strip())
            if value > 9999999999:
                value = value / 1000
            sys.stdout.write(datetime.datetime.fromtimestamp(value).astimezone().isoformat(timespec="seconds"))'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "generate-uuid",
            name: "Generate UUID",
            summary: "Generate a lowercase UUID.",
            category: "Generate",
            systemImageName: "number",
            content: """
            uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '\\n'
            """,
            timeoutSeconds: 5
        ),
        SnippetTemplate(
            identifier: "generate-password",
            name: "Generate Password",
            summary: "Generate a random 24-character password.",
            category: "Generate",
            systemImageName: "key.fill",
            content: """
            LC_ALL=C tr -dc 'A-Za-z0-9._~!@#%^+=-' < /dev/urandom | head -c 24
            """,
            timeoutSeconds: 5
        )
    ]

    static let categoryOrder = ["Format", "Encode", "Decode", "Convert", "Generate"]

    static var categories: [String] {
        categoryOrder.filter { category in
            builtInTemplates.contains { $0.category == category }
        }
    }

    static func templates(in category: String) -> [SnippetTemplate] {
        builtInTemplates.filter { $0.category == category }
    }
}
