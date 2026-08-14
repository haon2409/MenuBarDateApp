import SwiftUI
import Combine

@main
struct MenuBarDateApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                if let icon = viewModel.calendarIcon {
                    icon
                }

                Text(viewModel.dateString)
                    .font(.system(size: 14, weight: .medium))
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var calendarIcon: Image?
    @Published var dateString: String = ""

    private var timer: AnyCancellable?

    // Cache để tránh render lại icon khi ngày chưa thay đổi
    private var lastDateString: String = ""
    private var lastWeekday: String = ""

    init() {
        updateDate()

        timer = Timer.publish(
            every: 60,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.updateDate()
        }
    }

    deinit {
        timer?.cancel()
    }

    func updateDate() {
        let date = Date()
        let calendar = Calendar.current

        // MARK: Date

        let day = calendar.component(.day, from: date)

        let totalDays =
            calendar.range(
                of: .day,
                in: .month,
                for: date
            )?.count ?? 31

        let newDateString = "\(day)/\(totalDays)"

        // MARK: Weekday

        let weekdayIndex = calendar.component(
            .weekday,
            from: date
        )

        let newWeekday = getVietnameseWeekday(weekdayIndex)

        // Nếu ngày và thứ không thay đổi thì không cần
        // cập nhật UI hoặc render lại icon.
        guard newDateString != lastDateString ||
              newWeekday != lastWeekday else {
            return
        }

        // Lưu trạng thái mới
        lastDateString = newDateString
        lastWeekday = newWeekday

        // Cập nhật text
        dateString = newDateString

        // MARK: Calendar Icon

        // Canvas cao 24pt thay vì 20pt.
        // Calendar card thực tế vẫn 26 x 20pt.
        //
        // offset -2 được áp dụng bên trong ImageRenderer
        // để dịch chính bitmap của calendar lên 2pt.
        let iconView = ZStack {
            Color.clear

            CalendarCardView(weekday: newWeekday)
                .offset(y: -2)
        }
        .frame(
            width: 24,
            height: 24
        )

        let renderer = ImageRenderer(
            content: iconView
        )

        renderer.scale =
            NSScreen.main?.backingScaleFactor ?? 2.0

        renderer.isOpaque = false

        if let nsImage = renderer.nsImage {
            calendarIcon = Image(nsImage: nsImage)
        }
    }

    private func getVietnameseWeekday(
        _ index: Int
    ) -> String {
        switch index {
        case 1:
            return "CN"
        case 2:
            return "T2"
        case 3:
            return "T3"
        case 4:
            return "T4"
        case 5:
            return "T5"
        case 6:
            return "T6"
        case 7:
            return "T7"
        default:
            return ""
        }
    }
}

// MARK: - Calendar Card View

struct CalendarCardView: View {
    let weekday: String

    private let cardWidth: CGFloat = 24
    private let cardHeight: CGFloat = 20
    private let cornerRadius: CGFloat = 3.5

    var body: some View {
        ZStack(alignment: .top) {
            // Nền trắng
            Color.white

            VStack(spacing: 0) {
                // Dải đỏ phía trên
                Color.red
                    .frame(height: 5)

                // Thứ trong tuần
                Text(weekday)
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundColor(.black)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .padding(.bottom, 1)
            }
        }
        .frame(
            width: cardWidth,
            height: cardHeight
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.15),
                lineWidth: 0.5
            )
        )
    }
}
