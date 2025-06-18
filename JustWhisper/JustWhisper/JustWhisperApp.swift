//
//  JustWhisperApp.swift
//  JustWhisper
//
//  Created by Scott Soifer on 6/16/25.
//

import SwiftUI
import Cocoa

@main
struct JustWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene - app runs in menu bar only
        Settings {
            EmptyView()
        }
    }
}
