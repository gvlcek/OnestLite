import SwiftUI

@main
struct OnestLiteApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                // Las pruebas unitarias usan la app como host: no arrancamos la UI real.
                Color.clear
            } else {
                RootView()
                    .environmentObject(environment)
                    .environmentObject(environment.session)
            }
        }
    }
}
