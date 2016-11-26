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
        created:Date,
        expires: Date,
        appID: String,
        teamID: String,
        rawXML: String,
        entitlements: AnyObject?
    fileprivate let delegate = NSApplication.shared().delegate as! AppDelegate
    
    static func getProfiles() -> [ProvisioningProfile] {
        var output: [ProvisioningProfile] = []
        
        let fileManager = FileManager()
        if let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                let provisioningProfilesPath = libraryDirectory.path.stringByAppendingPathComponent("MobileDevice/Provisioning Profiles") as NSString
                if let provisioningProfiles = try? fileManager.contentsOfDirectory(atPath: provisioningProfilesPath as String) {
                    
                    for provFile in provisioningProfiles {
                        if provFile.pathExtension == "mobileprovision" {
                            let profileFilename = provisioningProfilesPath.appendingPathComponent(provFile)
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
        
         let taskOutput = Process().execute("/usr/bin/security", workingDirectory: nil, arguments: securityArgs)
         if taskOutput.status == 0 {
            if let xmlIndex = taskOutput.output.range(of: "<?xml") {
                self.rawXML = taskOutput.output.substring(from: xmlIndex.lowerBound)
            } else {
                Log.write("Unable to find xml start tag in profile")
                self.rawXML = taskOutput.output
            }
            
            if let results = try? PropertyListSerialization.propertyList(from: self.rawXML.data(using: String.Encoding.utf8)!, options: PropertyListSerialization.MutabilityOptions(), format: nil) {
                if let expirationDate = (results as AnyObject).value(forKey: "ExpirationDate") as? Date,
                    let creationDate = (results as AnyObject).value(forKey: "CreationDate") as? Date,
                    let name = (results as AnyObject).value(forKey: "Name") as? String,
                    let entitlements = (results as AnyObject).value(forKey: "Entitlements"),
                    let applicationIdentifier = (entitlements as AnyObject).value(forKey: "application-identifier") as? String,
                    let periodIndex = applicationIdentifier.characters.index(of: ".") {
                        self.filename = filename
                        self.expires = expirationDate
                        self.created = creationDate
                        self.appID = applicationIdentifier.substring(from: applicationIdentifier.index(periodIndex, offsetBy: 1))
                        self.teamID = applicationIdentifier.substring(to: periodIndex)
                        self.name = name
                        self.entitlements = entitlements as AnyObject?
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
    
    func getEntitlementsPlist(_ tempFolder: String) -> NSString? {
        let mobileProvisionPlist = tempFolder.stringByAppendingPathComponent("mobileprovision.plist")
        do {
            try self.rawXML.write(toFile: mobileProvisionPlist, atomically: false, encoding: String.Encoding.utf8)
            let plistBuddy = Process().execute("/usr/libexec/PlistBuddy", workingDirectory: nil, arguments: ["-c", "Print :Entitlements",mobileProvisionPlist, "-x"])
            if plistBuddy.status == 0 {
                return plistBuddy.output as NSString?
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
