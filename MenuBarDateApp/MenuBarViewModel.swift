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
            Group {
                if let icon = menuBarViewModel.combinedIcon {
                    icon
                }
            }
            .help(menuBarViewModel.iconTooltip)
        }
        .menuBarExtraStyle(.window)
    }
}
