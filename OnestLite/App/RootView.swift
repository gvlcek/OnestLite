import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                ProgressView()
            case .loggedOut:
                LoginView(auth: environment.auth, notice: session.notice) {
                    session.didLogin()
                }
            case .loggedIn:
                LoansView(repository: environment.loans)
            }
        }
        // Nuevo `id` en cada login/logout: ningún ViewModel ni dato del usuario anterior sobrevive.
        .id(session.generation)
        .task { await session.start() }
    }
}
