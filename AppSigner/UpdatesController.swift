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
    let prefs = UserDefaults.standard
    static var updatesWindow: UpdatesController?
    
    //MARK: IBOutlets
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet var updateWindow: NSWindow!
    @IBOutlet var changelogText: NSTextView!
    @IBOutlet weak var versionLabel: NSTextField!
    
    //MARK: Functions
    static func checkForUpdate(
        _ currentVersion: String = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String,
        forceShow: Bool = false,
        callbackFunc: ((_ status: Bool, _ data: Data?, _ response: URLResponse?, _ error: Error?)->Void)? = nil
    ) {
        let requestURL: URL = URL(string: "https://api.github.com/repos/DanTheMan827/ios-app-signer/releases")!
        let urlRequest = URLRequest(url: requestURL)
        
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        
        let task = session.dataTask(with: urlRequest, completionHandler: {
            (data, response, error) -> Void in
            
            if error == nil {
                let httpResponse = response as! HTTPURLResponse
                let statusCode = httpResponse.statusCode
                
                if (statusCode == 200) {
                    do{
                        
                        let json = try JSONSerialization.jsonObject(with: data!, options:.allowFragments)
                        if let releases = json as? [[String: AnyObject]],
                            let release = releases[0] as? [String: AnyObject],
                            let name = release["name"] as? String {
                                let prefs = UserDefaults.standard
                                if let skipVersion = prefs.string(forKey: "skipVersion"){
                                    if skipVersion == name && forceShow == false {
                                        return
                                    }
                                }
                                if name != currentVersion {
                                    DispatchQueue.main.async {
                                        // update some UI
                                        if updatesWindow == nil {
                                            updatesWindow = UpdatesController(windowNibName: "Updates")
                                        }
                                        updatesWindow!.showWindow([currentVersion,releases])
                                    }
                                    if let statusFunc = callbackFunc {
                                        statusFunc(true, data, response, error)
                                    }
                                } else {
                                    if let statusFunc = callbackFunc {
                                        statusFunc(false, data, response, error)
                                    }
                                }
                        }
                    }catch {
                        Log.write("Error with Json: \(error)")
                    }
                } else {
                    if let statusFunc = callbackFunc {
                        statusFunc(false, data, response, error)
                    }
                }
            } else {
                if let statusFunc = callbackFunc {
                    statusFunc(false, data, response, error)
                }
            }
        }) 
        
        
        task.resume()
        
    }
    
    override init(window: NSWindow?) {
        super.init(window: window)
        
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        appIcon.image = NSWorkspace.shared().icon(forFile: Bundle.main.bundlePath)
        var releaseOutput: [String] = []
        if let senderArray = sender as? [AnyObject] {
            if let releases = senderArray[1] as? [[String: AnyObject]],
                let currentVersion = senderArray[0] as? String {
                for release in releases {
                    if let name = release["name"] as? String,
                        let body = release["body"] as? String {
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
            setChangelog(releaseOutput.joined(separator: "\n\n"))
        }
        
    }
    func setChangelog(_ text: String){
        changelogText.isEditable = true
        changelogText.string = ""
        changelogText.insertText(markdownParser.attributedString(fromMarkdownString: text))
        changelogText.isEditable = false
    }
    
    //MARK: IBActions
    @IBAction func skipVersion(_ sender: NSButton) {
        prefs.setValue(latestVersion, forKey: "skipVersion")
        updateWindow.close()
    }
    @IBAction func remindMeLater(_ sender: NSButton) {
        prefs.setValue(nil, forKey: "skipVersion")
        updateWindow.close()
    }
    @IBAction func visitProjectPage(_ sender: NSButton) {
        NSWorkspace.shared().open(URL(string: "http://dantheman827.github.io/ios-app-signer/")!)
        updateWindow.close()
    }
}
