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
            // Chỉ hiển thị 1 Image duy nhất đã gom cả Icon và Text
            if let icon = viewModel.combinedIcon {
                icon
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var combinedIcon: Image?

    private var timer: AnyCancellable?
    private var lastDateString: String = ""

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

        // MARK: Date & Weekday Setup
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let totalDays = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        let weekdayIndex = calendar.component(.weekday, from: date)
        let newWeekday = getVietnameseWeekday(weekdayIndex)

        // Tạo khóa kiểm tra thay đổi
        let newDateString = "\(day)/\(month)\(totalDays)-\(newWeekday)"
        guard newDateString != lastDateString else { return }
        lastDateString = newDateString

        // MARK: Detect Dark Mode cho Text
        // Xác định giao diện hệ thống để chỉnh màu chữ thủ công vì ImageRenderer chạy độc lập
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let textColor: Color = isDark ? .white : .black

        // MARK: - Gom tất cả vào 1 View
        let combinedView = HStack(alignment: .center, spacing: 6) {
            // 1. Icon lịch
            ZStack {
                Color.clear
                CalendarCardView(weekday: newWeekday)
                    .offset(y: -2)
            }
            .frame(width: 24, height: 24)

            // 2. Text Ngày/Tháng
            Text("\(day)/\(month)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
            
            // 3. Tổng số ngày với khung nền tròn
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3)) // Nền tối
                    .frame(width: 16, height: 16) // Kích thước khung nền tròn
                
                Text("\(totalDays)")
                    .font(.system(size: 14 * 0.7, weight: .bold)) // Giữ nguyên kích thước 0.7
                    .foregroundColor(.white) // Màu số (nên để trắng hoặc màu nổi trên nền tối)
            }
            .offset(x: -4, y: -2)
        }
        .fixedSize()

        // MARK: Render thành Image
        let renderer = ImageRenderer(content: combinedView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        renderer.isOpaque = false // Phải là false để nền trong suốt

        if let nsImage = renderer.nsImage {
            // KHÔNG set isTemplate = true để bảo toàn màu đỏ của lịch
            combinedIcon = Image(nsImage: nsImage)
        }
    }

    private func getVietnameseWeekday(_ index: Int) -> String {
        switch index {
        case 1: return "CN"
        case 2: return "T2"
        case 3: return "T3"
        case 4: return "T4"
        case 5: return "T5"
        case 6: return "T6"
        case 7: return "T7"
        default: return ""
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
            Color.white

            VStack(spacing: 0) {
                Color.red
                    .frame(height: 5)

                Text(weekday)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 1)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }
}
