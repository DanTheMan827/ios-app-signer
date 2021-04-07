//
//  ViewController.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa
import Foundation

class MainView: NSView, URLSessionDataDelegate, URLSessionDelegate, URLSessionDownloadDelegate {
    
    //MARK: IBOutlets
    @IBOutlet var ProvisioningProfilesPopup: NSPopUpButton!
    @IBOutlet var CodesigningCertsPopup: NSPopUpButton!
    @IBOutlet var StatusLabel: NSTextField!
    @IBOutlet var InputFileText: NSTextField!
    @IBOutlet var BrowseButton: NSButton!
    @IBOutlet var StartButton: NSButton!
    @IBOutlet var NewApplicationIDTextField: NSTextField!
    @IBOutlet var downloadProgress: NSProgressIndicator!
    @IBOutlet var appDisplayName: NSTextField!
    @IBOutlet var appShortVersion: NSTextField!
    @IBOutlet var appVersion: NSTextField!
    @IBOutlet var ignorePluginsCheckbox: NSButton!
    @IBOutlet var noGetTaskAllowCheckbox: NSButton!

    
    //MARK: Variables
    var provisioningProfiles:[ProvisioningProfile] = []
    @objc var codesigningCerts: [String] = []
    @objc var profileFilename: String?
    @objc var ReEnableNewApplicationID = false
    @objc var PreviousNewApplicationID = ""
    @objc var outputFile: String?
    var startSize: CGFloat?
    @objc var NibLoaded = false
    var shouldCheckPlugins: Bool!
    var shouldSkipGetTaskAllow: Bool!

    //MARK: Constants
    let signableExtensions = ["dylib","so","0","vis","pvr","framework","appex","app"]
    @objc let defaults = UserDefaults()
    @objc let fileManager = FileManager.default
    @objc let bundleID = Bundle.main.bundleIdentifier
    @objc let arPath = "/usr/bin/ar"
    @objc let mktempPath = "/usr/bin/mktemp"
    @objc let tarPath = "/usr/bin/tar"
    @objc let unzipPath = "/usr/bin/unzip"
    @objc let zipPath = "/usr/bin/zip"
    @objc let defaultsPath = "/usr/bin/defaults"
    @objc let codesignPath = "/usr/bin/codesign"
    @objc let securityPath = "/usr/bin/security"
    @objc let chmodPath = "/bin/chmod"
//    let plistbuddyPath = "/usr/libexec/plistbuddy"
    
    //MARK: Drag / Drop
    static let urlFileTypes = ["ipa", "deb"]
    static let allowedFileTypes = urlFileTypes + ["app", "appex", "xcarchive"]
    static let fileTypes = allowedFileTypes + ["mobileprovision"]
    @objc var fileTypeIsOk = false
    
    @objc func fileDropped(_ filename: String){
        switch filename.pathExtension.lowercased() {
        case let ext where MainView.allowedFileTypes.contains(ext):
            InputFileText.stringValue = filename
        case "mobileprovision":
            ProvisioningProfilesPopup.selectItem(at: 1)
            checkProfileID(ProvisioningProfile(filename: filename))
        default:
            break
        }
    }
    
