import SwiftUI

/// Token classes the highlighter can emit. Colours follow the widely-recognised
/// VS Code "Dark+" palette so the read-only viewer reads like a real editor.
enum CodeTokenKind: Equatable {
    case plain, comment, string, number, keyword, type

    var color: Color {
        switch self {
        case .plain:   return Theme.textPrimary
        case .comment: return Color(hex: 0x6A9955)
        case .string:  return Color(hex: 0xCE9178)
        case .number:  return Color(hex: 0xB5CEA8)
        case .keyword: return Color(hex: 0x569CD6)
        case .type:    return Color(hex: 0x4EC9B0)
        }
    }
}

/// A contiguous slice of a single line sharing one token class.
struct CodeRun: Equatable {
    let text: String
    let kind: CodeTokenKind
}

/// A tiny, dependency-free lexer. It is intentionally approximate (single pass,
/// no full grammar) but handles the constructs that matter for readability:
/// line + block comments, quoted strings with escapes, numbers, and a
/// per-language keyword/type vocabulary. Anything it can't classify stays
/// `.plain`, so worst case the viewer simply looks like before.
enum SyntaxHighlighter {

    struct Language {
        let lineComments: [String]
        let blockComment: (open: String, close: String)?
        let stringDelimiters: Set<Character>
        let keywords: Set<String>
        let types: Set<String>
        /// Treat Capitalized identifiers as type references (true for most
        /// curly-brace / typed languages).
        let capitalizedAsType: Bool
    }

    /// Produce per-line coloured runs. Block-comment state is carried across
    /// line boundaries so multi-line `/* … */` comments colour correctly.
    static func highlight(_ text: String, language lang: Language?) -> [[CodeRun]] {
        guard let lang else {
            return text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { [CodeRun(text: String($0), kind: .plain)] }
        }

        let chars = Array(text)
        let n = chars.count
        var i = 0

        var lines: [[CodeRun]] = []
        var current: [CodeRun] = []
        var buffer = ""
        var bufferKind: CodeTokenKind = .plain
        var inBlock = false
        var stringDelim: Character? = nil

        func flush() {
            if !buffer.isEmpty {
                current.append(CodeRun(text: buffer, kind: bufferKind))
                buffer = ""
            }
        }
        func emit(_ s: String, _ kind: CodeTokenKind) {
            if kind != bufferKind { flush(); bufferKind = kind }
            buffer += s
        }
        func newline() {
            flush()
            lines.append(current)
            current = []
            bufferKind = .plain
            stringDelim = nil  // plain strings don't span lines in this model
        }
        func matches(_ token: String, at idx: Int) -> Bool {
            guard !token.isEmpty, idx + token.count <= n else { return false }
            for (k, ch) in token.enumerated() where chars[idx + k] != ch { return false }
            return true
        }
        func isIdentStart(_ c: Character) -> Bool { c == "_" || c.isLetter }
        func isIdentBody(_ c: Character) -> Bool { c == "_" || c.isLetter || c.isNumber }

        while i < n {
            let c = chars[i]

            if c == "\n" { newline(); i += 1; continue }

            if inBlock {
                if let close = lang.blockComment?.close, matches(close, at: i) {
                    emit(close, .comment); i += close.count; inBlock = false
                } else {
                    emit(String(c), .comment); i += 1
                }
                continue
            }

            if let delim = stringDelim {
                if c == "\\", i + 1 < n {
                    emit(String(chars[i]) + String(chars[i + 1]), .string); i += 2; continue
                }
                emit(String(c), .string); i += 1
                if c == delim { stringDelim = nil }
                continue
            }

            // Line comment → rest of the line.
            if let token = lang.lineComments.first(where: { matches($0, at: i) }) {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                emit(String(chars[i..<j]), .comment); i = j
                _ = token
                continue
            }

            // Block comment open.
            if let block = lang.blockComment, matches(block.open, at: i) {
                emit(block.open, .comment); i += block.open.count; inBlock = true
                continue
            }

            // String open.
            if lang.stringDelimiters.contains(c) {
                stringDelim = c; emit(String(c), .string); i += 1
                continue
            }

            // Number.
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                var j = i
                while j < n && (chars[j].isHexDigit || ".xXeEbBoO_".contains(chars[j])) { j += 1 }
                emit(String(chars[i..<j]), .number); i = j
                continue
            }

            // Identifier / keyword / type.
            if isIdentStart(c) {
                var j = i
                while j < n && isIdentBody(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                let kind: CodeTokenKind
                if lang.keywords.contains(word) {
                    kind = .keyword
                } else if lang.types.contains(word)
                            || (lang.capitalizedAsType && (word.first?.isUppercase ?? false)) {
                    kind = .type
                } else {
                    kind = .plain
                }
                emit(word, kind); i = j
                continue
            }

            emit(String(c), .plain); i += 1
        }
        flush()
        lines.append(current)
        return lines
    }

