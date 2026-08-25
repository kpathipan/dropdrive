import Foundation

let expected = CommandLine.arguments.dropFirst().first ?? ""
guard KeychainNamespace.sessionItem == expected else {
    fputs(
        "FAIL keychain namespace: got \(KeychainNamespace.sessionItem), expected \(expected)\n",
        stderr
    )
    exit(1)
}

print("PASS keychain namespace: \(KeychainNamespace.sessionItem)")
