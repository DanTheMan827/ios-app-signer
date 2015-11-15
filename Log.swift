//
//  Log.swift
//  iOS App Signer
//
//  Created by Daniel Radtke on 11/14/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Foundation
class Log {
    static let mainBundle = NSBundle.mainBundle()
    static let bundleID = mainBundle.bundleIdentifier
    static let bundleName = mainBundle.infoDictionary!["CFBundleName"]
    static let bundleVersion = mainBundle.infoDictionary!["CFBundleShortVersionString"]
    static let tempDirectory = NSTemporaryDirectory()
    static var logName = Log.tempDirectory.stringByAppendingPathComponent("\(Log.bundleID!)-\(NSDate().timeIntervalSince1970).log")
    
    static func write(value:String) {
        let formatter = NSDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        
        if let outputStream = NSOutputStream(toFileAtPath: logName, append: true) {
            outputStream.open()
            let text = "\(formatter.stringFromDate(NSDate())) \(value)\n"
            let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            outputStream.write(UnsafePointer(data.bytes), maxLength: data.length)
            outputStream.close()
        }
        NSLog(value)
    }
}