    @objc func urlDropped(_ url: NSURL){
        if let urlString = url.absoluteString {
            InputFileText.stringValue = urlString
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if checkExtension(sender) == true {
            self.fileTypeIsOk = true
            return .copy
        } else {
            self.fileTypeIsOk = false
            return NSDragOperation()
        }
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if self.fileTypeIsOk {
            return .copy
        } else {
            return NSDragOperation()
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let board = pasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray {
            if let filePath = board[0] as? String {
                
                fileDropped(filePath)
                return true
            }
        }
        if let types = pasteboard.types {
            if types.contains(NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")) {
                if let url = NSURL(from: pasteboard) {
                    urlDropped(url)
                }
            }
        }
        return false
    }
    
    @objc func checkExtension(_ drag: NSDraggingInfo) -> Bool {
        if let board = drag.draggingPasteboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? NSArray,
            let path = board[0] as? String {
                return MainView.fileTypes.contains(path.pathExtension.lowercased())
        }
        if let types = drag.draggingPasteboard.types {
            if types.contains(NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")) {
                if let url = NSURL(from: drag.draggingPasteboard),
                    let suffix = url.pathExtension {
                        return MainView.urlFileTypes.contains(suffix.lowercased())
                }
            }
        }
        return false
    }
    
    //MARK: Functions
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType"), NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType"), NSPasteboard.PasteboardType(rawValue: "NSURLPboardType")])
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        
        if NibLoaded == false {
            NibLoaded = true
            
            // Do any additional setup after loading the view.
            populateProvisioningProfiles()
            populateCodesigningCerts()
            if let defaultCert = defaults.string(forKey: "signingCertificate") {
                if codesigningCerts.contains(defaultCert) {
                    Log.write("Loaded Codesigning Certificate from Defaults: \(defaultCert)")
                    CodesigningCertsPopup.selectItem(withTitle: defaultCert)
                }
            }
            setStatus("Ready")
            if checkXcodeCLI() == false {
                if #available(OSX 10.10, *) {
                    let _ = installXcodeCLI()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Please install the Xcode command line tools and re-launch this application."
                    alert.runModal()
                }
                
                NSApplication.shared.terminate(self)
            }
            UpdatesController.checkForUpdate()
        }
    }
    
    func installXcodeCLI() -> AppSignerTaskOutput {
        return Process().execute("/usr/bin/xcode-select", workingDirectory: nil, arguments: ["--install"])
    }
    
    @objc func checkXcodeCLI() -> Bool {
        if #available(OSX 10.10, *) {
            if Process().execute("/usr/bin/xcode-select", workingDirectory: nil, arguments: ["-p"]).status   != 0 {
                return false
            }
        } else {
            if Process().execute("/usr/sbin/pkgutil", workingDirectory: nil, arguments: ["--pkg-info=com.apple.pkg.DeveloperToolsCLI"]).status != 0 {
                // Command line tools not available
                return false
            }
        }
        
        return true
    }
    
    @objc func makeTempFolder()->String?{
        let tempTask = Process().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID!])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    @objc func setStatus(_ status: String){
        if (!Thread.isMainThread){
            DispatchQueue.main.sync{
                setStatus(status)
            }
        }
        else{
            StatusLabel.stringValue = status
            Log.write(status)
        }
    }
    
    @objc func populateProvisioningProfiles(){
        let zeroWidthSpace = "​"
        self.provisioningProfiles = ProvisioningProfile.getProfiles().sorted {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        setStatus("Found \(provisioningProfiles.count) Provisioning Profile\(provisioningProfiles.count>1 || provisioningProfiles.count<1 ? "s":"")")
        ProvisioningProfilesPopup.removeAllItems()
        ProvisioningProfilesPopup.addItems(withTitles: [
            "Re-Sign Only",
            "Choose Custom File",
            "––––––––––––––––––––––"
        ])
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        var newProfiles: [ProvisioningProfile] = []
        var zeroWidthPadding: String = ""
        for profile in provisioningProfiles {
            zeroWidthPadding = "\(zeroWidthPadding)\(zeroWidthSpace)"
            if profile.expires.timeIntervalSince1970 > Date().timeIntervalSince1970 {
                newProfiles.append(profile)
                
                ProvisioningProfilesPopup.addItem(withTitle: "\(profile.name)\(zeroWidthPadding) (\(profile.teamID))")
                
                let toolTipItems = [
                    "\(profile.name)",
                    "",
                    "Team ID: \(profile.teamID)",
                    "Created: \(formatter.string(from: profile.created as Date))",
                    "Expires: \(formatter.string(from: profile.expires as Date))"
                ]
                ProvisioningProfilesPopup.lastItem!.toolTip = toolTipItems.joined(separator: "\n")
                setStatus("Added profile \(profile.appID), expires (\(formatter.string(from: profile.expires as Date)))")
            } else {
                setStatus("Skipped profile \(profile.appID), expired (\(formatter.string(from: profile.expires as Date)))")
            }
        }
        self.provisioningProfiles = newProfiles
        chooseProvisioningProfile(ProvisioningProfilesPopup)
    }
    
    @objc func getCodesigningCerts() -> [String] {
        var output: [String] = []
        let securityResult = Process().execute(securityPath, workingDirectory: nil, arguments: ["find-identity","-v","-p","codesigning"])
        if securityResult.output.count < 1 {
            return output
        }
        let rawResult = securityResult.output.components(separatedBy: "\"")
        
        var index: Int
        
        for index in stride(from: 0, through: rawResult.count - 2, by: 2) {
            if !(rawResult.count - 1 < index + 1) {
                output.append(rawResult[index+1])
            }
        }
        return output.sorted()
    }
    
    @objc func showCodesignCertsErrorAlert(){
        let alert = NSAlert()
        alert.messageText = "No codesigning certificates found"
        alert.informativeText = "I can attempt to fix this automatically, would you like me to try?"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
            if let tempFolder = makeTempFolder() {
                iASShared.fixSigning(tempFolder)
                try? fileManager.removeItem(atPath: tempFolder)
                populateCodesigningCerts()
            }
        }
    }
    
    @objc func populateCodesigningCerts() {
        CodesigningCertsPopup.removeAllItems()
        self.codesigningCerts = getCodesigningCerts()
        
        setStatus("Found \(self.codesigningCerts.count) Codesigning Certificate\(self.codesigningCerts.count>1 || self.codesigningCerts.count<1 ? "s":"")")
        if self.codesigningCerts.count > 0 {
            for cert in self.codesigningCerts {
                CodesigningCertsPopup.addItem(withTitle: cert)
                setStatus("Added signing certificate \"\(cert)\"")
            }
        } else {
            showCodesignCertsErrorAlert()
        }
        
    }
    
    func checkProfileID(_ profile: ProvisioningProfile?){
        if let profile = profile {
            self.profileFilename = profile.filename
            setStatus("Selected provisioning profile \(profile.appID)")
            if profile.expires.timeIntervalSince1970 < Date().timeIntervalSince1970 {
                ProvisioningProfilesPopup.selectItem(at: 0)
                setStatus("Provisioning profile expired")
                chooseProvisioningProfile(ProvisioningProfilesPopup)
            }
            if profile.appID.firstIndex(of: "*") == nil {
                // Not a wildcard profile
                NewApplicationIDTextField.stringValue = profile.appID
                NewApplicationIDTextField.isEnabled = false
            } else {
                // Wildcard profile
                if NewApplicationIDTextField.isEnabled == false {
                    NewApplicationIDTextField.stringValue = ""
                    NewApplicationIDTextField.isEnabled = true
                }
            }
        } else {
            ProvisioningProfilesPopup.selectItem(at: 0)
            setStatus("Invalid provisioning profile")
            chooseProvisioningProfile(ProvisioningProfilesPopup)
        }
    }
    
    @objc func controlsEnabled(_ enabled: Bool){
        
        if (!Thread.isMainThread){
            DispatchQueue.main.sync{
                controlsEnabled(enabled)
            }
        }
        else{
            if(enabled){
                InputFileText.isEnabled = true
                BrowseButton.isEnabled = true
                ProvisioningProfilesPopup.isEnabled = true
                CodesigningCertsPopup.isEnabled = true
                NewApplicationIDTextField.isEnabled = ReEnableNewApplicationID
                NewApplicationIDTextField.stringValue = PreviousNewApplicationID
                StartButton.isEnabled = true
                appDisplayName.isEnabled = true
            } else {
                // Backup previous values
                PreviousNewApplicationID = NewApplicationIDTextField.stringValue
                ReEnableNewApplicationID = NewApplicationIDTextField.isEnabled
                
                InputFileText.isEnabled = false
                BrowseButton.isEnabled = false
                ProvisioningProfilesPopup.isEnabled = false
                CodesigningCertsPopup.isEnabled = false
                NewApplicationIDTextField.isEnabled = false
                StartButton.isEnabled = false
                appDisplayName.isEnabled = false
            }
        }
    }
    
    @objc func recursiveDirectorySearch(_ path: String, extensions: [String], found: ((_ file: String) -> Void)){
        
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    if file.pathExtension != "" || file == "IpaSecurityRestriction" {
                        found(currentFile)
                    } else {
                        //NSLog("couldnt find: %@", file)
                    }
                } else if isDirectory.boolValue == false && checkMachOFile(currentFile) {
                    found(currentFile)
                }
                
            }
        }
    }

    func allowRecursiveSearchAt(_ path: String) -> Bool {
        return shouldCheckPlugins || path.lastPathComponent != "PlugIns"
    }
    
    /// check if Mach-O file
    @objc func checkMachOFile(_ path: String) -> Bool {
        if let file = FileHandle(forReadingAtPath: path) {
            let data = file.readData(ofLength: 4)
            file.closeFile()
            var machOFile = data.elementsEqual([0xCE, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCF, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCA, 0xFE, 0xBA, 0xBE])
            
            if machOFile == false && signableExtensions.contains(path.lastPathComponent.pathExtension.lowercased()) {
                Log.write("Detected binary by extension: \(path)")
                machOFile = true
            }
            return machOFile
        }
        return false
    }
    
    func unzip(_ inputFile: String, outputPath: String)->AppSignerTaskOutput {
        return Process().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    func zip(_ inputPath: String, outputFile: String)->AppSignerTaskOutput {
        return Process().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    @objc func cleanup(_ tempFolder: String){
        do {
            Log.write("Deleting: \(tempFolder)")
            try fileManager.removeItem(atPath: tempFolder)
        } catch let error as NSError {
            setStatus("Unable to delete temp folder")
            Log.write(error.localizedDescription)
        }
        controlsEnabled(true)
    }
    @objc func bytesToSmallestSi(_ size: Double) -> String {
        let prefixes = ["","K","M","G","T","P","E","Z","Y"]
        for i in 1...6 {
            let nextUnit = pow(1024.00, Double(i+1))
            let unitMax = pow(1024.00, Double(i))
            if size < nextUnit {
                return "\(round((size / unitMax)*100)/100)\(prefixes[i])B"
            }
            
        }
        return "\(size)B"
    }
    @objc func getPlistKey(_ plist: String, keyName: String)->String? {
        let dictionary = NSDictionary(contentsOfFile: plist);
        return dictionary?[keyName] as? String
    }
    
    func setPlistKey(_ plist: String, keyName: String, value: String)->AppSignerTaskOutput {
        return Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }
    
    //MARK: NSURL Delegate
    @objc var downloading = false
    @objc var downloadError: NSError?
    @objc var downloadPath: String!
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        downloadError = downloadTask.error as NSError?
        if downloadError == nil {
            do {
                try fileManager.moveItem(at: location, to: URL(fileURLWithPath: downloadPath))
            } catch let error as NSError {
                setStatus("Unable to move downloaded file")
                Log.write(error.localizedDescription)
            }
        }
        downloading = false
        downloadProgress.doubleValue = 0.0
        downloadProgress.stopAnimation(nil)
        DispatchQueue.main.async {
            self.downloadProgress.isHidden = true
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        //StatusLabel.stringValue = "Downloading file: \(bytesToSmallestSi(Double(totalBytesWritten))) / \(bytesToSmallestSi(Double(totalBytesExpectedToWrite)))"
        let percentDownloaded = (Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100
        downloadProgress.doubleValue = percentDownloaded
    }
    
    //MARK: Codesigning
    @discardableResult
    func codeSign(_ file: String, certificate: String, entitlements: String?,before:((_ file: String, _ certificate: String, _ entitlements: String?)->Void)?, after: ((_ file: String, _ certificate: String, _ entitlements: String?, _ codesignTask: AppSignerTaskOutput)->Void)?)->AppSignerTaskOutput{

        var needEntitlements: Bool = false
        let filePath: String
        switch file.pathExtension.lowercased() {
        case "framework":
            // append executable file in framework
            let fileName = file.lastPathComponent.stringByDeletingPathExtension
            filePath = file.stringByAppendingPathComponent(fileName)
        case "app", "appex":
            // read executable file from Info.plist
            let infoPlist = file.stringByAppendingPathComponent("Info.plist")
            let executableFile = getPlistKey(infoPlist, keyName: "CFBundleExecutable")!
            filePath = file.stringByAppendingPathComponent(executableFile)

            if let entitlementsPath = entitlements, fileManager.fileExists(atPath: entitlementsPath) {
                needEntitlements = true
            }
        default:
            filePath = file
        }

        if let beforeFunc = before {
            beforeFunc(file, certificate, entitlements)
        }

        var arguments = ["-f", "-s", certificate]
        if needEntitlements {
            arguments += ["--entitlements", entitlements!]
        }
        arguments.append(filePath)

        let codesignTask = Process().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if codesignTask.status != 0 {
            Log.write("Error codesign: \(codesignTask.output)")
        }
        
        if let afterFunc = after {
            afterFunc(file, certificate, entitlements, codesignTask)
        }
        return codesignTask
    }
    func testSigning(_ certificate: String, tempFolder: String )->Bool? {
        let codesignTempFile = tempFolder.stringByAppendingPathComponent("test-sign")
        
        // Copy our binary to the temp folder to use for testing.
        let path = ProcessInfo.processInfo.arguments[0]
        if (try? fileManager.copyItem(atPath: path, toPath: codesignTempFile)) != nil {
            codeSign(codesignTempFile, certificate: certificate, entitlements: nil, before: nil, after: nil)
            
            let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",codesignTempFile])
            try? fileManager.removeItem(atPath: codesignTempFile)
            if verificationTask.status == 0 {
                Log.write("Error testing codesign: \(verificationTask.output)")
                return true
            } else {
                return false
            }
        } else {
            setStatus("Error testing codesign")
        }
        return nil
    }
    
    @objc func startSigning() {
        let inputFile = InputFileText.stringValue
        if inputFile.pathExtension.lowercased() == "appex" {
            outputFile = inputFile
        } else {
            //MARK: Get output filename
            let saveDialog = NSSavePanel()
            saveDialog.allowedFileTypes = ["ipa"]
            saveDialog.nameFieldStringValue = inputFile.lastPathComponent.stringByDeletingPathExtension
            if saveDialog.runModal().rawValue == NSFileHandlingPanelOKButton {
                outputFile = saveDialog.url!.path
            } else {
                outputFile = nil
            }
        }
        if outputFile != nil {
            controlsEnabled(false)
            Thread.detachNewThreadSelector(#selector(self.signingThread), toTarget: self, with: nil)
        }
    }
    
    @objc func signingThread(){
        
        
        //MARK: Set up variables
        var warnings = 0
        var inputFile : String = ""
        var signingCertificate : String?
        var newApplicationID : String = ""
        var newDisplayName : String = ""
        var newShortVersion : String = ""
        var newVersion : String = ""

        DispatchQueue.main.sync {
            downloadProgress.isHidden = true
            inputFile = self.InputFileText.stringValue
            signingCertificate = self.CodesigningCertsPopup.selectedItem?.title
            newApplicationID = self.NewApplicationIDTextField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newDisplayName = self.appDisplayName.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newShortVersion = self.appShortVersion.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            newVersion = self.appVersion.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            shouldCheckPlugins = ignorePluginsCheckbox.state == .off
            shouldSkipGetTaskAllow = noGetTaskAllowCheckbox.state == .on
        }

        var provisioningFile = self.profileFilename
        let inputStartsWithHTTP = inputFile.lowercased().substring(to: inputFile.index(inputFile.startIndex, offsetBy: 4)) == "http"
        var eggCount: Int = 0
        var continueSigning: Bool? = nil
        
        //MARK: Sanity checks
        
        // Check signing certificate selection
        if signingCertificate == nil {
            setStatus("No signing certificate selected")
            return
        }
        
        // Check if input file exists
        var inputIsDirectory: ObjCBool = false
        if !inputStartsWithHTTP && !fileManager.fileExists(atPath: inputFile, isDirectory: &inputIsDirectory){
            DispatchQueue.main.async(execute: {
                let alert = NSAlert()
                alert.messageText = "Input file not found"
                alert.addButton(withTitle: "OK")
                alert.informativeText = "The file \(inputFile) could not be found"
                alert.runModal()
                self.controlsEnabled(true)
            })
            return
        }
        
        //MARK: Create working temp folder
        var tempFolder: String! = nil
        if let tmpFolder = makeTempFolder() {
            tempFolder = tmpFolder
        } else {
            setStatus("Error creating temp folder")
            return
        }
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        let eggDirectory = tempFolder.stringByAppendingPathComponent("eggs")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        
        Log.write("Temp folder: \(tempFolder)")
        Log.write("Working directory: \(workingDirectory)")
        Log.write("Payload directory: \(payloadDirectory)")
        
        //MARK: Codesign Test
        
        DispatchQueue.main.async(execute: {
            if let codesignResult = self.testSigning(signingCertificate!, tempFolder: tempFolder) {
                if codesignResult == false {
                    let alert = NSAlert()
                    alert.messageText = "Codesigning error"
                    alert.addButton(withTitle: "Yes")
                    alert.addButton(withTitle: "No")
                    alert.informativeText = "You appear to have a error with your codesigning certificate, do you want me to try and fix the problem?"
                    let response = alert.runModal()
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        iASShared.fixSigning(tempFolder)
                        if self.testSigning(signingCertificate!, tempFolder: tempFolder) == false {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Unable to Fix"
                            errorAlert.addButton(withTitle: "OK")
                            errorAlert.informativeText = "I was unable to automatically resolve your codesigning issue ☹\n\nIf you have previously trusted your certificate using Keychain, please set the Trust setting back to the system default."
                            errorAlert.runModal()
                            continueSigning = false
                            return
                        }
                    } else {
                        continueSigning = false
                        return
                    }
                }
            }
            continueSigning = true
        })
        
        
        while true {
            if continueSigning != nil {
                if continueSigning! == false {
                    continueSigning = nil
                    cleanup(tempFolder); return
                }
                break
            }
            usleep(100)
        }
        
        //MARK: Create Egg Temp Directory
        do {
            try fileManager.createDirectory(atPath: eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            setStatus("Error creating egg temp directory")
            Log.write(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Download file
        downloading = false
        downloadError = nil
        downloadPath = tempFolder.stringByAppendingPathComponent("download.\(inputFile.pathExtension)")
        
        if inputStartsWithHTTP {
            let defaultConfigObject = URLSessionConfiguration.default
            let defaultSession = Foundation.URLSession(configuration: defaultConfigObject, delegate: self, delegateQueue: OperationQueue.main)
            if let url = URL(string: inputFile) {
                downloading = true
                
                let downloadTask = defaultSession.downloadTask(with: url)
                setStatus("Downloading file")
                DispatchQueue.main.async {
                    self.downloadProgress.isHidden = false
                }
                downloadProgress.startAnimation(nil)
                downloadTask.resume()
                defaultSession.finishTasksAndInvalidate()
            }
            
            while downloading {
                usleep(100000)
            }
            if downloadError != nil {
                setStatus("Error downloading file, \(downloadError!.localizedDescription.lowercased())")
                cleanup(tempFolder); return
            } else {
                inputFile = downloadPath
            }
        }
        
        //MARK: Process input file
        switch(inputFile.pathExtension.lowercased()){
        case "deb":
            //MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectory(atPath: debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting deb file")
                let debTask = Process().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Log.write(debTask.output)
                if debTask.status != 0 {
                    setStatus("Error processing deb file")
                    cleanup(tempFolder); return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExists(atPath: dataPath){
                        
                        setStatus("Unpacking data.\(tarFormat)")
                        let tarTask = Process().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
                        Log.write(tarTask.output)
                        if tarTask.status == 0 {
                            tarUnpacked = true
                        }
                        break
                    }
                }
                if !tarUnpacked {
                    setStatus("Error unpacking data.tar")
                    cleanup(tempFolder); return
                }
              
              var sourcePath = debPath.stringByAppendingPathComponent("Applications")
              if fileManager.fileExists(atPath: debPath.stringByAppendingPathComponent("var/mobile/Applications")){
                  sourcePath = debPath.stringByAppendingPathComponent("var/mobile/Applications")
              }
              
              try fileManager.moveItem(atPath: sourcePath, toPath: payloadDirectory)
                
            } catch {
                setStatus("Error processing deb file")
                cleanup(tempFolder); return
            }
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting ipa file")
                
                let unzipTask = self.unzip(inputFile, outputPath: workingDirectory)
                if unzipTask.status != 0 {
                    setStatus("Error extracting ipa file")
                    cleanup(tempFolder); return
                }
            } catch {
                setStatus("Error extracting ipa file")
                cleanup(tempFolder); return
            }
            
        case "app", "appex":
            //MARK: --Copy app bundle
            if !inputIsDirectory.boolValue {
                setStatus("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        case "xcarchive":
            //MARK: --Copy app bundle from xcarchive
            if !inputIsDirectory.boolValue {
                setStatus("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        default:
            setStatus("Unsupported input file")
            cleanup(tempFolder); return
        }
        
        if !fileManager.fileExists(atPath: payloadDirectory){
            setStatus("Payload directory doesn't exist")
            cleanup(tempFolder); return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectory(atPath: payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExists(atPath: payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory.boolValue { continue }
                
                //MARK: Bundle variables setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExists(atPath: appBundleProvisioningFilePath))
                
                //MARK: Delete CFBundleResourceSpecification from Info.plist
                Log.write(Process().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                //MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExists(atPath: appBundleProvisioningFilePath) {
                        setStatus("Deleting embedded.mobileprovision")
                        do {
                            try fileManager.removeItem(atPath: appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            setStatus("Error deleting embedded.mobileprovision")
                            Log.write(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    setStatus("Copying provisioning profile to app bundle")
                    do {
                        try fileManager.copyItem(atPath: provisioningFile!, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        setStatus("Error copying provisioning profile")
                        Log.write(error.localizedDescription)
                        cleanup(tempFolder); return
                    }
                }
                
                let bundleID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier")
                
                //MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    setStatus("Parsing entitlements")
                    
                    if var profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if shouldSkipGetTaskAllow {
                            profile.removeGetTaskAllow()
                        }
                        let isWildcard = profile.appID == "*" // TODO: support com.example.* wildcard
                        if !isWildcard && (newApplicationID != "" && newApplicationID != profile.appID) {
                            setStatus("Unable to change App ID to \(newApplicationID), provisioning profile won't allow it")
                            cleanup(tempFolder); return
                        } else if isWildcard {
                            if newApplicationID != "" {
                                profile.update(trueAppID: newApplicationID)
                            } else if let existingBundleID = bundleID {
                                profile.update(trueAppID: existingBundleID)
                            }
                        }
                        if let entitlements = profile.getEntitlementsPlist() {
                            Log.write("–––––––––––––––––––––––\n\(entitlements)")
                            Log.write("–––––––––––––––––––––––")
                            do {
                                try entitlements.write(toFile: entitlementsPlist, atomically: false, encoding: .utf8)
                                setStatus("Saved entitlements to \(entitlementsPlist)")
                            } catch let error as NSError {
                                setStatus("Error writing entitlements.plist, \(error.localizedDescription)")
                            }
                        } else {
                            setStatus("Unable to read entitlements from provisioning profile")
                            warnings += 1
                        }
                    } else {
                        setStatus("Unable to parse provisioning profile, it may be corrupt")
                        warnings += 1
                    }
                    
                }
                
                //MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable"){
                    _ = Process().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                //MARK: Change Application ID
                if newApplicationID != "" {
                    
                    if let oldAppID = bundleID {
                        func changeAppexID(_ appexFile: String){
                            guard allowRecursiveSearchAt(appexFile.stringByDeletingLastPathComponent) else {
                                return
                            }

                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newApplicationID)\(appexBundleID.substring(from: oldAppID.endIndex))"
                                setStatus("Changing \(appexFile) id to \(newAppexID)")
                                _ = setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                _ = setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
                            }
                            // 修复微信改bundleid后安装失败问题
                            let pluginInfoPlist = NSMutableDictionary(contentsOfFile: appexPlist)
                            if let dictionaryArray = pluginInfoPlist?["NSExtension"] as? [String:AnyObject],
                                let attributes : NSMutableDictionary = dictionaryArray["NSExtensionAttributes"] as? NSMutableDictionary,
                                let wkAppBundleIdentifier = attributes["WKAppBundleIdentifier"] as? String{
                                let newAppesID = wkAppBundleIdentifier.replacingOccurrences(of:oldAppID, with:newApplicationID);
                                attributes["WKAppBundleIdentifier"] = newAppesID;
                                pluginInfoPlist!.write(toFile: appexPlist, atomically: true);
                            }
                            recursiveDirectorySearch(appexFile, extensions: ["app"], found: changeAppexID)
                        }
                        recursiveDirectorySearch(appBundlePath, extensions: ["appex"], found: changeAppexID)
                    }
                    
                    setStatus("Changing App ID to \(newApplicationID)")
                    let IDChangeTask = setPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier", value: newApplicationID)
                    if IDChangeTask.status != 0 {
                        setStatus("Error changing App ID")
                        Log.write(IDChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Display Name
                if newDisplayName != "" {
                    setStatus("Changing Display Name to \(newDisplayName))")
                    let displayNameChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        setStatus("Error changing display name")
                        Log.write(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Version
                if newVersion != "" {
                    setStatus("Changing Version to \(newVersion)")
                    let versionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleVersion", newVersion])
                    if versionChangeTask.status != 0 {
                        setStatus("Error changing version")
                        Log.write(versionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Short Version
                if newShortVersion != "" {
                    setStatus("Changing Short Version to \(newShortVersion)")
                    let shortVersionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleShortVersionString", newShortVersion])
                    if shortVersionChangeTask.status != 0 {
                        setStatus("Error changing short version")
                        Log.write(shortVersionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                
                func generateFileSignFunc(_ payloadDirectory:String, entitlementsPath: String, signingCertificate: String)->((_ file:String)->Void){
                    
                    
                    let useEntitlements: Bool = ({
                        if fileManager.fileExists(atPath: entitlementsPath) {
                            return true
                        }
                        return false
                    })()
                    
                    func shortName(_ file: String, payloadDirectory: String)->String{
                        return file.substring(from: payloadDirectory.endIndex)
                    }
                    
                    func beforeFunc(_ file: String, certificate: String, entitlements: String?){
                            setStatus("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements":"")")
                    }
                    
                    func afterFunc(_ file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput){
                        if codesignOutput.status != 0 {
                            setStatus("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            Log.write(codesignOutput.output)
                            warnings += 1
                        }
                    }
                    
                    func output(_ file:String){
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    return output
                }
                
                //MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                func signEgg(_ eggFile: String){
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substring(from: payloadDirectory.endIndex)
                    setStatus("Extracting \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Log.write("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    setStatus("Compressing \(shortName)")
                    _ = self.zip(currentEggPath, outputFile: eggFile)                    
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                //MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(appBundlePath)
                
                //MARK: Codesigning - Verification
                let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
                if verificationTask.status != 0 {
                    DispatchQueue.main.async(execute: {
                        let alert = NSAlert()
                        alert.addButton(withTitle: "OK")
                        alert.messageText = "Error verifying code signature!"
                        alert.informativeText = verificationTask.output
                        alert.alertStyle = .critical
                        alert.runModal()
                        self.setStatus("Error verifying code signature")
                        Log.write(verificationTask.output)
                        self.cleanup(tempFolder); return
                    })
                }
            }
        } catch let error as NSError {
            setStatus("Error listing files in payload directory")
            Log.write(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Packaging
        //Check if output already exists and delete if so
        if fileManager.fileExists(atPath: outputFile!) {
            do {
                try fileManager.removeItem(atPath: outputFile!)
            } catch let error as NSError {
                setStatus("Error deleting output file")
                Log.write(error.localizedDescription)
                cleanup(tempFolder)
                return
            }
        }

        switch outputFile?.pathExtension.lowercased() {
        case "ipa":
            setStatus("Packaging IPA")
            let zipTask = self.zip(workingDirectory, outputFile: outputFile!)
            if zipTask.status != 0 {
                setStatus("Error packaging IPA")
            }
        case "appex":
            do {
                try fileManager.copyItem(atPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent), toPath: outputFile!)
            } catch let error as NSError {
                setStatus("Error copying appex bundle to \(outputFile!)")
                Log.write(error.localizedDescription)
            }
        default:
            break
        }

        //MARK: Cleanup
        cleanup(tempFolder)
        setStatus("Done, output at \(outputFile!)")
    }

    //MARK: IBActions
    @IBAction func chooseProvisioningProfile(_ sender: NSPopUpButton) {
        
        switch(sender.indexOfSelectedItem){
        case 0:
            self.profileFilename = nil
            if NewApplicationIDTextField.isEnabled == false {
                NewApplicationIDTextField.isEnabled = true
                NewApplicationIDTextField.stringValue = ""
            }
            
        case 1:
            let openDialog = NSOpenPanel()
            openDialog.canChooseFiles = true
            openDialog.canChooseDirectories = false
            openDialog.allowsMultipleSelection = false
            openDialog.allowsOtherFileTypes = false
            openDialog.allowedFileTypes = ["mobileprovision"]
            openDialog.runModal()
            if let filename = openDialog.urls.first {
                checkProfileID(ProvisioningProfile(filename: filename.path))
            } else {
                sender.selectItem(at: 0)
                chooseProvisioningProfile(sender)
            }
            
        case 2:
            sender.selectItem(at: 0)
            chooseProvisioningProfile(sender)
            
        default:
            let profile = provisioningProfiles[sender.indexOfSelectedItem - 3]
            checkProfileID(profile)
        }
        
    }
    @IBAction func doBrowse(_ sender: AnyObject) {
        let openDialog = NSOpenPanel()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = MainView.allowedFileTypes + MainView.allowedFileTypes.map({ $0.uppercased() })
        openDialog.runModal()
        if let filename = openDialog.urls.first {
            InputFileText.stringValue = filename.path
        }
    }
    @IBAction func chooseSigningCertificate(_ sender: NSPopUpButton) {
        Log.write("Set Codesigning Certificate Default to: \(sender.stringValue)")
        defaults.setValue(sender.selectedItem?.title, forKey: "signingCertificate")
    }
    
    @IBAction func doSign(_ sender: NSButton) {
        if codesigningCerts.count > 0 {
            NSApplication.shared.windows[0].makeFirstResponder(self)
            startSigning()
        } else {
            showCodesignCertsErrorAlert()
        }
    }
    
    @IBAction func statusLabelClick(_ sender: NSButton) {
        if let outputFile = self.outputFile {
            if fileManager.fileExists(atPath: outputFile) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputFile)])
            }
        }
    }
    
}