    // MARK: Language detection

    static func language(forPath path: String) -> Language? {
        let ext = (path as NSString).pathExtension.lowercased()
        let name = (path as NSString).lastPathComponent.lowercased()
        switch ext {
        case "swift": return swift
        case "js", "jsx", "mjs", "cjs", "ts", "tsx": return cFamily(keywords: jsKeywords)
        case "c", "h", "cpp", "cc", "hpp", "cxx", "m", "mm": return cFamily(keywords: cKeywords)
        case "java", "kt", "kts", "scala", "groovy", "cs": return cFamily(keywords: jvmKeywords)
        case "go": return cFamily(keywords: goKeywords)
        case "rs": return cFamily(keywords: rustKeywords)
        case "py", "pyi": return hashLang(keywords: pyKeywords)
        case "rb": return hashLang(keywords: rubyKeywords)
        case "sh", "bash", "zsh", "fish": return hashLang(keywords: shellKeywords)
        case "yml", "yaml", "toml", "ini", "conf", "cfg": return hashLang(keywords: [])
        case "json", "json5", "jsonc": return cFamily(keywords: ["true", "false", "null"])
        case "css", "scss", "less": return cFamily(keywords: [])
        case "php": return cFamily(keywords: jsKeywords)
        default:
            if name == "dockerfile" || name == "makefile" { return hashLang(keywords: []) }
            return nil
        }
    }

    /// Map a markdown code-fence info string (e.g. ```` ```swift ````, `python`,
    /// `sh`) to a `Language`. Falls back to extension-based detection so a tag
    /// like `swift` reuses the same grammar as a `.swift` file.
    static func language(forFenceTag tag: String) -> Language? {
        let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        let ext: String
        switch t {
        case "javascript", "node": ext = "js"
        case "typescript": ext = "ts"
        case "python", "python3": ext = "py"
        case "ruby": ext = "rb"
        case "shell", "console", "terminal": ext = "sh"
        case "golang": ext = "go"
        case "rust": ext = "rs"
        case "objective-c", "objc": ext = "m"
        case "c++": ext = "cpp"
        case "c#", "csharp": ext = "cs"
        case "kotlin": ext = "kt"
        case "yaml": ext = "yml"
        case "html", "xml", "markdown", "md", "text", "txt", "plaintext": return nil
        default: ext = t
        }
        return language(forPath: "x.\(ext)")
    }

    // MARK: Language definitions

    private static func cFamily(keywords: Set<String>) -> Language {
        Language(lineComments: ["//"], blockComment: ("/*", "*/"),
                 stringDelimiters: ["\"", "'", "`"],
                 keywords: keywords, types: commonTypes, capitalizedAsType: true)
    }

    private static func hashLang(keywords: Set<String>) -> Language {
        Language(lineComments: ["#"], blockComment: nil,
                 stringDelimiters: ["\"", "'"],
                 keywords: keywords, types: commonTypes, capitalizedAsType: true)
    }

