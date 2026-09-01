import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let expected = arguments.first ?? ""
guard KeychainNamespace.sessionItem == expected else {
    fputs(
        "FAIL keychain namespace: got \(KeychainNamespace.sessionItem), expected \(expected)\n",
        stderr
    )
    exit(1)
}

print("PASS keychain namespace: \(KeychainNamespace.sessionItem)")

let expectedAccountItem = "\(expected).account.MTIzNDU2Nzg5MA"
let accountItem = KeychainNamespace.sessionItem(for: "1234567890")
guard accountItem == expectedAccountItem else {
    fputs(
        "FAIL account keychain namespace: got \(accountItem), expected \(expectedAccountItem)\n",
        stderr
    )
    exit(1)
}
print("PASS account keychain namespace: \(expectedAccountItem)")
