//
//  JPBTApp.swift
//  JPBT
//
//  Created by Jozef Hollý on 17/03/2026.
//

import Sentry
import SwiftUI
import SwiftData

@main
struct JPBTApp: App {
  init() {
    SentrySDK.start { options in
      options.dsn =
        "https://b56ebb3843a5144dba4fa0c6a00bb8a7@o946083.ingest.us.sentry.io/4511240793227264"
      #if DEBUG
        options.environment = "debug"
        options.debug = true
      #else
        options.environment = "production"
        options.debug = false
      #endif
    }
  }

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Item.self,
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .modelContainer(sharedModelContainer)
  }
}