    private static let swift = Language(
        lineComments: ["//"], blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        keywords: ["import", "struct", "class", "enum", "protocol", "extension", "func",
                   "var", "let", "if", "else", "guard", "switch", "case", "default", "for",
                   "while", "repeat", "in", "return", "break", "continue", "do", "try",
                   "catch", "throw", "throws", "rethrows", "async", "await", "defer",
                   "private", "public", "internal", "fileprivate", "open", "static", "final",
                   "self", "Self", "super", "init", "deinit", "nil", "true", "false",
                   "where", "as", "is", "some", "any", "typealias", "associatedtype",
                   "lazy", "weak", "unowned", "mutating", "nonmutating", "override",
                   "convenience", "required", "indirect", "subscript", "willSet", "didSet",
                   "get", "set", "inout", "operator", "precedencegroup"],
        types: commonTypes, capitalizedAsType: true)

    private static let commonTypes: Set<String> = [
        "Int", "String", "Bool", "Double", "Float", "Void", "Array", "Dictionary",
        "Set", "Optional", "Character", "Data", "Date", "URL", "Error", "Any",
        "AnyObject", "Result", "Task"
    ]

    private static let jsKeywords: Set<String> = [
        "const", "let", "var", "function", "return", "if", "else", "for", "while",
        "do", "switch", "case", "default", "break", "continue", "new", "class",
        "extends", "super", "this", "import", "export", "from", "as", "async",
        "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "in",
        "of", "delete", "void", "yield", "null", "undefined", "true", "false",
        "interface", "type", "enum", "implements", "public", "private", "protected",
        "readonly", "static", "abstract", "namespace", "declare", "get", "set"
    ]

    private static let cKeywords: Set<String> = [
        "int", "char", "short", "long", "float", "double", "void", "unsigned",
        "signed", "struct", "union", "enum", "typedef", "const", "static", "extern",
        "register", "volatile", "sizeof", "if", "else", "for", "while", "do",
        "switch", "case", "default", "break", "continue", "return", "goto", "inline",
        "namespace", "class", "public", "private", "protected", "virtual", "template",
        "typename", "using", "new", "delete", "this", "true", "false", "nullptr",
        "bool", "auto", "constexpr", "override", "final", "operator", "friend"
    ]

    private static let jvmKeywords: Set<String> = [
        "public", "private", "protected", "class", "interface", "enum", "extends",
        "implements", "abstract", "final", "static", "void", "new", "return", "if",
        "else", "for", "while", "do", "switch", "case", "default", "break",
        "continue", "try", "catch", "finally", "throw", "throws", "import", "package",
        "this", "super", "null", "true", "false", "val", "var", "fun", "object",
        "companion", "data", "sealed", "override", "open", "when", "is", "as", "in",
        "suspend", "lateinit", "by", "constructor", "init"
    ]

    private static let goKeywords: Set<String> = [
        "package", "import", "func", "var", "const", "type", "struct", "interface",
        "map", "chan", "go", "defer", "if", "else", "for", "range", "switch", "case",
        "default", "select", "return", "break", "continue", "fallthrough", "goto",
        "nil", "true", "false", "iota", "make", "new", "len", "cap", "append"
    ]

    private static let rustKeywords: Set<String> = [
        "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl",
        "for", "while", "loop", "if", "else", "match", "return", "break", "continue",
        "use", "mod", "pub", "crate", "self", "super", "as", "where", "move", "ref",
        "dyn", "async", "await", "unsafe", "extern", "type", "true", "false", "Some",
        "None", "Ok", "Err", "Box", "Vec", "String"
    ]

    private static let pyKeywords: Set<String> = [
        "def", "class", "return", "if", "elif", "else", "for", "while", "break",
        "continue", "import", "from", "as", "pass", "with", "try", "except",
        "finally", "raise", "lambda", "global", "nonlocal", "yield", "async",
        "await", "and", "or", "not", "in", "is", "None", "True", "False", "del",
        "assert", "self"
    ]

    private static let rubyKeywords: Set<String> = [
        "def", "end", "class", "module", "if", "elsif", "else", "unless", "case",
        "when", "while", "until", "for", "do", "begin", "rescue", "ensure", "return",
        "yield", "require", "require_relative", "include", "extend", "attr_accessor",
        "attr_reader", "attr_writer", "nil", "true", "false", "self", "then", "and",
        "or", "not", "in"
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
        "case", "esac", "function", "return", "in", "select", "echo", "export",
        "local", "source", "alias", "set", "unset", "read", "cd", "exit"
    ]
}
