import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TonightView()
                .tabItem {
                    Image(systemName: "moon.fill")
                    Text("Tonight")
                }
                .tag(0)
            
            TimelineView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Timeline")
                }
                .tag(1)
            
            DashboardView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Dashboard")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}

#Preview {
    MainTabView()
}
