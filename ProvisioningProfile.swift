//
//  provisioningProfile.swift
//  AppSigner
//
//  Created by Daniel Radtke on 11/4/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Foundation
struct ProvisioningProfile {
    var filename: String,
        expires: NSDate,
        appID: String,
        teamID: String,
        entitlements: AnyObject?
    
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
                    teamIdentifier = entitlements.valueForKey("com.apple.developer.team-identifier") as? String {
                        self.filename = filename
                        self.expires = expirationDate
                        self.appID = applicationIdentifier.substringFromIndex(("\(teamIdentifier).").endIndex)
                        self.teamID = teamIdentifier
                        self.entitlements = entitlements
                } else {
                    NSLog("Error processing \(filename.lastPathComponent)")
                    return nil
                }
            } else {
                NSLog("Error parsing \(filename.lastPathComponent)")
                return nil
            }
        } else {
            NSLog("Error reading \(filename.lastPathComponent)")
            return nil
        }
    }
    
    func getEntitlementsPlist() -> NSString? {
        do {
        let plistData = try NSPropertyListSerialization.dataWithPropertyList(self.entitlements!, format: .XMLFormat_v1_0, options: 0)
        return NSString(data: plistData, encoding: NSUTF8StringEncoding)
        } catch {
            NSLog("Error reading entitlements from \(filename.lastPathComponent)")
            return nil
        }
    }
}