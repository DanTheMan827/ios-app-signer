//
//  ViewController.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/2/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, NSURLSessionDataDelegate, NSURLSessionDelegate, NSURLSessionDownloadDelegate {
    
    //MARK: IBOutlets
    @IBOutlet var ProvisioningProfilesPopup: NSPopUpButton!
    @IBOutlet var CodesigningCertsPopup: NSPopUpButton!
    @IBOutlet var StatusLabel: NSTextField!
    @IBOutlet var InputFileText: NSTextField!
    @IBOutlet var BrowseButton: NSButton!
    @IBOutlet var StartButton: NSButton!
    @IBOutlet var NewApplicationIDTextField: NSTextField!
    @IBOutlet var downloadProgress: NSProgressIndicator!
    @IBOutlet var appDisplayName: NSTextFieldCell!
    
    //MARK: Variables
    var provisioningProfiles:[ProvisioningProfile] = []
    var codesigningCerts: [String] = []
    var profileFilename: String?
    var ReEnableNewApplicationID = false
    var PreviousNewApplicationID = ""
    var outputFile: String?
    var startSize: CGFloat?
    
    //MARK: Constants
    let defaults = NSUserDefaults()
    let fileManager = NSFileManager.defaultManager()
    let arPath = "/usr/bin/ar"
    let mktempPath = "/usr/bin/mktemp"
    let tarPath = "/usr/bin/tar"
    let unzipPath = "/usr/bin/unzip"
    let zipPath = "/usr/bin/zip"
    let defaultsPath = "/usr/bin/defaults"
    let codesignPath = "/usr/bin/codesign"
    
    
    //MARK: Functions
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        populateProvisioningProfiles()
        populateCodesigningCerts()
        if let defaultCert = defaults.stringForKey("signingCertificate") {
            if codesigningCerts.contains(defaultCert) {
                NSLog("Loaded Codesigning Certificate from Defaults: \(defaultCert)")
                CodesigningCertsPopup.selectItemWithTitle(defaultCert)
            }
        }
        setStatus("Ready")
    }
    
    func setStatus(status: String){
        NSLog(status)
        StatusLabel.stringValue = status
    }
    
    func populateProvisioningProfiles(){
        provisioningProfiles = ProvisioningProfile.getProfiles().sort {
            $0.appID < $1.appID
        }
        setStatus("Found \(provisioningProfiles.count) Provisioning Profile\(provisioningProfiles.count>1 || provisioningProfiles.count<1 ? "s":"")")
        ProvisioningProfilesPopup.removeAllItems()
        ProvisioningProfilesPopup.addItemsWithTitles([
            "Re-Sign Only",
            "Choose Custom File",
            "––––––––––––––––––––––"
        ])
        for profile in provisioningProfiles {
            if profile.expires.timeIntervalSince1970 > NSDate().timeIntervalSince1970 {
                ProvisioningProfilesPopup.addItemWithTitle("\(profile.appID) (\(profile.teamID))")
            }
        }
        chooseProvisioningProfile(ProvisioningProfilesPopup)
    }
    
    func getCodesigningCerts() -> [String] {
        var output: [String] = []
        let securityResult = NSTask().execute("/usr/bin/security", workingDirectory: nil, arguments: ["find-identity","-v","-p","codesigning"])
        if securityResult.output.characters.count < 1 {
            return output
        }
        let rawResult = securityResult.output.componentsSeparatedByString("\"")
        
        var index: Int
        
        for index = 0; index <= rawResult.count - 2; index+=2 {
            if !(rawResult.count - 1 < index + 1) {
                output.append(rawResult[index+1])
            }
        }
        return output
    }
    
    func populateCodesigningCerts() {
        CodesigningCertsPopup.removeAllItems()
        self.codesigningCerts = getCodesigningCerts()
        
        for cert in self.codesigningCerts {
            CodesigningCertsPopup.addItemWithTitle(cert)
        }
        setStatus("Found \(self.codesigningCerts.count) Codesigning Certificate\(self.codesigningCerts.count>1 || self.codesigningCerts.count<1 ? "s":"")")
    }
    
    func checkProfileID(profile: ProvisioningProfile?){
        if profile != nil {
            if profile!.appID != "*" {
                NewApplicationIDTextField.stringValue = profile!.appID
                NewApplicationIDTextField.enabled = false
            } else {
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
    
    func cleanup(tempFolder: String){
        if (try? fileManager.removeItemAtPath(tempFolder)) == nil {
            setStatus("Unable to delete temp folder")
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
    //MARK: NSURL Delegate
    var downloading = false
    var downloadError: NSError?
    var downloadPath: String!
    
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        downloadError = downloadTask.error
        if downloadError == nil {
            try? fileManager.moveItemAtURL(location, toURL: NSURL(fileURLWithPath: downloadPath))
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
    func startSigning() {
        controlsEnabled(false)
        
        //MARK: Get output filename
        let saveDialog = NSSavePanel()
        saveDialog.allowedFileTypes = ["ipa"]
        saveDialog.nameFieldStringValue = InputFileText.stringValue.lastPathComponent.stringByDeletingPathExtension
        if saveDialog.runModal() == NSFileHandlingPanelOKButton {
            outputFile = saveDialog.URL!.path
            NSThread.detachNewThreadSelector(Selector("signingThread"), toTarget: self, withObject: nil)
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
        let signingCertificate = self.CodesigningCertsPopup.selectedItem!.title
        let newApplicationID = self.NewApplicationIDTextField.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let newDisplayName = self.appDisplayName.stringValue.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        
        //MARK: Create working temp folder
        let tempTask = NSTask().execute(mktempPath, workingDirectory: nil, arguments: ["-d"])
        if tempTask.status != 0 {
            setStatus("Error creating temp folder")
            return
        }
        let tempFolder = tempTask.output.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        
        //MARK: Download file
        downloading = false
        downloadError = nil
        downloadPath = tempFolder.stringByAppendingPathComponent("download.\(inputFile.pathExtension)")
        
        if inputFile.lowercaseString.substringToIndex(inputFile.startIndex.advancedBy(4)) == "http" {
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
        
        //MARK: Check if input file exists
        var inputIsDirectory: ObjCBool = false
        if !fileManager.fileExistsAtPath(inputFile, isDirectory: &inputIsDirectory){
            let alert = NSAlert()
            alert.messageText = "Input file not found"
            alert.addButtonWithTitle("OK")
            alert.informativeText = "The file \(inputFile) could not be found"
            alert.runModal()
            controlsEnabled(true)
            cleanup(tempFolder)
            return
        }
        
        //MARK: Process input file
        switch(inputFile.pathExtension.lowercaseString){
        case "deb":
            //MARK: Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectoryAtPath(debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting deb file")
                let debTask = NSTask().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                NSLog(debTask.output)
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
                        NSLog(tarTask.output)
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
            //MARK: Unzip ipa
            do {
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting ipa file")
                let unzipTask = NSTask().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",workingDirectory])
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
            //MARK: Copy app bundle
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
            //MARK: Copy app bundle from xcarchive
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
        
        func generateFileSignFunc(payloadDirectory:String, entitlementsPath: String, signingCertificate: String)->((file:String)->Void){
            let useEntitlements = fileManager.fileExistsAtPath(entitlementsPath)
            func output(file:String){
                let shortName = file.substringFromIndex(payloadDirectory.endIndex)
                setStatus("Codesigning \(shortName)")
                var arguments = ["-vvv","-fs",signingCertificate,"--no-strict"]
                if useEntitlements {
                    arguments.append("--entitlements=\(entitlementsPath)")
                }
                arguments.append(file)
                let codesignTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: arguments)
                
                if codesignTask.status != 0 {
                    setStatus("Error codesigning \(shortName)")
                    warnings++
                    NSLog(codesignTask.output)
                }
            }
            return output
        }
        
        if let files = try? fileManager.contentsOfDirectoryAtPath(payloadDirectory) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExistsAtPath(payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory { continue }
                
                //MARK: Bundle variable setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExistsAtPath(appBundleProvisioningFilePath))
                
                //MARK: Delete CFBundleResourceSpecification from Info.plist
                NSLog(NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                //MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExistsAtPath(appBundleProvisioningFilePath) {
                        if (try? fileManager.removeItemAtPath(appBundleProvisioningFilePath)) == nil {
                            setStatus("Error deleting embedded.mobileprovision")
                            cleanup(tempFolder); return
                        }
                    }
                    if (try? fileManager.copyItemAtPath(provisioningFile!, toPath: appBundleProvisioningFilePath)) == nil {
                        setStatus("Error copying provisioning profile")
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    setStatus("Parsing entitlements")
                    if let profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if let entitlements = profile.getEntitlementsPlist() {
                            if (try? entitlements.writeToFile(entitlementsPlist, atomically: false, encoding: NSUTF8StringEncoding)) == nil {
                                setStatus("Error writing entitlements.plist")
                            }
                        } else {
                            setStatus("Unable to read entitlements from provisioning profile")
                            warnings++
                        }
                        if profile.appID != "*" && (newApplicationID != "" && newApplicationID != profile.appID) {
                            setStatus("Unable to change App ID to \(newApplicationID), provisioning profile won't allow it")
                            cleanup(tempFolder); return
                        }
                    } else {
                        setStatus("Unable to parse provisioning profile, it may be corrupt")
                        warnings++
                    }
                    
                }
                
                //MARK: Change Application ID
                if newApplicationID != "" {
                    setStatus("Changing App ID to \(newApplicationID)")
                    let IDChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleIdentifier", newApplicationID])
                    if IDChangeTask.status != 0 {
                        setStatus("Error changing App ID")
                        NSLog(IDChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Display Name
                if newDisplayName != "" {
                    setStatus("Changing Display Name to \(newDisplayName))")
                    let displayNameChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        setStatus("Error changing display name")
                        NSLog(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Codesigning
                let signFunc = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate)
                recursiveDirectorySearch(appBundlePath, extensions: ["dylib","so","0","vis","pvr","framework"], found: signFunc)
                signFunc(file: appBundlePath)
            }
        }
        
        //MARK: Packaging
        //Check if output already exists and delete if so
        if fileManager.fileExistsAtPath(outputFile!) {
            if (try? fileManager.removeItemAtPath(outputFile!)) == nil {
                setStatus("Error deleting output file")
                cleanup(tempFolder); return
            }
        }
        setStatus("Packaging IPA")
        let zipTask = NSTask().execute(zipPath, workingDirectory: workingDirectory, arguments: ["-qry", outputFile!, "."])
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
            profileFilename = nil
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
            if let filename = openDialog.URLs.first {
                let profileFilename = filename.path!
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
            profileFilename = profile.filename
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
        NSLog("Set Codesigning Certificate Default to: \(sender.stringValue)")
        defaults.setValue(sender.selectedItem?.title, forKey: "signingCertificate")
    }
    
    @IBAction func doSign(sender: NSButton) {
        NSApplication.sharedApplication().windows[0].makeFirstResponder(self)
        startSigning()
        //NSThread.detachNewThreadSelector(Selector("signingThread"), toTarget: self, withObject: nil)
    }
}

