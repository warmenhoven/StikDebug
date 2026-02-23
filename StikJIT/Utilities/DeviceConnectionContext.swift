//
//  DeviceConnectionContext.swift
//  StikJIT
//
//  Created by Stephen.
//

import Foundation

enum DeviceConnectionContext {
    static var isUsingExternalDevice: Bool {
        return targetIPAddress != "127.0.0.1"
    }
    
    static var requiresLoopbackVPN: Bool {
        false
    }
    
    static var targetIPAddress: String {
        let stored = UserDefaults.standard.string(forKey: "customTargetIP")
        if let stored, !stored.isEmpty {
            return stored
        }
        return "127.0.0.1"
    }
}
