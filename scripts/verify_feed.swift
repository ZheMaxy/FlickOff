// Checks an update feed the way Sparkle does, with only the public key: this runs in CI, where no signing key may go.
//   swift scripts/verify_feed.swift <feed> <Info.plist> [--archives] [--newer-than <older feed>]
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

func ok(_ message: String) {
    print("PASS: \(message)")
}

/// Every Sparkle build number in a feed, newest first, with its enclosure.
func items(in data: Data) -> [(build: Int, enclosure: XMLElement?, item: XMLElement)] {
    guard let document = try? XMLDocument(data: data, options: []),
          let nodes = try? document.nodes(forXPath: "//item") as? [XMLElement] else { fail("the feed isn't valid XML") }
    return nodes.map { item in
        guard let text = item.elements(forName: "sparkle:version").first?.stringValue, let build = Int(text) else {
            fail("an item has no numeric sparkle:version")
        }
        return (build, item.elements(forName: "enclosure").first, item)
    }.sorted { $0.build > $1.build }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let checkArchives = arguments.contains("--archives")
arguments.removeAll { $0 == "--archives" }
var olderFeed: String?
if let index = arguments.firstIndex(of: "--newer-than"), index + 1 < arguments.count {
    olderFeed = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
}
guard arguments.count == 2 else { fail("usage: verify_feed.swift <feed> <Info.plist> [--archives] [--newer-than <older feed>]") }

guard let feed = FileManager.default.contents(atPath: arguments[0]) else { fail("can't read \(arguments[0])") }
guard let info = NSDictionary(contentsOfFile: arguments[1]),
      let keyText = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: keyText),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { fail("no usable SUPublicEDKey in \(arguments[1])") }

// sign_update appends the signature as a comment and signs everything before it.
let text = String(decoding: feed, as: UTF8.self)
let pattern = try! NSRegularExpression(pattern: #"<!-- sparkle-signatures:\s+edSignature: (\S+)\s+length: (\d+)\s+-->"#)
guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let signature = Range(match.range(at: 1), in: text).flatMap({ Data(base64Encoded: String(text[$0])) }),
      let length = Range(match.range(at: 2), in: text).flatMap({ Int(text[$0]) }) else { fail("the feed carries no signature") }
guard length <= feed.count, key.isValidSignature(signature, for: feed.prefix(length)) else { fail("the feed's signature is invalid") }
ok("the feed is signed by the key the app trusts")

let found = items(in: feed)
guard let newest = found.first else { fail("the feed offers nothing") }
if let sourceBuild = (info["CFBundleVersion"] as? String).flatMap(Int.init), newest.build > sourceBuild {
    fail("the feed offers build \(newest.build), but the source is only at build \(sourceBuild)")
}
for entry in found {
    let requirements = entry.item.elements(forName: "sparkle:hardwareRequirements").first?.stringValue
    guard requirements == "arm64" else { fail("build \(entry.build) could be offered to Intel Macs") }
    guard entry.item.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue != nil else {
        fail("build \(entry.build) names no minimum macOS version")
    }
    guard let enclosure = entry.enclosure, enclosure.attribute(forName: "sparkle:edSignature") != nil,
          enclosure.attribute(forName: "url")?.stringValue?.hasPrefix("https://") == true else {
        fail("build \(entry.build) has no signed https archive")
    }
}
ok("newest build is \(newest.build), and every item is arm64-only with a signed https archive")

if let olderFeed {
    guard let older = FileManager.default.contents(atPath: olderFeed) else { fail("can't read \(olderFeed)") }
    guard let previous = items(in: older).first?.build else { fail("\(olderFeed) offers nothing") }
    guard newest.build > previous else { fail("build \(newest.build) isn't newer than the published \(previous): Sparkle would ignore it") }
    ok("build \(newest.build) is newer than the published \(previous)")
}

if checkArchives {
    for entry in found {
        guard let enclosure = entry.enclosure,
              let address = enclosure.attribute(forName: "url")?.stringValue, let url = URL(string: address),
              let signatureText = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
              let archiveSignature = Data(base64Encoded: signatureText),
              let lengthText = enclosure.attribute(forName: "length")?.stringValue else { fail("build \(entry.build) has an incomplete enclosure") }
        guard address.hasPrefix("https://github.com/ZheMaxy/FlickOff/releases/download/") else { fail("build \(entry.build) points outside this project's releases: \(address)") }
        guard let archive = try? Data(contentsOf: url) else { fail("can't download \(address)") }
        guard String(archive.count) == lengthText else { fail("\(address) is \(archive.count) bytes, the feed says \(lengthText)") }
        guard key.isValidSignature(archiveSignature, for: archive) else { fail("the signature of \(address) is invalid") }
        ok("the archive of build \(entry.build) downloads, and its size and signature match")
    }
}
