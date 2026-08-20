import Foundation
import SwiftUI
import Combine

enum CalendarTab: String {
    case solar = "Dương Lịch"
    case lunar = "Âm Lịch"
}

@MainActor
final class CalendarPopupViewModel: ObservableObject {
    @Published var currentDate: Date = Date()
    @Published var days: [DayModel] = []
    @Published var isLoggedIn: Bool = false
    @Published var showAddModal: Bool = false
    @Published var selectedDateStr: String = ""
    
    // Thuộc tính Form cơ bản
    @Published var modalTitle: String = ""
    @Published var modalDesc: String = ""
    @Published var isTaskMode: Bool = true
    
    // Thuộc tính cho Edit Mode
    @Published var isEditMode: Bool = false
    private var editingItemId: String? = nil
    private var editingItemDateStr: String? = nil
    
    // Thuộc tính cho Tính năng Repeat
    @Published var isRepeat: Bool = false
    @Published var repeatInterval: Int = 1
    @Published var repeatUnit: String = "days" // "days", "weeks", "months", "years"
    @Published var repeatTimes: String = "3"
    
    @Published var isLoading: Bool = false // Biến trạng thái loading mới
    
    @Published var selectedTab: CalendarTab = .solar
    
    private let calendar = Calendar.current
    private let auth = GoogleAuthManager.shared
    
    init() {
        generateCalendarGrid()
        isLoggedIn = auth.isLoggedIn
    }
    
    func onPopupAppear() {
        currentDate = Date()
        generateCalendarGrid()
        if isLoggedIn {
            Task { await fetchDataFromGoogle() }
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
            if isLoggedIn { Task { await fetchDataFromGoogle() } }
        }
    }
    
