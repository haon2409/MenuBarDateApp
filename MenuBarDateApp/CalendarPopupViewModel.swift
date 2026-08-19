import Foundation
import SwiftUI
import Combine

@MainActor
final class CalendarPopupViewModel: ObservableObject {
    @Published var currentDate: Date = Date()
    @Published var days: [DayModel] = []
    @Published var isLoggedIn: Bool = false
    @Published var showAddModal: Bool = false
    @Published var selectedDateStr: String = ""
    
    // Thuộc tính Form
    @Published var modalTitle: String = ""
    @Published var modalDesc: String = ""
    @Published var isTaskMode: Bool = true
    
    private let calendar = Calendar.current
    private let auth = GoogleAuthManager.shared
    
    init() {
        generateCalendarGrid()
        
        // Đồng bộ trạng thái login
        isLoggedIn = auth.isLoggedIn
        if isLoggedIn {
            Task {
                await fetchDataFromGoogle()
            }
        }
    }
    
    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Tháng' M, yyyy"
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.string(from: currentDate)
    }
    
    func changeMonth(by offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: currentDate) {
            currentDate = newDate
            generateCalendarGrid()
            
            if isLoggedIn {
                Task { await fetchDataFromGoogle() }
            }
        }
    }
    
    func goToToday() {
        currentDate = Date()
        generateCalendarGrid()
        
        if isLoggedIn {
            Task { await fetchDataFromGoogle() }
        }
    }
    
    func generateCalendarGrid() {
        days.removeAll()
        
        let year = calendar.component(.year, from: currentDate)
        let month = calendar.component(.month, from: currentDate)
        let today = Date()
        
        guard let firstDayOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else { return }
        
        let daysInMonth = range.count
        var firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Chỉnh thứ 2 là đầu tuần (Swift trả CN = 1, T2 = 2)
        let startOffset = firstWeekday == 1 ? 6 : firstWeekday - 2
        
        // 1. Ngày tháng trước
        if startOffset > 0 {
            if let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: firstDayOfMonth),
               let prevRange = calendar.range(of: .day, in: .month, for: prevMonthDate) {
                let prevDays = prevRange.count
                for i in (prevDays - startOffset + 1)...prevDays {
                    let d = calendar.date(byAdding: .day, value: i - prevDays - 1, to: firstDayOfMonth)!
                    appendDay(date: d, isCurrentMonth: false, today: today)
                }
            }
        }
        
        // 2. Ngày tháng hiện tại
        for i in 1...daysInMonth {
            let d = calendar.date(byAdding: .day, value: i - 1, to: firstDayOfMonth)!
            appendDay(date: d, isCurrentMonth: true, today: today)
        }
        
        // 3. Ngày tháng sau
        let remainder = days.count % 7
        if remainder != 0 {
            let endOffset = 7 - remainder
            if let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: firstDayOfMonth) {
                for i in 1...endOffset {
                    let d = calendar.date(byAdding: .day, value: i - 1, to: nextMonthDate)!
                    appendDay(date: d, isCurrentMonth: false, today: today)
                }
            }
        }
    }
    
    private func appendDay(date: Date, isCurrentMonth: Bool, today: Date) {
        let dayNum = calendar.component(.day, from: date)
        let m = calendar.component(.month, from: date)
        let y = calendar.component(.year, from: date)
        
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let lunarInfo = LunarEngine.getLunarDate(dd: dayNum, mm: m, yyyy: y)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        
        let dayModel = DayModel(
            date: date,
            dayNumber: dayNum,
            lunarDay: lunarInfo.day,
            lunarMonth: lunarInfo.month,
            isCurrentMonth: isCurrentMonth,
            isToday: isToday,
            items: [],
            dateString: dateStr
        )
        days.append(dayModel)
    }
    
    // MARK: - Login / Logout
    func login() {
        if auth.isLoggedIn {
            // Logout
            auth.logout()
            isLoggedIn = false
            for i in days.indices {
                days[i].items.removeAll()
            }
        } else {
            // Login
            auth.login()
            
            // Lắng nghe khi login thành công
            Task {
                // Chờ tối đa 60 giây
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 giây
                    
                    if auth.isLoggedIn {
                        await MainActor.run {
                            self.isLoggedIn = true
                        }
                        // Đợi thêm 1 chút để token ổn định
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        await fetchDataFromGoogle()
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Fetch Google Data
    func fetchDataFromGoogle() async {
        print("🔄 Bắt đầu fetchDataFromGoogle...")
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            print("❌ Không lấy được token")
            return
        }
        
        print("✅ Có token, bắt đầu fetch...")
        
        // Clear items cũ
        for i in days.indices {
            days[i].items.removeAll()
        }
        
        await fetchCalendarEvents(token: token)
        await fetchTasks(token: token)
        
        print("✅ Fetch xong. Tổng số item:", days.flatMap { $0.items }.count)
    }
    
    // Thêm hàm helper này vào ViewModel
    private var visibleDateRange: (start: Date, end: Date)? {
        guard let first = days.first?.date,
              let last = days.last?.date else { return nil }
        return (first, last)
    }
    
    private func fetchCalendarEvents(token: String) async {
        guard let range = visibleDateRange else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Mở rộng thêm 1 ngày cuối để an toàn
        let timeMax = calendar.date(byAdding: .day, value: 1, to: range.end)!
        
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            .init(name: "timeMin", value: formatter.string(from: range.start)),
            .init(name: "timeMax", value: formatter.string(from: timeMax)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "250")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                
                print("📅 Nhận được \(items.count) events trong khoảng \(days.first?.dateString ?? "") → \(days.last?.dateString ?? "")")
                
                for item in items {
                    guard let summary = item["summary"] as? String else { continue }
                    
                    let dateStr: String
                    if let startDict = item["start"] as? [String: Any] {
                        if let dateTime = startDict["dateTime"] as? String {
                            dateStr = String(dateTime.prefix(10))
                        } else if let date = startDict["date"] as? String {
                            dateStr = date
                        } else { continue }
                    } else { continue }
                    
                    let calendarItem = CalendarItem(
                        id: item["id"] as? String ?? UUID().uuidString,
                        title: summary,
                        description: item["description"] as? String,
                        type: .event,
                        dateString: dateStr
                    )
                    
                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) {
                        days[index].items.append(calendarItem)
                    }
                }
            }
        } catch {
            print("Calendar fetch error:", error)
        }
    }
    
    private func fetchTasks(token: String) async {
        guard let range = visibleDateRange else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let dueMin = formatter.string(from: range.start)
        let dueMax = formatter.string(from: calendar.date(byAdding: .day, value: 1, to: range.end)!)
        
        // Dùng @default giống extension
        var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks")!
        components.queryItems = [
            .init(name: "dueMin", value: dueMin),
            .init(name: "dueMax", value: dueMax),
            .init(name: "showCompleted", value: "true"),
            .init(name: "showHidden", value: "true"),
            .init(name: "maxResults", value: "100")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tasks = json["items"] as? [[String: Any]] {
                
                print("✅ Nhận được \(tasks.count) tasks (dùng @default + dueMin/dueMax)")
                
                var addedCount = 0
                
                for task in tasks {
                    guard let title = task["title"] as? String,
                          let due = task["due"] as? String else { continue }
                    
                    let dateStr = String(due.prefix(10))
                    
                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) {
                        let calendarItem = CalendarItem(
                            id: task["id"] as? String ?? UUID().uuidString,
                            title: title,
                            description: task["notes"] as? String,
                            type: .task,
                            isCompleted: (task["status"] as? String) == "completed",
                            dateString: dateStr
                        )
                        days[index].items.append(calendarItem)
                        addedCount += 1
                    }
                }
                
                print("✅ Đã thêm \(addedCount) tasks vào lịch")
            }
        } catch {
            print("Tasks fetch error:", error)
        }
    }
    
    // MARK: - Popup height
    var totalRows: Int {
        let count = days.count
        return count / 7
    }

    var popupHeight: CGFloat {
        let cellHeight: CGFloat = 75 + 4
        let headerHeight: CGFloat = 90
        let padding: CGFloat = 24
        return headerHeight + (CGFloat(totalRows) * cellHeight) + padding
    }
}
