//
//  ViewController.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa

class MainView: NSView, NSURLSessionDataDelegate, NSURLSessionDelegate, NSURLSessionDownloadDelegate {
    
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
    
    
    //MARK: Variables
    var provisioningProfiles:[ProvisioningProfile] = []
    var codesigningCerts: [String] = []
    var profileFilename: String?
    var ReEnableNewApplicationID = false
    var PreviousNewApplicationID = ""
    var outputFile: String?
    var startSize: CGFloat?
    var NibLoaded = false
    
    //MARK: Constants
    let defaults = NSUserDefaults()
    let fileManager = NSFileManager.defaultManager()
    let bundleID = NSBundle.mainBundle().bundleIdentifier
    let arPath = "/usr/bin/ar"
    let mktempPath = "/usr/bin/mktemp"
    let tarPath = "/usr/bin/tar"
    let unzipPath = "/usr/bin/unzip"
    let zipPath = "/usr/bin/zip"
    let defaultsPath = "/usr/bin/defaults"
    let codesignPath = "/usr/bin/codesign"
    let securityPath = "/usr/bin/security"
    let chmodPath = "/bin/chmod"
    
    //MARK: Drag / Drop
    var fileTypes: [String] = ["ipa","deb","app","xcarchive","mobileprovision"]
    var urlFileTypes: [String] = ["ipa","deb"]
    var fileTypeIsOk = false
    
    func fileDropped(filename: String){
        switch(filename.pathExtension.lowercaseString){
        case "ipa", "deb", "app", "xcarchive":
            InputFileText.stringValue = filename
            break
            
        case "mobileprovision":
            ProvisioningProfilesPopup.selectItemAtIndex(1)
            checkProfileID(ProvisioningProfile(filename: filename))
            break
        default: break
            
        }
    }
    
    func urlDropped(url: NSURL){
        InputFileText.stringValue = url.absoluteString
    }
    
