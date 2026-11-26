import Foundation
@testable import PixelPlayerKit

/// Importing a font in Settings: weight and slant from OS/2, broken files passed over, one file per style.
func fontImportChecks() {
    var os2 = [UInt8](repeating: 0, count: 96)
    os2[4] = 0x02; os2[5] = 0xBC  // 700
    check(FontImport.style(os2: os2)?.weight == 700, "weight comes from usWeightClass")
    check(FontImport.style(os2: os2)?.italic == false, "upright without the italic bit")
    os2[63] = 0x01
    check(FontImport.style(os2: os2)?.italic == true, "fsSelection bit 0 is italic")
    os2[63] = 0; os2[62] = 0x02
    check(FontImport.style(os2: os2)?.italic == true, "fsSelection bit 9 (oblique) counts as italic")
    check(FontImport.style(os2: Array(os2.prefix(40))) == nil, "a short OS/2 table gives no style")

    check(FontImport.wholeLayout([0, 1, 0, 0, 0, 10]), "GPOS 1.0 is whole")
    check(FontImport.wholeLayout([0, 1, 0, 3]), "GDEF 1.3 is whole")
    check(!FontImport.wholeLayout([0x54, 0x20, 0x00, 0x3A]), "a table that starts mid-way is broken (as in the Mix TTFs)")
    check(FontImport.wholeLayout(nil), "no table at all is not broken")

    func face(_ name: String, _ weight: Int, italic: Bool = false, intact: Bool = true, family: String = "Spotify Mix") -> FontImport.Face {
        FontImport.Face(url: URL(fileURLWithPath: "/fonts/\(name)"), weight: weight, italic: italic, family: family, intact: intact)
    }
    let download = [
        face("Mix-Regular.ttf", 400, intact: false, family: "\u{5265}lar"), face("Mix-Regular.woff", 400), face("Mix-Regular.woff2", 400),
        face("Mix-Bold.ttf", 700, intact: false, family: "a r k s"), face("Mix-Bold.woff2", 700),
        face("Mix-BoldItalic.woff", 700, italic: true), face("Mix-Extrabold.woff2", 800),
    ]
    let picked = FontImport.pick(download)
    check(picked.count == 4, "one file per weight and slant")
    check(picked.first { $0.weight == 400 }?.url.lastPathComponent == "Mix-Regular.woff", "a whole WOFF beats a broken TTF")
    check(picked.last?.italic == true, "italics come after the upright faces")
    check(FontImport.pick([face("a.woff2", 400), face("a.otf", 400)]).first?.url.pathExtension == "otf", "OpenType before WOFF2 when both are whole")
    check(FontImport.pick([face("a.ttf", 400, intact: false)]).count == 1, "a broken file is still used when it is the only one")

    check(FontImport.missing(picked) == nil, "regular and bold are enough")
    check(FontImport.missing([face("a.ttf", 700)]) == "Regular is missing", "says what is missing")
    check(FontImport.missing([face("a.ttf", 400, italic: true), face("b.ttf", 700, italic: true)]) == "Regular and Bold are missing", "italics alone are not enough")
    check(FontImport.missing([]) == "No fonts in what you chose", "nothing found")

    check(FontImport.displayName(download) == "Spotify Mix", "the first readable family name")
    check(FontImport.displayName([face("Mix-Bold.ttf", 700, family: "a r\u{0}")]) == "Mix", "a broken name falls back to the file name")

    // With PP_FONTS=<a folder or zip of Mix> the real files are read as well.
    if let path = ProcessInfo.processInfo.environment["PP_FONTS"] {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("pp-font-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let files = FontImport.collect([URL(fileURLWithPath: path)], unpackingInto: scratch)
        let faces = FontImport.pick(files.compactMap(FontImport.inspect))
        print("fonts in \(path): \(files.count) files, \(faces.count) styles, broken: \(faces.filter { !$0.intact }.map(\.url.lastPathComponent))")
        check(FontImport.missing(faces) == nil, "the real download has regular and bold")
        check(faces.allSatisfy(\.intact), "the real download gives whole files for every style")
    }
}
