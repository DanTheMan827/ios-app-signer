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
        let fileManager = FileManager()
        
        guard let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return [] }

        let preMacOSSequouiaPath = libraryDirectory
            .path
            .stringByAppendingPathComponent("MobileDevice/Provisioning Profiles")
        
        let macOSSequoiaPath = libraryDirectory
            .path
            .stringByAppendingPathComponent("Developer/Xcode/UserData/Provisioning Profiles")
        
        let profiles = [preMacOSSequouiaPath, macOSSequoiaPath]
            .flatMap { (profilesPath: String) -> [String] in
                let contents = (try? fileManager.contentsOfDirectory(atPath: profilesPath)) ?? []
                return contents.map { (profile: String) -> String in
                    profilesPath.stringByAppendingPathComponent(profile)
                }
            }
            .filter { path in
                path.pathExtension == "mobileprovision"
            }
            .compactMap { path in
                ProvisioningProfile(filename: path)
            }
            .sorted { lhs, rhs in
                lhs.created.timeIntervalSince1970 > rhs.created.timeIntervalSince1970
            }
        
        var names = Set<String>()
        return profiles.filter { profile in
            let inserted = names.insert("\(profile.name)\(profile.appID)").inserted
            if inserted {
                NSLog("\(profile.name), \(profile.created)")
            }
            return inserted
        }
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
