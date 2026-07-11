import AppKit
import Darwin
import Dispatch
import Foundation

private let backgroundLaunchURL = URL(string: "ar-tecnologica-dockerbridge://background")!
private let configuration = NSWorkspace.OpenConfiguration()

configuration.activates = false
configuration.addsToRecentItems = false
configuration.promptsUserIfNeeded = false

NSWorkspace.shared.open(backgroundLaunchURL, configuration: configuration) { _, error in
    if let error {
        NSLog("Could not open DockerBridge at login: \(error.localizedDescription)")
    }
    exit(EXIT_SUCCESS)
}

dispatchMain()
