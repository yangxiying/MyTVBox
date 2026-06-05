import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSubscriptionSheet: Bool = false

    var body: some View {
        Group {
            if appState.subscriptions.isEmpty {
                // 首次启动引导
                WelcomeView(showSubscriptionSheet: $showSubscriptionSheet)
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            AddSubscriptionView()
                .environmentObject(appState)
        }
        .task {
            appState.loadSubscriptions()
            if appState.hasActiveSubscription {
                await appState.loadConfig()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
