//
//  AppDelegate.swift
//  LearningMetal
//
//  Created by Yevgen Ostroukhov on 5/3/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let window = NSApplication.shared.windows.first {
//            var frame = window.frame
//            frame.size = NSSize(width: 1200, height: 900)
//            window.setFrame(frame, display: true)
//            window.center()
            let metalView = MetalView(frame: window.contentView!.bounds)
            metalView.autoresizingMask = [.width, .height]
            window.contentView = metalView
            window.setFrameAutosaveName("MetalExperiment")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool
    {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}
