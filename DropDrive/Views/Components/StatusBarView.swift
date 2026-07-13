import SwiftUI

struct StatusBarView: View {
    let statusText: String
    let isConnected: Bool

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return "Version \(version) (Beta)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? .green : .secondary)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text(appVersion)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
