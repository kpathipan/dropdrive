//
//  SafariWebExtensionHandler.swift
//  DropDrive Safari Extension Extension
//
//  Created by mac on 13/7/2569 BE.
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        // Handle different message types
        if let messageDict = message as? [String: Any],
           let action = messageDict["action"] as? String {
            handleAction(action, with: messageDict, context: context)
            return
        }

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [ SFExtensionMessageKey: [ "echo": message ] ]
        } else {
            response.userInfo = [ "message": [ "echo": message ] ]
        }

        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }

    // MARK: - Message Handling

    private func handleAction(_ action: String, with message: [String: Any], context: NSExtensionContext) {
        switch action {
        case "downloadFileFromDrive":
            if let urlString = message["url"] as? String {
                openDropDriveApp(with: urlString)
            }
        case "contextMenuClicked":
            if let urlString = message["url"] as? String {
                openDropDriveApp(with: urlString)
            }
        default:
            os_log(.default, "Unknown action: %@", action)
        }

        // Send acknowledgment
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [ SFExtensionMessageKey: [ "success": true ] ]
        } else {
            response.userInfo = [ "message": [ "success": true ] ]
        }
        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }

    private func openDropDriveApp(with driveLink: String) {
        // Construct deep link URL
        let encodedLink = driveLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? driveLink
        guard let deepLinkURL = URL(string: "dropdrive://add?url=\(encodedLink)") else {
            os_log(.error, "Failed to create deep link URL")
            return
        }

        os_log(.default, "Opening DropDrive with URL: %@", deepLinkURL.absoluteString)

        // Open the deep link
        NSWorkspace.shared.open(deepLinkURL) { (application, error) in
            if let error = error {
                os_log(.error, "Failed to open DropDrive: %@", error.localizedDescription)
            } else {
                os_log(.default, "Successfully opened DropDrive")
            }
        }
    }

}
