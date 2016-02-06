//
//  UpdatesController.swift
//  iOS App Signer
//
//  Created by Daniel Radtke on 2/5/16.
//  Copyright © 2016 Daniel Radtke. All rights reserved.
//

import Foundation
import AppKit
class UpdatesController: NSWindowController {
    //MARK: Variables
    let markdownParser = NSAttributedStringMarkdownParser()
    var latestVersion: String?
    let prefs = NSUserDefaults.standardUserDefaults()
    static var updatesWindow: UpdatesController?
    
    //MARK: IBOutlets
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet var updateWindow: NSWindow!
    @IBOutlet var changelogText: NSTextView!
    @IBOutlet weak var versionLabel: NSTextField!
    
    //MARK: Functions
    static func checkForUpdate(
        currentVersion: String = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as! String,
        forceShow: Bool = false,
        callbackFunc: ((status: Bool, data: NSData?, response: NSURLResponse?, error: NSError?)->Void)? = nil
    ) {
        let requestURL: NSURL = NSURL(string: "https://api.github.com/repos/DanTheMan827/ios-app-signer/releases")!
        let urlRequest: NSMutableURLRequest = NSMutableURLRequest(URL: requestURL)
        
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.requestCachePolicy = .ReloadIgnoringLocalAndRemoteCacheData
        let session = NSURLSession(configuration: configuration)
        
        let task = session.dataTaskWithRequest(urlRequest) {
            (data, response, error) -> Void in
            
            if error == nil {
                let httpResponse = response as! NSHTTPURLResponse
                let statusCode = httpResponse.statusCode
                
                if (statusCode == 200) {
                    do{
                        
                        let json = try NSJSONSerialization.JSONObjectWithData(data!, options:.AllowFragments)
                        if let releases = json as? [[String: AnyObject]],
                            release = releases[0] as? [String: AnyObject],
                            name = release["name"] as? String {
                                let prefs = NSUserDefaults.standardUserDefaults()
                                if let skipVersion = prefs.stringForKey("skipVersion"){
                                    if skipVersion == name && forceShow == false {
                                        return
                                    }
                                }
                                if name != currentVersion {
                                    dispatch_async(dispatch_get_main_queue()) {
                                        // update some UI
                                        if updatesWindow == nil {
                                            updatesWindow = UpdatesController(windowNibName: "Updates")
                                        }
                                        updatesWindow!.showWindow([currentVersion,releases])
                                    }
                                    if let statusFunc = callbackFunc {
                                        statusFunc(status: true, data: data, response: response, error: error)
                                    }
                                } else {
                                    if let statusFunc = callbackFunc {
                                        statusFunc(status: false, data: data, response: response, error: error)
                                    }
                                }
                        }
                    }catch {
                        Log.write("Error with Json: \(error)")
                    }
                } else {
                    if let statusFunc = callbackFunc {
                        statusFunc(status: false, data: data, response: response, error: error)
                    }
                }
            } else {
                if let statusFunc = callbackFunc {
                    statusFunc(status: false, data: data, response: response, error: error)
                }
            }
        }
        
        
        task.resume()
        
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
        
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    override func showWindow(sender: AnyObject?) {
        super.showWindow(sender)
        appIcon.image = NSWorkspace.sharedWorkspace().iconForFile(NSBundle.mainBundle().bundlePath)
        var releaseOutput: [String] = []
        if let releases = sender![1] as? [[String: AnyObject]],
            currentVersion = sender![0] as? String {
            for release in releases {
                if let name = release["name"] as? String,
                    body = release["body"] as? String {
                        if latestVersion == nil {
                            latestVersion = name
                        }
                        if currentVersion == name {
                            break
                        }
                        releaseOutput.append("**Version \(name)**\n\(body)")
                }
            }
            versionLabel.stringValue = "Version \(latestVersion!) is now available, you have \(currentVersion)."
        }
        
        setChangelog(releaseOutput.joinWithSeparator("\n\n"))
    }
    func setChangelog(text: String){
        changelogText.editable = true
        changelogText.string = ""
        changelogText.insertText(markdownParser.attributedStringFromMarkdownString(text))
        changelogText.editable = false
    }
    
    //MARK: IBActions
    @IBAction func skipVersion(sender: NSButton) {
        prefs.setValue(latestVersion, forKey: "skipVersion")
        updateWindow.close()
    }
    @IBAction func remindMeLater(sender: NSButton) {
        prefs.setValue(nil, forKey: "skipVersion")
        updateWindow.close()
    }
    @IBAction func visitProjectPage(sender: NSButton) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "http://dantheman827.github.io/ios-app-signer/")!)
        updateWindow.close()
    }
}