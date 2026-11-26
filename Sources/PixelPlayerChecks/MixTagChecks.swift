import Foundation
@testable import PixelPlayerKit

/// The mark of a mix in a playlist's comment, as SpotCopy and PixelPlayer write it, and which copy stays.
func mixTagChecks() {
    // Reading, as the three apps write it (comments from the test Navidrome).
    let your = MixTag.read(comment: "Made for you, refreshed every day. [mix:your::2026-11-27]")
    check(your == MixTag(kind: "your", key: "", date: "2026-11-27"), "Your Mix mark reads with an empty key")
    let pixel = MixTag.read(comment: "PixelPlayer [mix:daily::2026-11-26]")
    check(pixel == MixTag(kind: "daily", key: "", date: "2026-11-26"), "PixelPlayer's Daily Mix reads, mark after other words")
    let spot = MixTag.read(comment: "Made for you, new every day. [mix:daily:1:2026-11-26]")
    check(spot == MixTag(kind: "daily", key: "1", date: "2026-11-26"), "SpotCopy's Daily Mix 1 reads with key 1")
    check(MixTag.read(comment: "[mix:genre:hip:hop:2026-11-26]")?.key == "hip:hop", "a key with a colon stays whole")
    check(pixel.map { !$0.sameMix(as: spot!) } ?? false, "daily and daily:1 are different mixes")

    // Writing.
    let today = MixTag(kind: "your", date: "2026-11-27")
    check(today.mark == "[mix:your::2026-11-27]", "the mark is written with two colons for an empty key")
    check(today.comment == "Made for you, refreshed every day. [mix:your::2026-11-27]", "the comment is the sentence and the mark")
    check(MixTag.read(comment: today.comment) == today, "what is written reads back the same")

    // The old comment of this Mac.
    check(MixTag.read(comment: "PixelPlayer daily mix 2026-11-26", name: "Your Mix") == MixTag(kind: "your", date: "2026-11-26"),
          "the old comment on Your Mix counts as Your Mix of that day")
    check(MixTag.read(comment: "PixelPlayer daily mix 2026-11-26", name: "Road trip") == nil, "the old comment on another playlist is no mix")
    check(MixTag.isMix(comment: "PixelPlayer daily mix 2026-11-26", name: "Your Mix"), "the old Your Mix is hidden as a mix")
    check(!MixTag.isMix(comment: "My favourites", name: "Daily Mix 1"), "a playlist of your own called Daily Mix 1 stays yours")
    check(!MixTag.isMix(comment: nil, name: "Your Mix"), "Your Mix without a comment stays yours")
    check(MixTag.isMix(comment: "[mix:weekly:something]", name: "x"), "a mark this app can't read is still hidden")

    // Days.
    check(MixTag.read(comment: "[mix:your::2026-13-01]") == nil, "a month 13 is no day")
    check(MixTag.read(comment: "[mix:your::2026-02-30]") == nil, "30 February is no day")
    check(MixTag.read(comment: "[mix:your::27-11-2026]") == nil, "a day the other way round is not read")
    check(MixTag.read(comment: "[mix:your::]") == nil, "a mark without a day is not read")
    check(MixTag.read(comment: "[mix:your:2026-11-27") == nil, "a mark without its bracket is not read")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 23, minute: 30))!
    check(MixTag.day(lateEvening, timeZone: calendar.timeZone) == "2026-11-27", "the day is the local day")
    check(MixTag.day(lateEvening, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "2026-11-28", "another zone gives its own day")

    // Times as Navidrome sends them, with 9 and 8 digits: as text .2Z would sort after .21Z.
    let a = MixCopies.created("2026-11-26T19:08:47.205213122Z"), b = MixCopies.created("2026-11-26T19:08:47.21337357Z")
    check(a < b, "times with a different number of digits compare as times")
    check(MixCopies.created("2026-11-26T19:08:47.2Z") < MixCopies.created("2026-11-26T19:08:47.21Z"), ".2 is before .21")
    check(MixCopies.created("2026-11-26T20:08:47+01:00") == MixCopies.created("2026-11-26T19:08:47Z"), "a zone offset is taken into account")
    check(MixCopies.created(nil) == .infinity, "no time counts as newest")

    // Which copy stays: the oldest of this account's with this mark; the rest goes; nothing else is touched.
    let lists = [
        MixPlaylist(id: "new", name: "Your Mix", comment: "Made for you, refreshed every day. [mix:your::2026-11-27]", owner: "admin",
                    created: "2026-11-27T08:00:00.21337357Z"),
        MixPlaylist(id: "old", name: "Your Mix", comment: "PixelPlayer daily mix 2026-11-26", owner: "admin",
                    created: "2026-11-27T08:00:00.205213122Z"),
        MixPlaylist(id: "mine", name: "Your Mix", comment: "my own", owner: "admin", created: "2026-01-01T00:00:00Z"),
        MixPlaylist(id: "other", name: "Your Mix", comment: "[mix:your::2026-11-27]", owner: "simon", created: "2025-01-01T00:00:00Z"),
        MixPlaylist(id: "shared", name: "Your Mix", comment: "[mix:your::2026-11-27]", owner: "Admin", created: "2025-01-01T00:00:00Z", readonly: true),
        MixPlaylist(id: "daily", name: "Daily Mix", comment: "[mix:daily::2026-11-27]", owner: "admin", created: "2020-01-01T00:00:00Z"),
    ]
    let plan = MixCopies.plan(for: today, in: lists, user: "ADMIN")
    check(plan.keep?.id == "old", "the oldest copy stays, the old comment included")
    check(plan.remove.map(\.id) == ["new"], "only the newer copy with the mark goes")
    check(MixCopies.plan(for: today, in: lists.filter { $0.id == "mine" }, user: "admin").keep == nil, "a playlist without mark is never chosen")
    let tie = [MixPlaylist(id: "b", name: "Your Mix", comment: "[mix:your::2026-11-27]", owner: "admin", created: "2026-11-27T08:00:00Z"),
               MixPlaylist(id: "a", name: "Your Mix", comment: "[mix:your::2026-11-27]", owner: "admin", created: "2026-11-27T08:00:00Z")]
    check(MixCopies.plan(for: today, in: tie, user: "admin").keep?.id == "a", "on the same time the lowest id stays")
}
