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
        entitlements: [String : AnyObject]
    fileprivate let delegate = NSApplication.shared.delegate as! AppDelegate
    
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

        // distinct
        output = output.sorted(by: {
            $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970
        })

        var newProfiles = [ProvisioningProfile]()
        var names = [String]()
        for profile in output {
            if !names.contains("\(profile.name)\(profile.appID)") {
                newProfiles.append(profile)
                names.append("\(profile.name)\(profile.appID)")
                NSLog("\(profile.name), \(profile.created)")
            }
        }
        return newProfiles;
    }
    
    init?(filename: String){
        let securityArgs = ["cms","-D","-i", filename]
        
         let taskOutput = Process().execute("/usr/bin/security", workingDirectory: nil, arguments: securityArgs)
         let rawXML: String
         if taskOutput.status == 0 {
            if let xmlIndex = taskOutput.output.range(of: "<?xml") {
                rawXML = taskOutput.output.substring(from: xmlIndex.lowerBound)
            } else {
                Log.write("Unable to find xml start tag in profile")
                rawXML = taskOutput.output
            }

            
            
            if let results = try? PropertyListSerialization.propertyList(from: rawXML.data(using: String.Encoding.utf8)!, options: .mutableContainers, format: nil) as? [String : AnyObject] {
                if let expirationDate = results["ExpirationDate"] as? Date,
                    let creationDate = results["CreationDate"] as? Date,
                    let name = results["Name"] as? String,
                    let entitlements = results["Entitlements"] as? [String : AnyObject],
                    let applicationIdentifier = entitlements["application-identifier"] as? String,
                    let periodIndex = applicationIdentifier.firstIndex(of: ".") {
                        self.filename = filename
                        self.expires = expirationDate
                        self.created = creationDate
                        self.appID = applicationIdentifier.substring(from: applicationIdentifier.index(periodIndex, offsetBy: 1))
                        self.teamID = applicationIdentifier.substring(to: periodIndex)
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
    
    mutating func removeGetTaskAllow() {
        if let _ = entitlements.removeValue(forKey: "get-task-allow") {
            Log.write("Skipped get-task-allow entitlement!");
        } else {
            Log.write("get-task-allow entitlement not found!");
        }
    }
    
    mutating func update(trueAppID: String) {
        guard let oldIdentifier = entitlements["application-identifier"] as? String else {
            Log.write("Error reading application-identifier")
            return
        }
        let newIdentifier = teamID + "." + trueAppID
        entitlements["application-identifier"] = newIdentifier as AnyObject
        Log.write("Updated application-identifier from '\(oldIdentifier)' to '\(newIdentifier)'")
        // TODO: update any other wildcard entitlements
    }
    
    func getEntitlementsPlist() -> String? {
        let data = PropertyListSerialization.dataFromPropertyList(entitlements, format: PropertyListSerialization.PropertyListFormat.xml, errorDescription: nil)!
        return String(data: data, encoding: .utf8)
    }
}
