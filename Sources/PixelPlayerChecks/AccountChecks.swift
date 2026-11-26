import Foundation
@testable import PixelPlayerKit

/// The Navidrome account: who is signed in, and the name the app greets with.
func accountChecks() {
    check(SubsonicUser(username: "mark").firstName == "Mark", "a user name gets a capital")
    check(SubsonicUser(username: "anna.devries").firstName == "Anna", "up to the first dot")
    check(SubsonicUser(username: "jo_b").firstName == "Jo", "up to the first underscore")
    let answer = """
    {"subsonic-response":{"status":"ok","version":"1.16.1","user":{"username":"listener","email":"listener@example.com","scrobblingEnabled":true,"adminRole":false}}}
    """
    if let user = try? SubsonicClient.decode(Data(answer.utf8), key: "user", as: SubsonicUser.self) {
        check(user.username == "listener" && user.email == "listener@example.com", "getUser decodes")
    } else { check(false, "getUser decodes") }
    let config = SubsonicConfig(server: URL(string: "http://music.local:4533")!, user: "listener", password: "secret")
    let avatar = SubsonicClient(config: config).avatarURL().absoluteString
    check(avatar.hasPrefix("http://music.local:4533/rest/getAvatar?") && avatar.contains("username=listener"), "avatar URL asks for this account")
}
