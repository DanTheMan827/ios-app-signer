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
    @IBAction func checkForUpdates(sender: NSMenuItem) {
        UpdatesController.checkForUpdate(forceShow: true)
        func updateCheckStatus(status: Bool, data: NSData?, response: NSURLResponse?, error: NSError?){
            if status == false {
                dispatch_async(dispatch_get_main_queue()) {
                    let alert = NSAlert()
                    
                    
                    if error != nil {
                        alert.messageText = "There was a problem checking for a new version."
                        alert.informativeText = "More information is available in the application log."
                        Log.write(error!.localizedDescription)
                    } else {
                        alert.messageText = "You are currently running the latest version."
                    }
                    alert.runModal()
                }
            }
        }
        UpdatesController.checkForUpdate(forceShow: true, callbackFunc: updateCheckStatus)
    }
}

