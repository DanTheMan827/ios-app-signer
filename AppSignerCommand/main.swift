//
//  main.swift
//  AppSignerCMD
//
//  Created by iMokhles on 20/03/16.
//  Copyright © 2016 Daniel Radtke. All rights reserved.
//

import Foundation

class AppSigner {
    let bundleID = "AppSignerCommand"
    let arPath = "/usr/bin/ar"
    let mktempPath = "/usr/bin/mktemp"
    let tarPath = "/usr/bin/tar"
    let unzipPath = "/usr/bin/unzip"
    let zipPath = "/usr/bin/zip"
    let defaultsPath = "/usr/bin/defaults"
    let codesignPath = "/usr/bin/codesign"
    let securityPath = "/usr/bin/security"
    let chmodPath = "/bin/chmod"
    var eggCount: Int = 0
    
    var inputFile: String!
    var outputFile: String!
    let fileManager = FileManager.default
    
    var signingCertificate: String!
    var provisioningFile: String!
    
    var bundleId: String?
    var appName: String?
    var version: String?
    var build: String?
    
    
    
    func sign() {
        // Check if input file exists
        var inputIsDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: inputFile, isDirectory: &inputIsDirectory){
            Logger.log("The file \(inputFile) could not be found")
            return
        }
        
        //MARK: Create working temp folder
        var tempFolder: String! = nil
        if let tmpFolder = makeTempFolder() {
            tempFolder = tmpFolder
        } else {
            Logger.log("Error creating temp folder")
            return
        }
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        let eggDirectory = tempFolder.stringByAppendingPathComponent("eggs")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        
//        Logger.log("Temp folder: \(tempFolder)")
//        Logger.log("Working directory: \(workingDirectory)")
//        Logger.log("Payload directory: \(payloadDirectory)")
        
        //MARK: Codesign Test
        guard testSign(certificate: self.signingCertificate, tempFolder: tempFolder) else {
            Logger.log("test sign fail")
            cleanup(tempFolder)
            return
        }
        
        //MARK: Create Egg Temp Directory
        do {
            try fileManager.createDirectory(atPath: eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            Logger.log("Error creating egg temp directory：\(error.localizedDescription)")
            cleanup(tempFolder);
            return
        }
        
        //MARK: Process input file
        switch(inputFile.pathExtension.lowercased()){
        case "deb":
            //MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectory(atPath: debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.log("Extracting deb file")
                let debTask = Process().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Logger.log(debTask.output)
                if debTask.status != 0 {
                    Logger.log("Error processing deb file")
                    cleanup(tempFolder);
                    return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExists(atPath: dataPath){
                        
                        Logger.log("Unpacking data.\(tarFormat)")
                        let tarTask = Process().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
                        Logger.log(tarTask.output)
                        if tarTask.status == 0 {
                            tarUnpacked = true
                        }
                        break
                    }
                }
                if !tarUnpacked {
                    Logger.log("Error unpacking data.tar")
                    cleanup(tempFolder); return
                }
                
                var sourcePath = debPath.stringByAppendingPathComponent("Applications")
                if fileManager.fileExists(atPath: debPath.stringByAppendingPathComponent("var/mobile/Applications")){
                    sourcePath = debPath.stringByAppendingPathComponent("var/mobile/Applications")
                }
                
                try fileManager.moveItem(atPath: sourcePath, toPath: payloadDirectory)
                
            } catch {
                Logger.log("Error processing deb file")
                cleanup(tempFolder); return
            }
            break
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.log("Extracting ipa file")
                
                let unzipTask = self.unzip(inputFile, outputPath: workingDirectory)
                if unzipTask.status != 0 {
                    Logger.log("Error extracting ipa file")
                    cleanup(tempFolder); return
                }
            } catch {
                Logger.log("Error extracting ipa file")
                cleanup(tempFolder); return
            }
            break
            
