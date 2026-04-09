//
//  FileIconHelper.swift
//  ReSourcer
//
//  Shared file type icon + color mapping
//

import SwiftUI

struct FileIconInfo {
    let icon: String   // SF Symbol name
    let color: Color
}

enum FileIconHelper {

    /// Returns icon name and color for a file based on its type and extension.
    static func iconInfo(for file: FileInfo) -> FileIconInfo {
        iconInfo(fileType: file.fileType, extension: file.extension)
    }

    static func iconInfo(fileType: FileType, extension ext: String) -> FileIconInfo {
        switch fileType {
        case .audio:  return FileIconInfo(icon: "music.note", color: .orange)
        case .video:  return FileIconInfo(icon: "film", color: .purple)
        case .image:  return FileIconInfo(icon: "photo", color: .blue)
        case .gif:    return FileIconInfo(icon: "photo", color: .blue)
        case .pdf:    return FileIconInfo(icon: "doc.fill", color: .red)
        case .other:  return iconForExtension(ext)
        }
    }

    private static func iconForExtension(_ ext: String) -> FileIconInfo {
        let e = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch e {
        // Code
        case "py", "js", "ts", "jsx", "tsx", "rs", "go", "java", "c", "cpp", "h",
             "swift", "kt", "rb", "php", "sh", "bash", "sql", "vue", "svelte":
            return FileIconInfo(icon: "chevron.left.forwardslash.chevron.right", color: .green)
        // Web
        case "html", "css", "scss":
            return FileIconInfo(icon: "globe", color: .green)
        // Data
        case "json", "xml", "yaml", "yml", "toml", "plist":
            return FileIconInfo(icon: "curlybraces", color: .orange)
        case "csv", "tsv":
            return FileIconInfo(icon: "tablecells", color: .orange)
        // Archives
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso":
            return FileIconInfo(icon: "doc.zipper", color: .purple)
        // Documents
        case "doc", "docx", "pages", "rtf", "odt":
            return FileIconInfo(icon: "doc.richtext", color: .blue)
        // Spreadsheets
        case "xls", "xlsx", "numbers", "ods":
            return FileIconInfo(icon: "tablecells", color: .green)
        // Presentations
        case "ppt", "pptx", "key", "odp":
            return FileIconInfo(icon: "rectangle.fill.on.rectangle.fill", color: .orange)
        // Text
        case "txt", "md", "log", "ini", "conf", "cfg":
            return FileIconInfo(icon: "doc.text", color: .secondary)
        // Fonts
        case "ttf", "otf", "woff", "woff2":
            return FileIconInfo(icon: "textformat", color: .cyan)
        default:
            return FileIconInfo(icon: "doc.fill", color: .secondary)
        }
    }
}
