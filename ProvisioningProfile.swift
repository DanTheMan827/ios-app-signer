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
        expires: NSDate,
        appID: String,
        teamID: String,
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
            if let results = try? NSPropertyListSerialization.propertyListWithData(taskOutput.output.dataUsingEncoding(NSUTF8StringEncoding)!, options: .Immutable, format: nil) {
                if let expirationDate = results.valueForKey("ExpirationDate") as? NSDate,
                    entitlements = results.valueForKey("Entitlements"),
                    applicationIdentifier = entitlements.valueForKey("application-identifier") as? String,
                    periodIndex = applicationIdentifier.characters.indexOf(".") {
                        self.filename = filename
                        self.expires = expirationDate
                        self.appID = applicationIdentifier.substringFromIndex(periodIndex.advancedBy(1))
                        self.teamID = applicationIdentifier.substringToIndex(periodIndex)
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
    
    func getEntitlementsPlist() -> NSString? {
        do {
        let plistData = try NSPropertyListSerialization.dataWithPropertyList(self.entitlements!, format: .XMLFormat_v1_0, options: 0)
        return NSString(data: plistData, encoding: NSUTF8StringEncoding)
        } catch let error as NSError {
            Log.write("Error reading entitlements from \(filename.lastPathComponent)")
            Log.write(error.localizedDescription)
            return nil
        }
    }
}