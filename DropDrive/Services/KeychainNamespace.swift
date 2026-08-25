import Foundation

/// Keeps development credentials away from the production keychain item.
///
/// A Debug build is normally ad-hoc signed, so its identity is its changing
/// binary hash. If it rewrites the production OAuth item, the next installed
/// release no longer matches that item's ACL and macOS asks for the login
/// password. Release builds retain the original item name so existing users
/// keep their Google session across updates.
enum KeychainNamespace {
    static let releaseSessionItem = "DropDriveAuthSession"

    static let sessionItem: String = {
        #if DEBUG
        return "\(releaseSessionItem).debug"
        #else
        return releaseSessionItem
        #endif
    }()
}
