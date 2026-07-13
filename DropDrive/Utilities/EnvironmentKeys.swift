import SwiftUI

struct DeepLinkURLKey: EnvironmentKey {
    static let defaultValue: Binding<URL?> = .constant(nil)
}

extension EnvironmentValues {
    var deeplinkURL: Binding<URL?> {
        get { self[DeepLinkURLKey.self] }
        set { self[DeepLinkURLKey.self] = newValue }
    }
}
