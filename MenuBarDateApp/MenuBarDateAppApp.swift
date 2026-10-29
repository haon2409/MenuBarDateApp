import SwiftUI
import Combine

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var combinedIcon: Image?
    @Published var iconTooltip: String = ""

    private var timer: AnyCancellable?
    private var tideCancellable: AnyCancellable?
    private var lastDateString: String = ""
    private var lastTideSignature: String = ""

    init() {
        updateDate(force: true)

        timer = Timer.publish(
            every: 60,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.updateDate()
        }
        
        // Theo dõi thay đổi tide data để cập nhật icon
        tideCancellable = TideService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDate(force: true)
            }
    }

    deinit {
        timer?.cancel()
        tideCancellable?.cancel()
    }

    func updateDate(force: Bool = false) {
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

        // Signature gồm ngày + tide levels
        let tideLevels = TideService.shared.levelsForIcon()
        let tideSig = tideLevels.map { String(format: "%.1f", $0) }.joined(separator: ",")
        let newDateString = "\(day)/\(month)(\(totalDays))-\(newWeekday)-\(lunar.day)/\(lunar.month)(\(lunarTotalDays))"
        
        // Tooltip: mực nước cao nhất trong các cột icon
        if TideService.shared.isEnabled, let maxLevel = tideLevels.filter({ $0 > 0 }).max() {
            iconTooltip = String(format: "%.1fm", maxLevel)
        } else {
            iconTooltip = ""
        }
        
        if !force && newDateString == lastDateString && tideSig == lastTideSignature {
            return
        }
        lastDateString = newDateString
        lastTideSignature = tideSig

        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let textColor: Color = isDark ? .white : .black

        // MARK: - Gom tất cả vào 1 View
        let combinedView = HStack(alignment: .center, spacing: 6) {
            // Nửa 1: Icon Thứ (có biểu đồ triều nếu bật)
            CalendarCardView(
                weekday: newWeekday,
                tideLevels: TideService.shared.isEnabled ? tideLevels : [],
                redThreshold: TideService.shared.redThreshold,
                yellowThreshold: TideService.shared.yellowThreshold
            )
            
            // MARK: - Nửa 2: Thông tin chi tiết
            VStack(alignment: .leading, spacing: 1) {
                // Hàng 1: Dương lịch
                HStack(spacing: 2) {
                    Text("\(day)/\(month)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(textColor)
                        .frame(width: 36, alignment: .leading)
                    
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
                    .padding(.vertical, -0.5)
                
                // Hàng 2: Âm lịch
                HStack(spacing: 2) {
                    Text("\(lunar.day)/\(lunar.month)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(textColor.opacity(0.7))
                        .frame(width: 36, alignment: .leading)
                    
                    Text("\(lunarTotalDays)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor.opacity(0.6))
                        .frame(width: 16, alignment: .center)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(width: 54)
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

// MARK: - Calendar Card View (ô Thứ + biểu đồ triều chìm dưới text)

struct CalendarCardView: View {
    let weekday: String
    var tideLevels: [Double] = []
    var redThreshold: Double = 3.9
    var yellowThreshold: Double = 3.4

    private let cardWidth: CGFloat = 24
    private let cardHeight: CGFloat = 20
    private let cornerRadius: CGFloat = 3.5

    var body: some View {
        ZStack(alignment: .top) {
            Color.white

            // Biểu đồ cột nằm dưới, chìm dưới text
            if !tideLevels.isEmpty {
                GeometryReader { geo in
                    let count = max(tideLevels.count, 1)
                    let colW = geo.size.width / CGFloat(count)
                    let maxH = geo.size.height - 1
                    
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(tideLevels.enumerated()), id: \.offset) { _, level in
                            let ratio = redThreshold > 0 ? min(1.0, level / redThreshold) : 0
                            let h = max(level > 0 ? 1 : 0, ratio * maxH)
                            
                            Rectangle()
                                .fill(barColor(for: level))
                                .frame(width: colW, height: h)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }

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
    
    private func barColor(for level: Double) -> Color {
        if level >= redThreshold {
            return Color(red: 1, green: 0, blue: 0).opacity(0.85)
        } else if level >= yellowThreshold {
            return Color(red: 1, green: 0.84, blue: 0).opacity(0.85)
        } else if level > 0 {
            return Color(red: 0.21, green: 0.635, blue: 0.922).opacity(0.85)
        }
        return .clear
    }
}