    func goToToday() {
        currentDate = Date()
        generateCalendarGrid()
        if isLoggedIn { Task { await fetchDataFromGoogle() } }
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
        let startOffset = firstWeekday == 1 ? 6 : firstWeekday - 2
        
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
        
        for i in 1...daysInMonth {
            let d = calendar.date(byAdding: .day, value: i - 1, to: firstDayOfMonth)!
            appendDay(date: d, isCurrentMonth: true, today: today)
        }
        
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
            auth.logout()
            isLoggedIn = false
            for i in days.indices { days[i].items.removeAll() }
        } else {
            auth.login()
            Task {
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if auth.isLoggedIn {
                        await MainActor.run { self.isLoggedIn = true }
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        await fetchDataFromGoogle()
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Fetch Google Data
    func fetchDataFromGoogle(isRetry: Bool = false) async {
        isLoading = true // Bật trạng thái tải
        defer { isLoading = false } // Đảm bảo luôn tắt khi kết thúc hàm
        
        guard let token = await auth.refreshAccessTokenIfNeeded(forceRefresh: isRetry) else { return }
        for i in days.indices { days[i].items.removeAll() }
        
        let eventsSuccess = await fetchCalendarEvents(token: token)
        let tasksSuccess = await fetchTasks(token: token)
        
        if (!eventsSuccess || !tasksSuccess) && !isRetry {
            await fetchDataFromGoogle(isRetry: true)
            return
        }
    }
    
    private var visibleDateRange: (start: Date, end: Date)? {
        guard let first = days.first?.date, let last = days.last?.date else { return nil }
        return (first, last)
    }
    
    private func fetchCalendarEvents(token: String) async -> Bool {
        guard let range = visibleDateRange else { return true }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
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
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { return false }
                if httpResponse.statusCode != 200 { return true }
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["items"] as? [[String: Any]] {
                for item in items {
                    guard let summary = item["summary"] as? String else { continue }
                    let dateStr: String
                    if let startDict = item["start"] as? [String: Any] {
                        if let dateTime = startDict["dateTime"] as? String { dateStr = String(dateTime.prefix(10)) }
                        else if let date = startDict["date"] as? String { dateStr = date }
                        else { continue }
                    } else { continue }
                    
                    let calendarItem = CalendarItem(id: item["id"] as? String ?? UUID().uuidString, title: summary, description: item["description"] as? String, type: .event, dateString: dateStr)
                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) { days[index].items.append(calendarItem) }
                }
            }
        } catch { }
        return true
    }

    private func fetchTasks(token: String) async -> Bool {
        guard let range = visibleDateRange else { return true }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let dueMin = formatter.string(from: range.start)
        let dueMax = formatter.string(from: calendar.date(byAdding: .day, value: 1, to: range.end)!)
        
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
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { return false }
                if httpResponse.statusCode != 200 { return true }
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tasks = json["items"] as? [[String: Any]] {
                for task in tasks {
                    guard let title = task["title"] as? String, let due = task["due"] as? String else { continue }
                    let dateStr = String(due.prefix(10))
                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) {
                        let calendarItem = CalendarItem(id: task["id"] as? String ?? UUID().uuidString, title: title, description: task["notes"] as? String, type: .task, isCompleted: (task["status"] as? String) == "completed", dateString: dateStr)
                        days[index].items.append(calendarItem)
                    }
                }
            }
        } catch { }
        return true
    }
    
    // MARK: - Popup height
    var totalRows: Int { return days.count / 7 }
    var popupHeight: CGFloat { return 90 + (CGFloat(totalRows) * 79) + 24 }
    
    // MARK: - Thao tác Dữ liệu
    func deleteItem(_ item: CalendarItem) async {
        guard let token = await auth.refreshAccessTokenIfNeeded() else { return }
        let urlString = item.type == .event ? "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(item.id)" : "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(item.id)"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }) {
                        days[dayIndex].items.removeAll(where: { $0.id == item.id })
                    }
                }
            }
        } catch { }
    }

    func toggleTaskStatus(_ item: CalendarItem) async {
        guard item.type == .task else { return }
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }), let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == item.id }) {
                days[dayIndex].items[itemIndex].isCompleted.toggle()
            }
        }
        guard let token = await auth.refreshAccessTokenIfNeeded() else { await rollbackStatus(item); return }
        
        let newStatus = !item.isCompleted ? "completed" : "needsAction"
        let urlString = "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(item.id)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["status": newStatus]
        if newStatus == "completed" {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            body["completed"] = formatter.string(from: Date())
        } else {
            body["completed"] = NSNull()
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    if let newToken = await auth.refreshAccessTokenIfNeeded(forceRefresh: true) {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse, !(200...299).contains(retryHttp.statusCode) { await rollbackStatus(item) }
                    } else { await rollbackStatus(item) }
                } else if !(200...299).contains(httpResponse.statusCode) { await rollbackStatus(item) }
            }
        } catch { await rollbackStatus(item) }
    }

    private func rollbackStatus(_ item: CalendarItem) async {
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }), let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == item.id }) {
                days[dayIndex].items[itemIndex].isCompleted.toggle()
            }
        }
    }
    
    // MARK: - Mở Modal Edit / Add
    func openEditModal(for item: CalendarItem) {
        self.modalTitle = item.title
        self.modalDesc = item.description ?? ""
        self.isTaskMode = (item.type == .task)
        self.isEditMode = true
        self.editingItemId = item.id
        self.editingItemDateStr = item.dateString
        self.showAddModal = true
    }

    func openAddModal(isTask: Bool, dateStr: String) {
        self.modalTitle = ""
        self.modalDesc = ""
        self.isTaskMode = isTask
        self.isEditMode = false
        self.editingItemId = nil
        self.selectedDateStr = dateStr
        
        self.isRepeat = false
        self.repeatInterval = 1
        self.repeatUnit = "days"
        self.repeatTimes = "3"
        
        // Reset tab về Dương Lịch khi mở modal mới
        self.selectedTab = .solar
        
        self.showAddModal = true
    }
    
    // MARK: - Helper Lặp thời gian
    private func calculateNextDate(dateString: String, interval: Int, unit: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        var components = DateComponents()
        switch unit {
        case "days": components.day = interval
        case "weeks": components.day = interval * 7
        case "months": components.month = interval
        case "years": components.year = interval
        default: break
        }
        
        if let nextDate = Calendar.current.date(byAdding: components, to: date) {
            return formatter.string(from: nextDate)
        }
        return dateString
    }
    
    // MARK: - Gửi Request Thêm Mới (POST)
    func submitAddItem() async {
        guard let token = await auth.refreshAccessTokenIfNeeded() else { return }
        
        let isTask = isTaskMode
        let newTitle = modalTitle.isEmpty ? "(Không có tiêu đề)" : modalTitle
        let newDesc = modalDesc
        
        let maxTimes = (isTask && isRepeat) ? max(1, min(Int(repeatTimes) ?? 3, 100)) : 1
        var currentIteratorDateStr = selectedDateStr
        
        await MainActor.run { self.showAddModal = false }
        
        for _ in 0..<maxTimes {
            let targetDate = currentIteratorDateStr
            let urlString = isTask
                ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks"
                : "https://www.googleapis.com/calendar/v3/calendars/primary/events"
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            var body: [String: Any] = [:]
            if isTask {
                body = [
                    "title": newTitle,
                    "notes": newDesc,
                    "due": "\(targetDate)T00:00:00.000Z"
                ]
            } else {
                body = [
                    "summary": newTitle,
                    "description": newDesc,
                    "start": ["date": targetDate],
                    "end": ["date": targetDate]
                ]
            }
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let newItemId = json["id"] as? String {
                        let newItem = CalendarItem(id: newItemId, title: newTitle, description: newDesc.isEmpty ? nil : newDesc, type: isTask ? .task : .event, isCompleted: false, dateString: targetDate)
                        
                        await MainActor.run {
                            if let dayIndex = self.days.firstIndex(where: { $0.dateString == targetDate }) {
                                self.days[dayIndex].items.append(newItem)
                            }
                        }
                    }
                } else {
                    await fetchDataFromGoogle()
                }
            } catch {
                await fetchDataFromGoogle()
            }
            
            if isTask && isRepeat {
                currentIteratorDateStr = calculateNextDate(dateString: currentIteratorDateStr, interval: repeatInterval, unit: repeatUnit)
            }
        }
    }
    
    // MARK: - Gửi Request Cập Nhật (PATCH)
    func submitEditItem() async {
        guard let id = editingItemId, let dateStr = editingItemDateStr, let token = await auth.refreshAccessTokenIfNeeded() else { return }
        let isTask = isTaskMode
        let newTitle = modalTitle
        let newDesc = modalDesc
        
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == dateStr }), let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == id }) {
                days[dayIndex].items[itemIndex].title = newTitle
                days[dayIndex].items[itemIndex].description = newDesc
                self.showAddModal = false
            }
        }
        
        let urlString = isTask ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(id)" : "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = isTask ? ["title": newTitle, "notes": newDesc] : ["summary": newTitle, "description": newDesc]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                await fetchDataFromGoogle()
            }
        } catch {
            await fetchDataFromGoogle()
        }
    }
}
