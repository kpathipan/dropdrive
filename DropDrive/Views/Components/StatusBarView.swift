import SwiftUI

struct StatusBarView: View {
    let statusText: String

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0.0"
        return "DropDrive • v\(version) Dev"
    }

    var body: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text(versionLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
