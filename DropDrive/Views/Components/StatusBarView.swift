import SwiftUI

struct StatusBarView: View {
    let statusText: String

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return "Version \(version) Beta"
    }

    var body: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text("DropDrive")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(appVersion)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
