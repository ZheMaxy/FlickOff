import Foundation
import Testing

/// Repo root, found from this file's location: Tests/TouchBarKitTests/<file>.
private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func table(_ lang: String) throws -> [String: String] {
    let url = root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings")
    return try #require(NSDictionary(contentsOf: url) as? [String: String], "cannot parse \(url.path)")
}

private func swiftSources() throws -> [(name: String, text: String)] {
    let dir = root.appendingPathComponent("Sources")
    let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []
    return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
}

private func formatSpecifiers(_ s: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "%(\\d\\$)?l?[d@f]")
    return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
}

/// Every Resources/<lang>.lproj; English is the base and must always be there.
private let languages: [String] = {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Resources").path)) ?? []
    let langs = names.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(6)) }.sorted()
    return ["en"] + langs.filter { $0 != "en" }
}()

@Suite("Localization")
struct LocalizationTests {
    @Test func englishIsTheCompleteBase() throws {
        #expect(languages.first == "en")
        #expect(try !table("en").isEmpty)
    }

    @Test func everyTranslationHasTheSameKeysAsEnglish() throws {
        let en = try table("en")
        for lang in languages.dropFirst() {
            let other = try table(lang)
            #expect(Set(en.keys).subtracting(other.keys).isEmpty, "missing in \(lang)")
            #expect(Set(other.keys).subtracting(en.keys).isEmpty, "extra in \(lang)")
        }
    }

    @Test func translationsKeepFormatSpecifiers() throws {
        let en = try table("en")
        for lang in languages.dropFirst() {
            let other = try table(lang)
            for (key, value) in en {
                #expect(formatSpecifiers(value) == formatSpecifiers(other[key] ?? ""), "\(lang): \(key)")
            }
        }
    }

    @Test func everyKeyUsedInCodeIsTranslated() throws {
        let regex = try NSRegularExpression(pattern: #"L\("([^"]+)"\)"#)
        var used = Set<String>()
        for (_, text) in try swiftSources() {
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert((text as NSString).substring(with: m.range(at: 1)))
            }
        }
        #expect(!used.isEmpty)
        for lang in languages {
            let keys = try table(lang).keys
            #expect(used.subtracting(keys).isEmpty, "untranslated in \(lang): \(used.subtracting(keys).sorted())")
        }
    }

    @Test func everyTranslatedKeyIsUsed() throws {
        let code = try swiftSources().map(\.text).joined()
        let unused = try table("en").keys.filter { !code.contains("L(\"\($0)\")") }
        #expect(unused.isEmpty, "stale keys: \(unused.sorted())")
    }

    /// UI text must come from the string tables, never from literals in the code.
    @Test func noHardcodedInterfaceText() throws {
        let allowed: Set<String> = ["Touch Bar", "FlickOff"] // hardware and product names
        let control = try NSRegularExpression(pattern: #"\b(Text|Button|Toggle|Picker|Label|Menu)\("((?:[^"\\]|\\.)*)""#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        for (name, text) in try swiftSources() {
            for m in control.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = (text as NSString).substring(with: m.range(at: 2))
                let words = interpolation.stringByReplacingMatches(in: literal, range: NSRange(literal.startIndex..., in: literal), withTemplate: "")
                guard words.range(of: "[A-Za-z]", options: .regularExpression) != nil, !allowed.contains(literal) else { continue }
                Issue.record("hardcoded UI text in \(name): \"\(literal)\"")
            }
        }
    }

    @Test func englishIsTheDevelopmentLanguage() throws {
        let plist = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")))
        #expect(plist["CFBundleDevelopmentRegion"] as? String == "en")
    }

    /// Without it macOS hands us System Settings names in the app's language (English) instead of the
    /// user's, and the setup steps would name panes that aren't on their screen.
    @Test func systemStringsFollowTheUsersLanguage() throws {
        let plist = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")))
        #expect(plist["CFBundleAllowMixedLocalizations"] as? Bool == true)
    }
}
