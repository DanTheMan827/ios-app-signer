//
//  AppDelegate.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let fileManager = NSFileManager.defaultManager()
    
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
        try? fileManager.removeItemAtPath(Log.logName)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication) -> Bool {
        return true
    }

    @IBAction func nsMenuLinkClick(sender: NSMenuLink) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: sender.url!)!)
    }
    @IBAction func viewLog(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openFile(Log.logName)
    }
}

