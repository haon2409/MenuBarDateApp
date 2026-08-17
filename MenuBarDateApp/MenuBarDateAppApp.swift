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

        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let totalDays = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        let weekdayIndex = calendar.component(.weekday, from: date)
        let newWeekday = getVietnameseWeekday(weekdayIndex)

        // Lấy ngày Âm lịch
        let lunar = LunarEngine.getLunarDate(dd: day, mm: month, yyyy: year)
        
        // Tính tổng số ngày trong tháng Âm lịch hiện tại
        let daysToAdd = 30 - lunar.day
        let futureDate = calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
        let futureDay = calendar.component(.day, from: futureDate)
        let futureMonth = calendar.component(.month, from: futureDate)
        let futureYear = calendar.component(.year, from: futureDate)
        let futureLunar = LunarEngine.getLunarDate(dd: futureDay, mm: futureMonth, yyyy: futureYear)
        let lunarTotalDays = (futureLunar.day == 30) ? 30 : 29

        // Tạo khóa kiểm tra thay đổi
        let newDateString = "\(day)/\(month)(\(totalDays))-\(newWeekday)-\(lunar.day)/\(lunar.month)(\(lunarTotalDays))"
        guard newDateString != lastDateString else { return }
        lastDateString = newDateString

        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let textColor: Color = isDark ? .white : .black

        // MARK: - Gom tất cả vào 1 View
        let combinedView = HStack(alignment: .center, spacing: 6) {
            // Nửa 1: Icon Thứ
            CalendarCardView(weekday: newWeekday)
            
            // MARK: - Nửa 2: Thông tin chi tiết
            VStack(alignment: .leading, spacing: 2) {
                // Hàng 1: Dương lịch
                HStack(spacing: 2) { // Giảm spacing xuống 2
                    Text("\(day)/\(month)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                        .frame(width: 30, alignment: .leading)
                    
                    Text("\(totalDays)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(isDark ? .white : .black)
                        .frame(width: 16, alignment: .center)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                
                // Đường kẻ ngang
                Divider()
                    .frame(height: 0.5)
                    .background(textColor.opacity(0.2))
                
                // Hàng 2: Âm lịch
                HStack(spacing: 2) { // Giảm spacing xuống 2
                    Text("\(lunar.day)/\(lunar.month)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(textColor.opacity(0.7))
                        .frame(width: 30, alignment: .leading)
                    
                    Text("\(lunarTotalDays)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor.opacity(0.6))
                        .frame(width: 16, alignment: .center)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(width: 48) // Thu nhỏ tổng chiều rộng tương ứng để ép sát hơn
        }
        .fixedSize()

        // MARK: Render thành Image
        let renderer = ImageRenderer(content: combinedView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        renderer.isOpaque = false

        if let nsImage = renderer.nsImage {
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
