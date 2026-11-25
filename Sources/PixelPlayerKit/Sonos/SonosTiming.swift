import Foundation

/// Every Sonos timing of the Android app (spec 5.16), in milliseconds unless the name says otherwise.
/// Kept in one place so the Mac and the phone stay in step when one of them changes.
public enum SonosTiming {
    /// Not a whole second, so each poll lands at another moment in the speaker's second (see the offset estimate).
    public static let pollInterval = 1_130
    public static let syncDebounce = 250
    /// Skips closer together than this are one run.
    public static let skipRunWindow = 1_500
    /// How long the speaker stays quiet after the last skip of a run.
    public static let skipRunDebounce = 800
    public static let trackCommandGrace = 4_000
    public static let playPauseGrace = 3_000
    public static let autoAdvanceGrace = 7_000
    public static let takeoverGrace = 6_000
    public static let driftLimit = 2_500
    /// A lyric line that is this far off is just noticeable.
    public static let fineSyncLimit = 250
    /// Polls between reads: takeover check (once settled), volumes, topology.
    public static let takeoverPollTicks = 2
    public static let volumePollTicks = 3
    public static let groupPollTicks = 4
    public static let groupWatch = 3_000
    /// Longer than a speaker needs to buffer a song from the server at home.
    public static let stall = 12_000
    public static let reachTimeout = 3_000
    public static let warmUpInterval = 60_000
    public static let resumeGrace = 20_000
    /// A speaker on pause only counts as still in use for this long.
    public static let resumePausedWithin = 12 * 60 * 60 * 1000
    public static let playStartTimeout = 4_000
    public static let playStartCheck = 120
    /// From Play to sound on a real speaker (measured 0.5 to 0.6 s); the pre-seek aims that far ahead.
    public static let startLead = 550
    /// Spotify Connect grabs a speaker back about 0.5 s after losing it unless it got a Pause first.
    public static let releaseSourceWait = 300
    public static let holdAttempts = 3
    public static let holdChecks = 5
    public static let holdCheckInterval = 150
    public static let seekLead = 250
    public static let alignTolerance = 1_200
    /// Below this phone position a seek is not worth it (pre-seek, align, jump within the queue).
    public static let seekMinimum = 1_500
    /// Volume changes closer together than this count as one drag or run of key presses.
    public static let volumeGesture = 1_500
    public static let volumeSendDelay = 90
    /// A volume refresh is skipped, and its answer dropped, this soon after a change by the user.
    public static let volumeRefreshQuiet = 2_000
    public static let volumeKeyStep = 2
    /// Wait after grouping before the topology is read again.
    public static let groupSettle = 700
    public static let maxUpcoming = 100
    public static let maxSkipStreak = 25
    public static let maxPollFailures = 8
    /// SOAP transport (5.2). URLSession has no separate connect timeout, so the read timeout covers both.
    public static let soapConnectTimeout = 3_000
    public static let soapReadTimeout = 8_000
    public static let quickCallLimit = 1_500
    /// SSDP (5.1): two sends, a 400 ms socket timeout, 2 s of listening.
    public static let ssdpSends = 2
    public static let ssdpSocketTimeout = 400
    public static let ssdpListen = 2_000
    /// When a session ends with a pause, the app unmutes its own player this much later so the pause reaches the sink.
    public static let unmuteAfterPause = 300
}
