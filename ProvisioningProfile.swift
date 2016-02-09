//
//  provisioningProfile.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/4/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Foundation
import AppKit
struct ProvisioningProfile {
    var filename: String,
        name: String,
        created:NSDate,
        expires: NSDate,
        appID: String,
        teamID: String,
        rawXML: String,
        entitlements: AnyObject?
    private let delegate = NSApplication.sharedApplication().delegate as! AppDelegate
    
    static func getProfiles() -> [ProvisioningProfile] {
        var output: [ProvisioningProfile] = []
        
        let fileManager = NSFileManager()
        if let libraryDirectory = fileManager.URLsForDirectory(.LibraryDirectory, inDomains: .UserDomainMask).first,
            libraryPath = libraryDirectory.path {
                let provisioningProfilesPath = libraryPath.stringByAppendingPathComponent("MobileDevice/Provisioning Profiles") as NSString
                if let provisioningProfiles = try? fileManager.contentsOfDirectoryAtPath(provisioningProfilesPath as String) {
                    
                    for provFile in provisioningProfiles {
                        if provFile.pathExtension == "mobileprovision" {
                            let profileFilename = provisioningProfilesPath.stringByAppendingPathComponent(provFile)
                            if let profile = ProvisioningProfile(filename: profileFilename) {
                                output.append(profile)
                            }
                        }
                    }
                }
        }

        
        return output;
    }
    
    init?(filename: String){
        let securityArgs = ["cms","-D","-i", filename]
        
         let taskOutput = NSTask().execute("/usr/bin/security", workingDirectory: nil, arguments: securityArgs)
         if taskOutput.status == 0 {
            self.rawXML = taskOutput.output
            if let results = try? NSPropertyListSerialization.propertyListWithData(taskOutput.output.dataUsingEncoding(NSUTF8StringEncoding)!, options: .Immutable, format: nil) {
                if let expirationDate = results.valueForKey("ExpirationDate") as? NSDate,
                    creationDate = results.valueForKey("CreationDate") as? NSDate,
                    name = results.valueForKey("Name") as? String,
                    entitlements = results.valueForKey("Entitlements"),
                    applicationIdentifier = entitlements.valueForKey("application-identifier") as? String,
                    periodIndex = applicationIdentifier.characters.indexOf(".") {
                        self.filename = filename
                        self.expires = expirationDate
                        self.created = creationDate
                        self.appID = applicationIdentifier.substringFromIndex(periodIndex.advancedBy(1))
                        self.teamID = applicationIdentifier.substringToIndex(periodIndex)
                        self.name = name
                        self.entitlements = entitlements
                } else {
                    Log.write("Error processing \(filename.lastPathComponent)")
                    return nil
                }
            } else {
                Log.write("Error parsing \(filename.lastPathComponent)")
                return nil
            }
        } else {
            Log.write("Error reading \(filename.lastPathComponent)")
            return nil
        }
    }
    
    func getEntitlementsPlist(tempFolder: String) -> NSString? {
        let mobileProvisionPlist = tempFolder.stringByAppendingPathComponent("mobileprovision.plist")
        do {
            try self.rawXML.writeToFile(mobileProvisionPlist, atomically: false, encoding: NSUTF8StringEncoding)
            let plistBuddy = NSTask().execute("/usr/libexec/PlistBuddy", workingDirectory: nil, arguments: ["-c", "Print :Entitlements",mobileProvisionPlist, "-x"])
            if plistBuddy.status == 0 {
                return plistBuddy.output
            } else {
                Log.write("PlistBuddy Failed")
                Log.write(plistBuddy.output)
                return nil
            }
        } catch let error as NSError {
            Log.write("Error writing mobileprovision.plist")
            Log.write(error.localizedDescription)
            return nil
        }
    }
}