        case "app":
            //MARK: --Copy app bundle
            if !inputIsDirectory.boolValue {
                Logger.log("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.log("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                Logger.log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            break
            
        case "xcarchive":
            //MARK: --Copy app bundle from xcarchive
            if !inputIsDirectory.boolValue {
                Logger.log("Unsupported input file")
                cleanup(tempFolder); return
            }
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.log("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                Logger.log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            break
            
        default:
            Logger.log("Unsupported input file")
            cleanup(tempFolder); return
        }
        
        if !fileManager.fileExists(atPath: payloadDirectory){
            Logger.log("Payload directory doesn't exist")
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
                Logger.log(Process().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                //MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExists(atPath: appBundleProvisioningFilePath) {
                        do {
                            try fileManager.removeItem(atPath: appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            Logger.log("Error deleting embedded.mobileprovision")
                            Logger.log(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    do {
                        try fileManager.copyItem(atPath: provisioningFile!, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        Logger.log("Error copying provisioning profile：\(error.localizedDescription)")
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    Logger.log("Parsing entitlements")
                    
                    if let profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if let entitlements = profile.getEntitlementsPlist(tempFolder) {
                            do {
                                try entitlements.write(toFile: entitlementsPlist, atomically: false, encoding: String.Encoding.utf8.rawValue)
                            } catch let error as NSError {
                                Logger.log("Error writing entitlements.plist, \(error.localizedDescription)")
                            }
                        } else {
                            Logger.log("Unable to read entitlements from provisioning profile")
                        }
                    } else {
                        Logger.log("Unable to parse provisioning profile, it may be corrupt")
                    }
                    
                }
                
                //MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable"){
                    _ = Process().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                //MARK: Change Application ID
                if let newBundleId = self.bundleId {
                    if let oldAppID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier") {
                        func changeAppexID(_ appexFile: String){
                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newBundleId)\(appexBundleID.suffix(from: oldAppID.endIndex))"
                                Logger.log("Changing \(appexFile) id to \(newAppexID)")
                                _ = setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                _ = setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newBundleId)
                            }
                            recursiveDirectorySearch(appexFile, extensions: ["app"], found: changeAppexID)
                        }
                        recursiveDirectorySearch(appBundlePath, extensions: ["appex"], found: changeAppexID)
                    }
                    
                    Logger.log("Changing App ID to \(newBundleId)")
                    let IDChangeTask = setPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier", value: newBundleId)
                    if IDChangeTask.status != 0 {
                        Logger.log("Error changing App ID：\(IDChangeTask.output)")
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Display Name
                if let newAppName = self.appName {
                    Logger.log("Changing Display Name to \(newAppName))")
                    let displayNameChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newAppName])
                    if displayNameChangeTask.status != 0 {
                        Logger.log("Error changing display name: \(displayNameChangeTask.output)")
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Version
                if let newVersion = self.version {
                    Logger.log("Changing Version to \(newVersion)")
                    let versionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleVersion", newVersion])
                    if versionChangeTask.status != 0 {
                        Logger.log("Error changing version: \(versionChangeTask.output)")
                        cleanup(tempFolder); return
                    }
                }
                
                //MARK: Change Short Version
                if let newBuild = self.build {
                    Logger.log("Changing Short Version to \(newBuild)")
                    let shortVersionChangeTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleShortVersionString", newBuild])
                    if shortVersionChangeTask.status != 0 {
                        Logger.log("Error changing short version: \(shortVersionChangeTask.output)")
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
                    
                    func shortName(_ file: String, payloadDirectory: String)-> String {
                        return String(file.suffix(from: payloadDirectory.endIndex))
                    }
                    
                    func beforeFunc(_ file: String, certificate: String, entitlements: String?){
                        Logger.log("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements":"")")
                    }
                    
                    func afterFunc(_ file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput){
                        if codesignOutput.status != 0 {
                            Logger.log("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            Logger.log(codesignOutput.output)
                        }
                    }
                    
                    func output(_ file:String){
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    return output
                }
                
                //MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                func signEgg(_ eggFile: String) {
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substring(from: payloadDirectory.endIndex)
                    Logger.log("Extracting \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Logger.log("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveMachOSearch(currentEggPath, found: eggSigningFunction)
                    Logger.log("Compressing \(shortName)")
                    _ = self.zip(currentEggPath, outputFile: eggFile)
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                //MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                
                
                recursiveMachOSearch(appBundlePath, found: signingFunction)
                signingFunction(appBundlePath)
                
                //MARK: Codesigning - Verification
                let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
                if verificationTask.status != 0 {
                    Logger.log("Error verifying code signature: \(verificationTask.output)")
                    self.cleanup(tempFolder); return
                }
            }
        } catch let error as NSError {
            Logger.log("Error listing files in payload directory")
            Logger.log(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        //MARK: Packaging
        //Check if output already exists and delete if so
        if fileManager.fileExists(atPath: outputFile!) {
            do {
                try fileManager.removeItem(atPath: outputFile!)
            } catch let error as NSError {
                Logger.log("Error deleting output file")
                Logger.log(error.localizedDescription)
                cleanup(tempFolder); return
            }
        }
        Logger.log("Packaging IPA")
        let zipTask = self.zip(workingDirectory, outputFile: outputFile!)
        if zipTask.status != 0 {
            Logger.log("Error packaging IPA")
        }
        //MARK: Cleanup
        cleanup(tempFolder)
    }
    
    func setPlistKey(_ plist: String, keyName: String, value: String)->AppSignerTaskOutput {
        return Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }
    
    func testSign(certificate: String, tempFolder: String) -> Bool {
        if let codesignResult = self.testSigning(signingCertificate!, tempFolder: tempFolder) {
            if codesignResult == false {
                iASShared.fixSigning(tempFolder)
                if let result = self.testSigning(signingCertificate!, tempFolder: tempFolder), result == true {
                    return true
                } else {
                    
                    return false
                }
            } else {
                return true
            }
        }
        return false
    }
    
    func makeTempFolder()->String?{
        let tempTask = Process().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
                return true
            } else {
                return false
            }
        } else {
            Logger.log("Error testing codesign")
        }
        return nil
    }
    
    //MARK: Codesigning
    @discardableResult
    func codeSign(_ file: String, certificate: String, entitlements: String?,before:((_ file: String, _ certificate: String, _ entitlements: String?)->Void)?, after: ((_ file: String, _ certificate: String, _ entitlements: String?, _ codesignTask: AppSignerTaskOutput)->Void)?)->AppSignerTaskOutput{
        
        let hasEntitlements: Bool = ({
            if entitlements == nil {
                return false
            } else {
                if fileManager.fileExists(atPath: entitlements!) {
                    return true
                } else {
                    return false
                }
            }
        })()
        
        var needEntitlements: Bool = false
        var filePath = file
        let fileExtension = file.lastPathComponent.pathExtension
        if fileExtension == "framework" {
            // appene execute file in framework
            let fileName = file.lastPathComponent.stringByDeletingPathExtension
            filePath = file.stringByAppendingPathComponent(fileName)
        } else if fileExtension == "app" {
            // appene execute file in app
            let fileName = file.lastPathComponent.stringByDeletingPathExtension
            filePath = file.stringByAppendingPathComponent(fileName)
            needEntitlements = hasEntitlements
        } else {
            //
        }
        
        if let beforeFunc = before {
            beforeFunc(file, certificate, entitlements)
        }
        var arguments = [String]()
        
        if needEntitlements {
            arguments.append("--entitlements")
            arguments.append(entitlements!)
        }
        arguments.append(contentsOf: ["-f", "-s", certificate])
        arguments.append(filePath)
        
        let codesignTask = Process().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if let afterFunc = after {
            afterFunc(file, certificate, entitlements, codesignTask)
        }
        return codesignTask
    }
    
    func cleanup(_ tempFolder: String){
        do {
            Logger.log("Deleting Temp Files")
            try fileManager.removeItem(atPath: tempFolder)
        } catch let error as NSError {
            Logger.log("Unable to delete temp folder: \(error.localizedDescription)")
        }
    }
    
    func unzip(_ inputFile: String, outputPath: String)->AppSignerTaskOutput {
        return Process().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    func zip(_ inputPath: String, outputFile: String)->AppSignerTaskOutput {
        return Process().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    func getPlistKey(_ plist: String, keyName: String)->String? {
        let currTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", plist, keyName])
        if currTask.status == 0 {
            return String(currTask.output.dropLast())
        } else {
            return nil
        }
    }
    
    func recursiveMachOSearch(_ path: String, found: ((_ file: String) -> Void)){
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveMachOSearch(currentFile, found: found)
                }
                if checkMachOFile(currentFile) {
                    found(currentFile)
                }
            }
        }
    }
    func recursiveDirectorySearch(_ path: String, extensions: [String], found: ((_ file: String) -> Void)){
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    found(currentFile)
                }
            }
        }
    }
    
    /// check if Mach-O file
    func checkMachOFile(_ path: String) -> Bool {
        let task = Process().execute("/usr/bin/file", workingDirectory: nil, arguments: [path])
        let fileContent = task.output.replacingOccurrences(of: "\(path): ", with: "")
        return fileContent.starts(with: "Mach-O")
    }

}


func main() {
    var arguments = CommandLine.arguments
   
    var inputFile: String?
    var outputFile: String?
    var signingCertificate: String?
    var provisioningFile: String?
    
    var bundleId: String?
    var name: String?
    var version: String?
    var build: String?
    
    for (i, argument) in arguments.enumerated() {
        switch argument {
        case "-i":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                inputFile = arguments[i + 1]
            }
        case "-o":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                outputFile = arguments[i + 1]
            }
        case "-s":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                signingCertificate = arguments[i + 1]
            }
        case "-p":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                provisioningFile = arguments[i + 1]
            }
        case "-appId":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                bundleId = arguments[i + 1]
            }
        case "-appName":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                name = arguments[i + 1]
            }
        case "-build":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                build = arguments[i + 1]
            }
        case "-version":
            if arguments.count > i - 1, arguments[i + 1].count > 0 {
                version = arguments[i + 1]
            }
        case "-help", "-h", "-fuck":
            print("""

Usage: ./AppSignerCommand [options]
# 下面是必要参数，不可少
  -i:
      (required) Path to the input ipa/app file.
  -o:
      (required) Path to the output ipa file.
  -s:
      (required) exmple: iPhone Developer: xxxx (XXX)
  -p:
      (required) Path to the mobileprovision file.

# 下面参数可选，如果没有设置，则使用原包的信息
  -appId:
      (optional) exmple: com.tencent.xin
  -appName:
      (optional) exmple: wechat
  -build:
      (optional) exmple: 10533
  -version:
      (optional) exmple: 1.0.5

# 查看帮助
  -h, -help, -fuck:
      Prints a help message.

example:
./AppSignerCommand -i "/Users/bomo/Desktop/Wechat.ipa" -o "/Users/bomo/Desktop/Wechat_sign.ipa" -p "/Users/bomo/Desktop/wechat_dev.mobileprovision" -s "iPhone Distribution: Guangzhou XXX Technology Co. Ltd (XXXX)"

""")
            return
        default:
            break
        }
    }
    
    guard let _ = inputFile else {
        print("没有指定包文件: -h 查看帮助")
        return
    }
    
    guard let _ = outputFile else {
        print("没有指定输出文件：-h 查看帮助")
        return;
    }
    
    guard let _ = signingCertificate else {
        print("没有指定签名证书：-h 查看帮助")
        return;
    }
    
    guard let _ = signingCertificate else {
        print("没有指定provisionprofile文件：-h 查看帮助")
        return;
    }
    
    let signer = AppSigner()
    signer.inputFile = inputFile
    signer.outputFile = outputFile
    signer.signingCertificate = signingCertificate
    signer.provisioningFile = provisioningFile;
    signer.appName = name
    signer.version = version
    signer.bundleId = bundleId
    signer.build = build
    signer.sign()
    
    // 签名完成后打开目录
    _ = Process().execute("/usr/bin/open", workingDirectory: nil, arguments: [inputFile!.stringByDeletingLastPathComponent])
    print("签名完成：\(outputFile!)")
}

main()

