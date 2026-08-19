import SwiftUI

@main
struct MenuBarDateApp: App {
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    @StateObject private var popupViewModel = CalendarPopupViewModel()

    var body: some Scene {
        MenuBarExtra {
            CalendarPopupView(viewModel: popupViewModel)
                .environmentObject(menuBarViewModel)
        } label: {
            if let icon = menuBarViewModel.combinedIcon {
                icon
            }
        }
        .menuBarExtraStyle(.window)
    }
}
