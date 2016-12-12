//
//  Log.swift
//  iOS App Signer
//
//  Created by Daniel Radtke on 11/14/15.
//  Copyright © 2015 Daniel Radtke. All rights reserved.
//

import Foundation
class Log {
    static let mainBundle = Bundle.main
    static let bundleID = mainBundle.bundleIdentifier
    static let bundleName = mainBundle.infoDictionary!["CFBundleName"]
    static let bundleVersion = mainBundle.infoDictionary!["CFBundleShortVersionString"]
    static let tempDirectory = NSTemporaryDirectory()
    static var logName = Log.tempDirectory.stringByAppendingPathComponent("\(Log.bundleID!)-\(Date().timeIntervalSince1970).log")
    
    static func write(_ value:String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        
        if let outputStream = OutputStream(toFileAtPath: logName, append: true) {
            outputStream.open()
            let text = "\(formatter.string(from: Date())) \(value)\n"
            let data = text.data(using: String.Encoding.utf8, allowLossyConversion: false)!
            outputStream.write((data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count), maxLength: data.count)
            outputStream.close()
        }
        NSLog(value)
    }
}
