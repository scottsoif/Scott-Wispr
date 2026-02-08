//
//  ActiveAppContext.swift
//  JustWhisper
//
//  Created by Scott Soifer on 2/7/26.
//

import Cocoa
import ApplicationServices

/// Detects the active application and gathers project context (file list) for smarter transcription
class ActiveAppContext {

    struct AppContext {
        let appName: String
        let windowTitle: String
        let projectPath: String?
        let projectFiles: [String]
    }

    /// Known IDE bundle IDs and their window title patterns
    private static let ideApps: Set<String> = [
        "Cursor", "Code", "Visual Studio Code", "VSCodium",
        "Xcode", "IntelliJ IDEA", "PyCharm", "WebStorm",
        "Android Studio", "Sublime Text", "Atom", "Fleet"
    ]

    /// Common developer directories to search for projects
    private static let devDirectories: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/coding",
            "\(home)/code",
            "\(home)/projects",
            "\(home)/dev",
            "\(home)/Developer",
            "\(home)/workspace",
            "\(home)/repos",
            "\(home)/src",
            "\(home)/Documents",
            "\(home)/Desktop"
        ]
    }()

    /// Gets context about the currently active application
    static func getCurrentContext() -> AppContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier

        // Get window title via Accessibility API
        let windowTitle = getWindowTitle(pid: pid) ?? ""

        // Try to extract project path from window title
        let projectPath = extractProjectPath(from: windowTitle, appName: appName)

        // Get file list if we found a project
        var projectFiles: [String] = []
        if let path = projectPath {
            projectFiles = getProjectFiles(at: path)
        }

        return AppContext(
            appName: appName,
            windowTitle: windowTitle,
            projectPath: projectPath,
            projectFiles: projectFiles
        )
    }

    /// Gets the window title of the frontmost window for a given PID using the Accessibility API
    private static func getWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)

        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        // Get the title of the first (frontmost) window
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, !title.isEmpty {
                return title
            }
        }

        return nil
    }

    /// Extracts a project directory path from an IDE window title
    /// Common patterns:
    ///   Cursor/VS Code: "filename.ts — project_folder"  or  "filename.ts — project_folder — Cursor"
    ///   Xcode: "Project — filename.swift"
    private static func extractProjectPath(from windowTitle: String, appName: String) -> String? {
        // Split on em-dash (—) which IDEs commonly use
        let parts = windowTitle.components(separatedBy: " — ").map { $0.trimmingCharacters(in: .whitespaces) }

        guard parts.count >= 2 else { return nil }

        // For Cursor/VS Code, project name is typically the last meaningful part
        // "file.ts — project_name" or "file.ts — project_name — Cursor"
        var projectName: String?

        if ideApps.contains(appName) {
            // Try the second part first (most common: "file — project")
            // But skip parts that are the app name itself
            for part in parts.reversed() {
                if part != appName && !part.isEmpty {
                    projectName = part
                    break
                }
            }
        }

        guard let name = projectName else { return nil }

        // Search common dev directories for a folder matching this name
        return findProjectDirectory(named: name)
    }

    /// Searches common developer directories for a project folder by name
    private static func findProjectDirectory(named name: String) -> String? {
        let fm = FileManager.default

        for devDir in devDirectories {
            let candidatePath = "\(devDir)/\(name)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidatePath, isDirectory: &isDir), isDir.boolValue {
                return candidatePath
            }
        }

        // Also check if the name itself is an absolute path
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: name, isDirectory: &isDir), isDir.boolValue {
            return name
        }

        return nil
    }

    /// Gets the list of files in a project directory using git ls-files (or fallback to find)
    private static func getProjectFiles(at path: String) -> [String] {
        // Try git ls-files first (faster, respects .gitignore)
        if let gitFiles = runCommand("git", arguments: ["-C", path, "ls-files"]) {
            let files = gitFiles.components(separatedBy: "\n").filter { !$0.isEmpty }
            if !files.isEmpty {
                return files
            }
        }

        // Fallback: list files directly (limited depth to avoid huge lists)
        if let findFiles = runCommand("/usr/bin/find", arguments: [path, "-maxdepth", "3", "-type", "f", "-not", "-path", "*/.*"]) {
            let files = findFiles.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { $0.replacingOccurrences(of: path + "/", with: "") }
            return Array(files.prefix(200)) // Cap at 200 files
        }

        return []
    }

    /// Runs a shell command and returns stdout
    private static func runCommand(_ command: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command == "git" ? "/usr/bin/git" : command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Categorizes apps into types for formatting guidance
    enum AppCategory: String {
        case messaging    // iMessage, WhatsApp, Telegram, Discord DMs
        case email        // Mail, Outlook, Gmail
        case chat         // Slack, Teams, Discord channels
        case ide          // Cursor, VS Code, Xcode
        case notes        // Notes, Notion, Obsidian, Bear
        case document     // Pages, Word, Google Docs
        case browser      // Safari, Chrome, Firefox, Arc
        case social       // Twitter/X, LinkedIn, Reddit
        case terminal     // Terminal, iTerm, Warp
        case other
    }

    /// Maps app names to categories
    private static func categorize(_ appName: String) -> AppCategory {
        let name = appName.lowercased()

        // Messaging
        if ["messages", "whatsapp", "telegram", "signal", "imessage"].contains(where: { name.contains($0) }) {
            return .messaging
        }
        // Email
        if ["mail", "outlook", "gmail", "spark", "airmail", "mimestream"].contains(where: { name.contains($0) }) {
            return .email
        }
        // Chat/collaboration
        if ["slack", "teams", "discord", "zoom", "webex"].contains(where: { name.contains($0) }) {
            return .chat
        }
        // IDEs
        if ideApps.contains(appName) {
            return .ide
        }
        // Notes
        if ["notes", "notion", "obsidian", "bear", "craft", "evernote", "apple notes"].contains(where: { name.contains($0) }) {
            return .notes
        }
        // Documents
        if ["pages", "word", "google docs", "libreoffice", "textedit"].contains(where: { name.contains($0) }) {
            return .document
        }
        // Browser
        if ["safari", "chrome", "firefox", "arc", "brave", "edge", "opera"].contains(where: { name.contains($0) }) {
            return .browser
        }
        // Social
        if ["twitter", "x", "linkedin", "reddit", "mastodon"].contains(where: { name.contains($0) }) {
            return .social
        }
        // Terminal
        if ["terminal", "iterm", "warp", "kitty", "alacritty", "hyper"].contains(where: { name.contains($0) }) {
            return .terminal
        }

        return .other
    }

    /// Fast version that only captures app name, category, and window title (no filesystem/git).
    /// Use this on the main thread so recording can start immediately.
    static func buildPromptContextFast() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier
        let windowTitle = getWindowTitle(pid: pid) ?? ""
        let category = categorize(appName)

        var parts: [String] = []
        parts.append("Active app: \(appName) (category: \(category.rawValue))")
        if !windowTitle.isEmpty {
            parts.append("Window: \(windowTitle)")
        }
        return parts.joined(separator: "\n")
    }

    /// Builds a context string suitable for including in a GPT prompt
    /// Always returns context (at minimum the app name) so the prompt can adapt formatting.
    /// NOTE: This may be slow (runs git ls-files) — call from a background thread.
    static func buildPromptContext() -> String? {
        guard let context = getCurrentContext() else { return nil }

        let category = categorize(context.appName)
        var parts: [String] = []

        // Always include app info
        parts.append("Active app: \(context.appName) (category: \(category.rawValue))")

        if !context.windowTitle.isEmpty {
            parts.append("Window: \(context.windowTitle)")
        }

        // Add project file context for IDEs
        if !context.projectFiles.isEmpty {
            let maxFiles = 150
            let files = Array(context.projectFiles.prefix(maxFiles))
            let fileList = files.joined(separator: "\n")
            let truncatedNote = context.projectFiles.count > maxFiles
                ? "\n(... and \(context.projectFiles.count - maxFiles) more files)"
                : ""

            parts.append("""
            Project: \(context.projectPath?.components(separatedBy: "/").last ?? "unknown")
            Files in the project:
            \(fileList)\(truncatedNote)

            If the speaker mentions something that sounds like one of these file names, replace it with the actual file path from the list above.
            """)
        }

        return parts.joined(separator: "\n")
    }
}