    override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
        if checkExtension(sender) == true {
            self.fileTypeIsOk = true
            return .Copy
        } else {
            self.fileTypeIsOk = false
            return .None
        }
    }
    
    override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
        if self.fileTypeIsOk {
            return .Copy
        } else {
            return .None
        }
    }
    
    override func performDragOperation(sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard()
        if let board = pasteboard.propertyListForType("NSFilenamesPboardType") as? NSArray {
            if let filePath = board[0] as? String {
                
                fileDropped(filePath)
                return true
            }
        }
        if let types = pasteboard.types {
            if types.contains(NSURLPboardType) {
                if let url = NSURL(fromPasteboard: pasteboard) {
                    urlDropped(url)
                }
            }
        }
        return false
    }
    
    func checkExtension(drag: NSDraggingInfo) -> Bool {
        if let board = drag.draggingPasteboard().propertyListForType("NSFilenamesPboardType") as? NSArray,
            let path = board[0] as? String {
                return self.fileTypes.contains(path.pathExtension.lowercaseString)
        }
        if let types = drag.draggingPasteboard().types {
            if types.contains(NSURLPboardType) {
                if let url = NSURL(fromPasteboard: drag.draggingPasteboard()),
                    suffix = url.pathExtension {
                        return self.urlFileTypes.contains(suffix.lowercaseString)
                }
            }
        }
        return false
    }
    
    //MARK: Functions
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSFilenamesPboardType, NSURLPboardType])
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([NSFilenamesPboardType, NSURLPboardType])
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        
        if NibLoaded == false {
            NibLoaded = true
            
            // Do any additional setup after loading the view.
            populateProvisioningProfiles()
            populateCodesigningCerts()
            if let defaultCert = defaults.stringForKey("signingCertificate") {
                if codesigningCerts.contains(defaultCert) {
                    Log.write("Loaded Codesigning Certificate from Defaults: \(defaultCert)")
                    CodesigningCertsPopup.selectItemWithTitle(defaultCert)
                }
            }
            setStatus("Ready")
            UpdatesController.checkForUpdate()
        }
    }
    
    func makeTempFolder()->String?{
        let tempTask = NSTask().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID!])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
    }
    
    func setStatus(status: String){
        Log.write(status)
        StatusLabel.stringValue = status
    }
    
    func populateProvisioningProfiles(){
        let zeroWidthSpace = "​"
        self.provisioningProfiles = ProvisioningProfile.getProfiles().sort {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        setStatus("Found \(provisioningProfiles.count) Provisioning Profile\(provisioningProfiles.count>1 || provisioningProfiles.count<1 ? "s":"")")
        ProvisioningProfilesPopup.removeAllItems()
        ProvisioningProfilesPopup.addItemsWithTitles([
            "Re-Sign Only",
            "Choose Custom File",
            "––––––––––––––––––––––"
        ])
        let formatter = NSDateFormatter()
        formatter.dateStyle = .ShortStyle
        formatter.timeStyle = .MediumStyle
        var newProfiles: [ProvisioningProfile] = []
        var zeroWidthPadding: String = ""
        for profile in provisioningProfiles {
            zeroWidthPadding = "\(zeroWidthPadding)\(zeroWidthSpace)"
            if profile.expires.timeIntervalSince1970 > NSDate().timeIntervalSince1970 {
                newProfiles.append(profile)
                
                ProvisioningProfilesPopup.addItemWithTitle("\(profile.name)\(zeroWidthPadding) (\(profile.teamID))")
                
                let toolTipItems = [
                    "\(profile.name)",
                    "",
                    "Team ID: \(profile.teamID)",
                    "Created: \(formatter.stringFromDate(profile.created))",
                    "Expires: \(formatter.stringFromDate(profile.expires))"
                ]
                ProvisioningProfilesPopup.lastItem!.toolTip = toolTipItems.joinWithSeparator("\n")
                setStatus("Added profile \(profile.appID), expires (\(formatter.stringFromDate(profile.expires)))")
            } else {
                setStatus("Skipped profile \(profile.appID), expired (\(formatter.stringFromDate(profile.expires)))")
            }
        }
        self.provisioningProfiles = newProfiles
        chooseProvisioningProfile(ProvisioningProfilesPopup)
    }
    
    func getCodesigningCerts() -> [String] {
        var output: [String] = []
        let securityResult = NSTask().execute(securityPath, workingDirectory: nil, arguments: ["find-identity","-v","-p","codesigning"])
        if securityResult.output.characters.count < 1 {
            return output
        }
        let rawResult = securityResult.output.componentsSeparatedByString("\"")
        
        var index: Int
        
        for index in 0.stride(through: rawResult.count - 2, by: 2) {
            if !(rawResult.count - 1 < index + 1) {
                output.append(rawResult[index+1])
            }
        }
        return output
    }
    
    func showCodesignCertsErrorAlert(){
        let alert = NSAlert()
        alert.messageText = "No codesigning certificates found"
        alert.informativeText = "I can attempt to fix this automatically, would you like me to try?"
        alert.addButtonWithTitle("Yes")
        alert.addButtonWithTitle("No")
        if alert.runModal() == NSAlertFirstButtonReturn {
            if let tempFolder = makeTempFolder() {
                iASShared.fixSigning(tempFolder)
                try? fileManager.removeItemAtPath(tempFolder)
                populateCodesigningCerts()
            }
        }
    }
    
    func populateCodesigningCerts() {
        CodesigningCertsPopup.removeAllItems()
        self.codesigningCerts = getCodesigningCerts()
        
        setStatus("Found \(self.codesigningCerts.count) Codesigning Certificate\(self.codesigningCerts.count>1 || self.codesigningCerts.count<1 ? "s":"")")
        if self.codesigningCerts.count > 0 {
            for cert in self.codesigningCerts {
                CodesigningCertsPopup.addItemWithTitle(cert)
                setStatus("Added signing certificate \"\(cert)\"")
            }
        } else {
            showCodesignCertsErrorAlert()
        }
        
    }
    
    func checkProfileID(profile: ProvisioningProfile?){
        if let profile = profile {
            self.profileFilename = profile.filename
            setStatus("Selected provisioning profile \(profile.appID)")
            if profile.expires.timeIntervalSince1970 < NSDate().timeIntervalSince1970 {
                ProvisioningProfilesPopup.selectItemAtIndex(0)
                setStatus("Provisioning profile expired")
                chooseProvisioningProfile(ProvisioningProfilesPopup)
            }
            if profile.appID.characters.indexOf("*") == nil {
                // Not a wildcard profile
                NewApplicationIDTextField.stringValue = profile.appID
                NewApplicationIDTextField.enabled = false
            } else {
                // Wildcard profile
                if NewApplicationIDTextField.enabled == false {
                    NewApplicationIDTextField.stringValue = ""
                    NewApplicationIDTextField.enabled = true
                }
            }
        } else {
            ProvisioningProfilesPopup.selectItemAtIndex(0)
            setStatus("Invalid provisioning profile")
            chooseProvisioningProfile(ProvisioningProfilesPopup)
        }
    }
    
    func controlsEnabled(enabled: Bool){
        if(enabled){
            InputFileText.enabled = true
            BrowseButton.enabled = true
            ProvisioningProfilesPopup.enabled = true
            CodesigningCertsPopup.enabled = true
            NewApplicationIDTextField.enabled = ReEnableNewApplicationID
            NewApplicationIDTextField.stringValue = PreviousNewApplicationID
            StartButton.enabled = true
            appDisplayName.enabled = true
        } else {
            // Backup previous values
            PreviousNewApplicationID = NewApplicationIDTextField.stringValue
            ReEnableNewApplicationID = NewApplicationIDTextField.enabled
            
            InputFileText.enabled = false
            BrowseButton.enabled = false
            ProvisioningProfilesPopup.enabled = false
            CodesigningCertsPopup.enabled = false
            NewApplicationIDTextField.enabled = false
            StartButton.enabled = false
            appDisplayName.enabled = false
        }
    }
    
    func recursiveDirectorySearch(path: String, extensions: [String], found: ((file: String) -> Void)){
        
        if let files = try? fileManager.contentsOfDirectoryAtPath(path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExistsAtPath(currentFile, isDirectory: &isDirectory)
                if isDirectory {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    found(file: currentFile)
                }
                
            }
        }
    }
    
    func unzip(inputFile: String, outputPath: String)->AppSignerTaskOutput {
        return NSTask().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    func zip(inputPath: String, outputFile: String)->AppSignerTaskOutput {
        return NSTask().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    func cleanup(tempFolder: String){
        do {
            Log.write("Deleting: \(tempFolder)")
            try fileManager.removeItemAtPath(tempFolder)
        } catch let error as NSError {
            setStatus("Unable to delete temp folder")
            Log.write(error.localizedDescription)
        }
        controlsEnabled(true)
    }
    func bytesToSmallestSi(size: Double) -> String {
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
    func getPlistKey(plist: String, keyName: String)->String? {
        let currTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["read", plist, keyName])
        if currTask.status == 0 {
            return String(currTask.output.characters.dropLast())
        } else {
            return nil
        }
    }
    
    func setPlistKey(plist: String, keyName: String, value: String)->AppSignerTaskOutput {
        return NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }
    
    //MARK: NSURL Delegate
    var downloading = false
    var downloadError: NSError?
    var downloadPath: String!
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        downloadError = downloadTask.error
        if downloadError == nil {
            do {
                try fileManager.moveItemAtURL(location, toURL: NSURL(fileURLWithPath: downloadPath))
            } catch let error as NSError {
                setStatus("Unable to move downloaded file")
                Log.write(error.localizedDescription)
            }
        }
        downloading = false
        downloadProgress.doubleValue = 0.0
        downloadProgress.stopAnimation(nil)
    }
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        
        //StatusLabel.stringValue = "Downloading file: \(bytesToSmallestSi(Double(totalBytesWritten))) / \(bytesToSmallestSi(Double(totalBytesExpectedToWrite)))"
        let percentDownloaded = (Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100
        downloadProgress.doubleValue = percentDownloaded
    }
    
    //MARK: Codesigning
    func codeSign(file: String, certificate: String, entitlements: String?,before:((file: String, certificate: String, entitlements: String?)->Void)?, after: ((file: String, certificate: String, entitlements: String?, codesignTask: AppSignerTaskOutput)->Void)?)->AppSignerTaskOutput{
        
        let useEntitlements: Bool = ({
            if entitlements == nil {
                return false
            } else {
                if fileManager.fileExistsAtPath(entitlements!) {
                    return true
                } else {
                    return false
                }
            }
        })()
        
        if let beforeFunc = before {
            beforeFunc(file: file, certificate: certificate, entitlements: entitlements)
        }
        var arguments = ["-vvv","-fs",certificate,"--no-strict"]
        if useEntitlements {
            arguments.append("--entitlements=\(entitlements!)")
        }
        arguments.append(file)
        let codesignTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if let afterFunc = after {
            afterFunc(file: file, certificate: certificate, entitlements: entitlements, codesignTask: codesignTask)
        }
        return codesignTask
    }
    func testSigning(certificate: String, tempFolder: String )->Bool? {
        let codesignTempFile = tempFolder.stringByAppendingPathComponent("test-sign")
        
        // Copy our binary to the temp folder to use for testing.
        let path = NSProcessInfo.processInfo().arguments[0]
        if (try? fileManager.copyItemAtPath(path, toPath: codesignTempFile)) != nil {
            codeSign(codesignTempFile, certificate: certificate, entitlements: nil, before: nil, after: nil)
            
            let verificationTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: ["-v",codesignTempFile])
            try? fileManager.removeItemAtPath(codesignTempFile)
            if verificationTask.status == 0 {
                return true
            } else {
                return false
            }
        } else {
            setStatus("Error testing codesign")
        }
        return nil
    }
    
    func startSigning() {
        controlsEnabled(false)
        
        //MARK: Get output filename
        let saveDialog = NSSavePanel()
        saveDialog.allowedFileTypes = ["ipa"]
        saveDialog.nameFieldStringValue = InputFileText.stringValue.lastPathComponent.stringByDeletingPathExtension
        if saveDialog.runModal() == NSFileHandlingPanelOKButton {
            outputFile = saveDialog.URL!.path
            NSThread.detachNewThreadSelector(#selector(self.signingThread), toTarget: self, withObject: nil)
        } else {
            outputFile = nil
            controlsEnabled(true)
        }
    }
    
    func signingThread(){
        
        
        //MARK: Set up variables
        var warnings = 0
        var inputFile = InputFileText.stringValue
        var provisioningFile = self.profileFilename
        let signingCertificate = self.CodesigningCertsPopup.selectedItem?.title
        let newApplicationID = self.NewApplicationIDTextField.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let newDisplayName = self.appDisplayName.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let newShortVersion = self.appShortVersion.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let newVersion = self.appVersion.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let inputStartsWithHTTP = inputFile.lowercaseString.substringToIndex(inputFile.startIndex.advancedBy(4)) == "http"
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
        if !inputStartsWithHTTP && !fileManager.fileExistsAtPath(inputFile, isDirectory: &inputIsDirectory){
            let alert = NSAlert()
            alert.messageText = "Input file not found"
            alert.addButtonWithTitle("OK")
            alert.informativeText = "The file \(inputFile) could not be found"
            alert.runModal()
            controlsEnabled(true)
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
        
        dispatch_async(dispatch_get_main_queue(), {
            if let codesignResult = self.testSigning(signingCertificate!, tempFolder: tempFolder) {
                if codesignResult == false {
                    let alert = NSAlert()
                    alert.messageText = "Codesigning error"
                    alert.addButtonWithTitle("Yes")
                    alert.addButtonWithTitle("No")
                    alert.informativeText = "You appear to have a error with your codesigning certificate, do you want me to try and fix the problem?"
                    let response = alert.runModal()
                    if response == NSAlertFirstButtonReturn {
                        iASShared.fixSigning(tempFolder)
                        if self.testSigning(signingCertificate!, tempFolder: tempFolder) == false {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Unable to Fix"
                            errorAlert.addButtonWithTitle("OK")
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
            try fileManager.createDirectoryAtPath(eggDirectory, withIntermediateDirectories: true, attributes: nil)
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
            let defaultConfigObject = NSURLSessionConfiguration.defaultSessionConfiguration()
            let defaultSession = NSURLSession(configuration: defaultConfigObject, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
            if let url = NSURL(string: inputFile) {
                downloading = true
                
                let downloadTask = defaultSession.downloadTaskWithURL(url)
                setStatus("Downloading file")
                downloadProgress.startAnimation(nil)
                downloadTask.resume()
                defaultSession.finishTasksAndInvalidate()
            }
            
            while downloading {
                usleep(100000)
            }
            if downloadError != nil {
                setStatus("Error downloading file, \(downloadError!.localizedDescription.lowercaseString)")
                cleanup(tempFolder); return
            } else {
                inputFile = downloadPath
            }
        }
        
        //MARK: Process input file
        switch(inputFile.pathExtension.lowercaseString){
        case "deb":
            //MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectoryAtPath(debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting deb file")
                let debTask = NSTask().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Log.write(debTask.output)
                if debTask.status != 0 {
                    setStatus("Error processing deb file")
                    cleanup(tempFolder); return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExistsAtPath(dataPath){
                        
                        setStatus("Unpacking data.\(tarFormat)")
                        let tarTask = NSTask().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
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
                try fileManager.moveItemAtPath(debPath.stringByAppendingPathComponent("Applications"), toPath: payloadDirectory)
                
            } catch {
                setStatus("Error processing deb file")
                cleanup(tempFolder); return
            }
            break
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
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
            break
            
        case "app":
            //MARK: --Copy app bundle
            if !inputIsDirectory {
                setStatus("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectoryAtPath(payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItemAtPath(inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            break
            
        case "xcarchive":
            //MARK: --Copy app bundle from xcarchive
            if !inputIsDirectory {
                setStatus("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItemAtPath(inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            break
            
        default:
            setStatus("Unsupported input file")
            cleanup(tempFolder); return
        }
        
        if !fileManager.fileExistsAtPath(payloadDirectory){
            setStatus("Payload directory doesn't exist")
            cleanup(tempFolder); return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectoryAtPath(payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExistsAtPath(payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory { continue }
                
                //MARK: Bundle variables setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExistsAtPath(appBundleProvisioningFilePath))
                
                //MARK: Delete CFBundleResourceSpecification from Info.plist
                Log.write(NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                //MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExistsAtPath(appBundleProvisioningFilePath) {
                        setStatus("Deleting embedded.mobileprovision")
                        do {
                            try fileManager.removeItemAtPath(appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            setStatus("Error deleting embedded.mobileprovision")
                            Log.write(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    setStatus("Copying provisioning profile to app bundle")
                    do {
                        try fileManager.copyItemAtPath(provisioningFile!, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        setStatus("Error copying provisioning profile")
                        Log.write(error.localizedDescription)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    setStatus("Parsing entitlements")
                    
                    if let profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if let entitlements = profile.getEntitlementsPlist(tempFolder) {
                            Log.write("–––––––––––––––––––––––\n\(entitlements)")
                            Log.write("–––––––––––––––––––––––")
                            do {
                                try entitlements.writeToFile(entitlementsPlist, atomically: false, encoding: NSUTF8StringEncoding)
                                setStatus("Saved entitlements to \(entitlementsPlist)")
                            } catch let error as NSError {
                                setStatus("Error writing entitlements.plist, \(error.localizedDescription)")
                            }
                        } else {
                            setStatus("Unable to read entitlements from provisioning profile")
                            warnings += 1
                        }
                        if profile.appID != "*" && (newApplicationID != "" && newApplicationID != profile.appID) {
                            setStatus("Unable to change App ID to \(newApplicationID), provisioning profile won't allow it")
                            cleanup(tempFolder); return
                        }
                    } else {
                        setStatus("Unable to parse provisioning profile, it may be corrupt")
                        warnings += 1
                    }
                    
                }
                
                //MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable"){
                    NSTask().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                //MARK: Change Application ID
                if newApplicationID != "" {
                    
                    if let oldAppID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier") {
                        func changeAppexID(appexFile: String){
                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newApplicationID)\(appexBundleID.substringFromIndex(oldAppID.endIndex))"
                                setStatus("Changing \(appexFile) id to \(newAppexID)")
                                setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
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
                    let displayNameChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        setStatus("Error changing display name")
                        Log.write(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Version
                if newVersion != "" {
                    setStatus("Changing Version to \(newVersion))")
                    let versionChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleVersion", newVersion])
                    if versionChangeTask.status != 0 {
                        setStatus("Error changing version")
                        Log.write(versionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Short Version
                if newShortVersion != "" {
                    setStatus("Changing Short Version to \(newShortVersion))")
                    let shortVersionChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleShortVersionString", newShortVersion])
                    if shortVersionChangeTask.status != 0 {
                        setStatus("Error changing short version")
                        Log.write(shortVersionChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                
                func generateFileSignFunc(payloadDirectory:String, entitlementsPath: String, signingCertificate: String)->((file:String)->Void){
                    
                    
                    let useEntitlements: Bool = ({
                        if fileManager.fileExistsAtPath(entitlementsPath) {
                            return true
                        }
                        return false
                    })()
                    
                    func shortName(file: String, payloadDirectory: String)->String{
                        return file.substringFromIndex(payloadDirectory.endIndex)
                    }
                    
                    func beforeFunc(file: String, certificate: String, entitlements: String?){
                            setStatus("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements":"")")
                    }
                    
                    func afterFunc(file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput){
                        if codesignOutput.status != 0 {
                            setStatus("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            Log.write(codesignOutput.output)
                            warnings += 1
                        }
                    }
                    
                    func output(file:String){
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    return output
                }
                
                //MARK: Codesigning - General
                let signableExtensions = ["dylib","so","0","vis","pvr","framework","appex","app"]
                
                //MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                func signEgg(eggFile: String){
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substringFromIndex(payloadDirectory.endIndex)
                    setStatus("Extracting \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Log.write("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    setStatus("Compressing \(shortName)")
                    self.zip(currentEggPath, outputFile: eggFile)                    
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                //MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(file: appBundlePath)
                
                //MARK: Codesigning - Verification
                let verificationTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
                if verificationTask.status != 0 {
                    let alert = NSAlert()
                    alert.addButtonWithTitle("OK")
                    alert.messageText = "Error verifying code signature!"
                    alert.informativeText = verificationTask.output
                    alert.alertStyle = .CriticalAlertStyle
                    alert.runModal()
                    setStatus("Error verifying code signature")
                    Log.write(verificationTask.output)
                    cleanup(tempFolder); return
                }
            }
        } catch let error as NSError {
            setStatus("Error listing files in payload directory")
            Log.write(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Packaging
        //Check if output already exists and delete if so
        if fileManager.fileExistsAtPath(outputFile!) {
            do {
                try fileManager.removeItemAtPath(outputFile!)
            } catch let error as NSError {
                setStatus("Error deleting output file")
                Log.write(error.localizedDescription)
                cleanup(tempFolder); return
            }
        }
        setStatus("Packaging IPA")
        let zipTask = self.zip(workingDirectory, outputFile: outputFile!)
        if zipTask.status != 0 {
            setStatus("Error packaging IPA")
        }
        //MARK: Cleanup
        cleanup(tempFolder)
        setStatus("Done, output at \(outputFile!)")
    }

    
    //MARK: IBActions
    @IBAction func chooseProvisioningProfile(sender: NSPopUpButton) {
        
        switch(sender.indexOfSelectedItem){
        case 0:
            self.profileFilename = nil
            if NewApplicationIDTextField.enabled == false {
                NewApplicationIDTextField.enabled = true
                NewApplicationIDTextField.stringValue = ""
            }
            break
            
        case 1:
            let openDialog = NSOpenPanel()
            openDialog.canChooseFiles = true
            openDialog.canChooseDirectories = false
            openDialog.allowsMultipleSelection = false
            openDialog.allowsOtherFileTypes = false
            openDialog.allowedFileTypes = ["mobileprovision"]
            openDialog.runModal()
            if let filename = openDialog.URLs.first,
                   profileFilename = filename.path {
                checkProfileID(ProvisioningProfile(filename: profileFilename))
            } else {
                sender.selectItemAtIndex(0)
                chooseProvisioningProfile(sender)
            }
            break
            
        case 2:
            sender.selectItemAtIndex(0)
            chooseProvisioningProfile(sender)
            break
            
        default:
            let profile = provisioningProfiles[sender.indexOfSelectedItem - 3]
            checkProfileID(profile)
            break
        }
        
    }
    @IBAction func doBrowse(sender: AnyObject) {
        let openDialog = NSOpenPanel()
        openDialog.canChooseFiles = true
        openDialog.canChooseDirectories = false
        openDialog.allowsMultipleSelection = false
        openDialog.allowsOtherFileTypes = false
        openDialog.allowedFileTypes = ["ipa","IPA","deb","DEB","app","APP","xcarchive","XCARCHIVE"]
        openDialog.runModal()
        if let filename = openDialog.URLs.first {
            InputFileText.stringValue = filename.path!
        }
    }
    @IBAction func chooseSigningCertificate(sender: NSPopUpButton) {
        Log.write("Set Codesigning Certificate Default to: \(sender.stringValue)")
        defaults.setValue(sender.selectedItem?.title, forKey: "signingCertificate")
    }
    
    @IBAction func doSign(sender: NSButton) {
        switch(true){
            case (codesigningCerts.count == 0):
                showCodesignCertsErrorAlert()
                break
            
            default:
                NSApplication.sharedApplication().windows[0].makeFirstResponder(self)
                startSigning()
        }
    }
    
    @IBAction func statusLabelClick(sender: NSButton) {
        if let outputFile = self.outputFile {
            if fileManager.fileExistsAtPath(outputFile) {
                NSWorkspace.sharedWorkspace().activateFileViewerSelectingURLs([NSURL(fileURLWithPath: outputFile)])
            }
        }
    }
    
}

