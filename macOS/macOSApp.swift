//
//  macOSApp.swift
//  macOS
//
//  Created by Sergei Saliukov on 19.02.2026.
//

import SwiftUI

@main
struct macOSApp: App {
    @StateObject private var store = ValueStore()
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
