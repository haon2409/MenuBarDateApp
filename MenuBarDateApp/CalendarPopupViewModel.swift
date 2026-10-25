import Foundation
import SwiftUI
import Combine
import AppKit

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
    
    @Published var profileImage: NSImage? = nil
    
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
    
    @Published var isLoading: Bool = false
    
    @Published var selectedTab: CalendarTab = .solar
    
    // MARK: - Expense State
    @Published var showExpenseModal: Bool = false
    @Published var expenseDateStr: String = ""
    @Published private(set) var allExpenses: [String: [ExpenseItem]] = [:]
    
    private let expenseFileName = "expenses.json"
    private var driveExpenseFileId: String? = nil
    
    private let calendar = Calendar.current
    private let auth = GoogleAuthManager.shared
    
    // MARK: - Computed cho Picker Tháng / Năm
    var currentMonth: Int {
        calendar.component(.month, from: currentDate)
    }
    
    var currentYear: Int {
        calendar.component(.year, from: currentDate)
    }
    
    var yearRange: [Int] {
        let y = calendar.component(.year, from: Date())
        return Array((y - 50)...(y + 50))
    }
    
    // MARK: - Expense Computed
    var expensesForSelectedDay: [ExpenseItem] {
        allExpenses[expenseDateStr] ?? []
    }
    
    var expenseDayTotal: Int {
        expensesForSelectedDay.reduce(0) { $0 + $1.amount }
    }
    
    var monthExpenseTotal: Int {
        let prefix = String(format: "%04d-%02d", currentYear, currentMonth)
        return allExpenses
            .filter { $0.key.hasPrefix(prefix) }
            .flatMap { $0.value }
            .reduce(0) { $0 + $1.amount }
    }
    
    init() {
        generateCalendarGrid()
        isLoggedIn = auth.isLoggedIn
        loadExpensesLocally()
    }
    
    // MARK: - Helper xử lý khi token chết
    private func handleAuthFailure() {
        auth.logout()
        isLoggedIn = false
        profileImage = nil
        FileLogger.shared.logError(context: "handleAuthFailure", message: "Phiên đăng nhập hết hạn → đã logout tự động")
    }
    
    // MARK: - Hàm onPopupAppear
    func onPopupAppear() {
        currentDate = Date()
        generateCalendarGrid()
        if isLoggedIn {
            Task {
                await fetchAndLoadImage()
                await fetchDataFromGoogle()
                await syncExpensesFromDrive()
            }
        } else {
            loadExpensesLocally()
        }
    }
    
    func fetchAndLoadImage() async {
        guard let url = await auth.fetchProfileImageURL() else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                await MainActor.run {
                    self.profileImage = image
                }
            }
        } catch {
            print("Lỗi tải data ảnh: \(error)")
            FileLogger.shared.logError(context: "fetchAndLoadImage", message: "Lỗi tải data ảnh: \(error.localizedDescription)")
        }
    }
    
    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Tháng' M, yyyy"
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.string(from: currentDate)
    }
    
    // MARK: - Set Tháng / Năm từ Picker
    func setMonth(_ month: Int) {
        guard (1...12).contains(month), month != currentMonth else { return }
        
        var components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        components.month = month
        
        if let year = components.year,
           let day = components.day,
           let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
           let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
            components.day = min(day, range.count)
        }
        
        guard let newDate = calendar.date(from: components) else { return }
        currentDate = newDate
        generateCalendarGrid()
        if isLoggedIn { Task { await fetchDataFromGoogle() } }
    }
    
    func setYear(_ year: Int) {
        guard yearRange.contains(year), year != currentYear else { return }
        
        var components = calendar.dateComponents([.year, .month, .day], from: currentDate)
        components.year = year
        
        if let month = components.month,
           let day = components.day,
           let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
           let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
            components.day = min(day, range.count)
        }
        
        guard let newDate = calendar.date(from: components) else { return }
        currentDate = newDate
        generateCalendarGrid()
        if isLoggedIn { Task { await fetchDataFromGoogle() } }
    }
    
    func changeMonth(by offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: currentDate) {
            currentDate = newDate
            generateCalendarGrid()
            if isLoggedIn { Task { await fetchDataFromGoogle() } }
        }
    }
    
    func goToToday() {
        guard !calendar.isDate(currentDate, equalTo: Date(), toGranularity: .month) else { return }
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
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
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
    
    func login() {
        if auth.isLoggedIn {
            auth.logout()
            isLoggedIn = false
            profileImage = nil
        } else {
            NSApp.keyWindow?.orderOut(nil)
            auth.login()
            Task {
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if auth.isLoggedIn {
                        await MainActor.run { self.isLoggedIn = true }
                        await fetchAndLoadImage()
                        await fetchDataFromGoogle()
                        await syncExpensesFromDrive()
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Fetch Google Data
    func fetchDataFromGoogle(isRetry: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        guard let token = await auth.refreshAccessTokenIfNeeded(forceRefresh: isRetry) else {
            FileLogger.shared.logError(context: "fetchDataFromGoogle", message: "Không lấy được access token từ refreshAccessTokenIfNeeded (isRetry: \(isRetry))")
            await MainActor.run { handleAuthFailure() }
            return
        }
        for i in days.indices { days[i].items.removeAll() }
        
        let eventsSuccess = await fetchCalendarEvents(token: token)
        let tasksSuccess = await fetchTasks(token: token)
        
        if (!eventsSuccess || !tasksSuccess) && !isRetry {
            FileLogger.shared.logError(context: "fetchDataFromGoogle", message: "Fetch thất bại (eventsSuccess: \(eventsSuccess), tasksSuccess: \(tasksSuccess)), tiến hành thử lại...")
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
                if httpResponse.statusCode == 401 {
                    FileLogger.shared.logError(context: "fetchCalendarEvents", message: "HTTP Status 401 Unauthorized")
                    return false
                }
                if httpResponse.statusCode != 200 {
                    FileLogger.shared.logError(context: "fetchCalendarEvents", message: "HTTP Status \(httpResponse.statusCode)")
                    return true
                }
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
                    
                    let calendarItem = CalendarItem(
                        id: item["id"] as? String ?? UUID().uuidString,
                        title: summary,
                        description: item["description"] as? String,
                        type: .event,
                        dateString: dateStr
                    )

                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) {
                        if !days[index].items.contains(where: { $0.id == calendarItem.id }) {
                            days[index].items.append(calendarItem)
                        }
                    }
                }
            }
        } catch {
            FileLogger.shared.logError(context: "fetchCalendarEvents", message: error.localizedDescription)
        }
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
                if httpResponse.statusCode == 401 {
                    FileLogger.shared.logError(context: "fetchTasks", message: "HTTP Status 401 Unauthorized")
                    return false
                }
                if httpResponse.statusCode != 200 {
                    FileLogger.shared.logError(context: "fetchTasks", message: "HTTP Status \(httpResponse.statusCode)")
                    return true
                }
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["items"] as? [[String: Any]] {
                for item in items {
                    guard let title = item["title"] as? String else { continue }
                    let dateStr: String
                    if let due = item["due"] as? String {
                        dateStr = String(due.prefix(10))
                    } else {
                        continue
                    }
                    
                    let isCompleted = (item["status"] as? String) == "completed"
                    
                    let calendarItem = CalendarItem(
                        id: item["id"] as? String ?? UUID().uuidString,
                        title: title,
                        description: item["notes"] as? String,
                        type: .task,
                        isCompleted: isCompleted,
                        dateString: dateStr
                    )
                    
                    if let index = days.firstIndex(where: { $0.dateString == dateStr }) {
                        if !days[index].items.contains(where: { $0.id == calendarItem.id }) {
                            days[index].items.append(calendarItem)
                        }
                    }
                }
            }
        } catch {
            FileLogger.shared.logError(context: "fetchTasks", message: error.localizedDescription)
        }
        return true
    }
    
    var totalRows: Int { return days.count / 7 }
    var popupHeight: CGFloat { return 90 + (CGFloat(totalRows) * 79) + 24 }
    
    func deleteItem(_ item: CalendarItem) async {
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            FileLogger.shared.logError(context: "deleteItem", message: "Không thể refresh access token")
            await MainActor.run { handleAuthFailure() }
            return
        }
        
        let urlString = item.type == .task
            ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(item.id)"
            : "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(item.id)"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }) {
                days[dayIndex].items.removeAll { $0.id == item.id }
            }
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    FileLogger.shared.logError(context: "deleteItem", message: "HTTP 401 Unauthorized")
                    await MainActor.run { handleAuthFailure() }
                    await fetchDataFromGoogle()
                } else if !(200...299).contains(httpResponse.statusCode) && httpResponse.statusCode != 204 {
                    FileLogger.shared.logError(context: "deleteItem", message: "HTTP Status \(httpResponse.statusCode)")
                    await fetchDataFromGoogle()
                }
            }
        } catch {
            FileLogger.shared.logError(context: "deleteItem", message: error.localizedDescription)
            await fetchDataFromGoogle()
        }
    }
    
    func toggleTaskStatus(_ item: CalendarItem) async {
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }),
               let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == item.id }) {
                days[dayIndex].items[itemIndex].isCompleted.toggle()
            }
        }
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            FileLogger.shared.logError(context: "toggleTaskStatus", message: "Không thể refresh access token")
            await rollbackStatus(item)
            await MainActor.run { handleAuthFailure() }
            return
        }
        
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
                    FileLogger.shared.logError(context: "toggleTaskStatus", message: "HTTP 401 Unauthorized, thử refresh token...")
                    if let newToken = await auth.refreshAccessTokenIfNeeded(forceRefresh: true) {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse, !(200...299).contains(retryHttp.statusCode) {
                            FileLogger.shared.logError(context: "toggleTaskStatus", message: "Retry HTTP Status \(retryHttp.statusCode)")
                            await rollbackStatus(item)
                            if retryHttp.statusCode == 401 {
                                await MainActor.run { handleAuthFailure() }
                            }
                        }
                    } else {
                        FileLogger.shared.logError(context: "toggleTaskStatus", message: "Không thể force refresh token")
                        await rollbackStatus(item)
                        await MainActor.run { handleAuthFailure() }
                    }
                } else if !(200...299).contains(httpResponse.statusCode) {
                    FileLogger.shared.logError(context: "toggleTaskStatus", message: "HTTP Status \(httpResponse.statusCode)")
                    await rollbackStatus(item)
                }
            }
        } catch {
            FileLogger.shared.logError(context: "toggleTaskStatus", message: error.localizedDescription)
            await rollbackStatus(item)
        }
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
    
    private func getSolarDateFromLunar(lunarDay: Int, lunarMonth: Int, year: Int) -> Date? {
        return LunarEngine.getSolarDate(day: lunarDay, month: lunarMonth, year: year)
    }
    
    // MARK: - Gửi Request Thêm Mới (POST)
    func submitAddItem() async {
        let isTask = isTaskMode
        let newTitle = modalTitle.isEmpty ? "(Không có tiêu đề)" : modalTitle
        let newDesc = modalDesc
        let maxTimes = (isRepeat) ? max(1, min(Int(repeatTimes) ?? 1, 100)) : 1
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let baseDate = formatter.date(from: selectedDateStr) else { return }
        
        let calendar = Calendar.current
        let baseYear = calendar.component(.year, from: baseDate)
        
        let lunarBase = LunarEngine.getLunarDate(
            dd: calendar.component(.day, from: baseDate),
            mm: calendar.component(.month, from: baseDate),
            yyyy: baseYear
        )
        
        await MainActor.run { self.showAddModal = false }
        
        for i in 0..<maxTimes {
            guard let token = await auth.refreshAccessTokenIfNeeded() else {
                FileLogger.shared.logError(context: "submitAddItem", message: "Không thể refresh access token tại lần lặp thứ \(i)")
                await MainActor.run { handleAuthFailure() }
                break
            }
            
            var targetDateStr: String = selectedDateStr
            
            if i == 0 {
                targetDateStr = selectedDateStr
            } else if isRepeat && selectedTab == .lunar {
                let targetLunarYear = baseYear + (i * repeatInterval)
                
                if let solarDate = LunarEngine.getSolarDate(day: lunarBase.day, month: lunarBase.month, year: targetLunarYear) {
                    targetDateStr = formatter.string(from: solarDate)
                } else {
                    let errMsg = "Không thể map ngày Âm \(lunarBase.day)/\(lunarBase.month)/\(targetLunarYear)"
                    FileLogger.shared.logError(context: "submitAddItem", message: errMsg)
                    continue
                }
            } else if isRepeat && selectedTab == .solar {
                targetDateStr = calculateNextDate(dateString: selectedDateStr, interval: i * repeatInterval, unit: repeatUnit)
            } else {
                targetDateStr = selectedDateStr
            }
            
            let urlString = isTask
                ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks"
                : "https://www.googleapis.com/calendar/v3/calendars/primary/events"
            
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = isTask ? [
                "title": newTitle,
                "notes": newDesc,
                "due": "\(targetDateStr)T00:00:00.000Z"
            ] : [
                "summary": newTitle,
                "description": newDesc,
                "start": ["date": targetDateStr],
                "end": ["date": targetDateStr]
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                var statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
                
                if statusCode == 401 {
                    FileLogger.shared.logError(context: "submitAddItem", message: "HTTP 401 Unauthorized, thử force refresh token...")
                    if let newToken = await auth.refreshAccessTokenIfNeeded(forceRefresh: true) {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        statusCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? 500
                    } else {
                        FileLogger.shared.logError(context: "submitAddItem", message: "Không thể force refresh token")
                        await MainActor.run { handleAuthFailure() }
                        break
                    }
                }
                
                if (200...299).contains(statusCode) {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let newItemId = json["id"] as? String {
                        let newItem = CalendarItem(id: newItemId, title: newTitle, description: newDesc.isEmpty ? nil : newDesc, type: isTask ? .task : .event, isCompleted: false, dateString: targetDateStr)
                        await MainActor.run {
                            if let dayIndex = self.days.firstIndex(where: { $0.dateString == targetDateStr }) {
                                self.days[dayIndex].items.append(newItem)
                            }
                        }
                    }
                } else {
                    FileLogger.shared.logError(context: "submitAddItem", message: "HTTP Status \(statusCode)")
                    if statusCode == 401 {
                        await MainActor.run { handleAuthFailure() }
                        break
                    }
                }
            } catch {
                print("Lỗi tạo task: \(error)")
                FileLogger.shared.logError(context: "submitAddItem", message: "Lỗi tạo task: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Gửi Request Cập Nhật (PATCH)
    func submitEditItem() async {
        guard let id = editingItemId, let dateStr = editingItemDateStr else { return }
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            FileLogger.shared.logError(context: "submitEditItem", message: "Không thể refresh access token")
            await MainActor.run { handleAuthFailure() }
            return
        }
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
            if let httpResponse = response as? HTTPURLResponse {
                if !(200...299).contains(httpResponse.statusCode) {
                    FileLogger.shared.logError(context: "submitEditItem", message: "HTTP Status \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 401 {
                        await MainActor.run { handleAuthFailure() }
                    } else {
                        await fetchDataFromGoogle()
                    }
                }
            }
        } catch {
            FileLogger.shared.logError(context: "submitEditItem", message: error.localizedDescription)
            await fetchDataFromGoogle()
        }
    }
    
    // MARK: - Expense Helpers
    func totalExpense(for dateStr: String) -> Int {
        (allExpenses[dateStr] ?? []).reduce(0) { $0 + $1.amount }
    }
    
    func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "en_US")
        return (formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") + " ₫"
    }
    
    func formatShortAmount(_ amount: Int) -> String {
        if amount >= 1_000_000 {
            let m = Double(amount) / 1_000_000
            if m == floor(m) {
                return String(format: "%.0fM", m)
            }
            return String(format: "%.1fM", m).replacingOccurrences(of: ".0", with: "")
        } else if amount >= 1_000 {
            let k = amount / 1_000
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return (formatter.string(from: NSNumber(value: k)) ?? "\(k)") + "k"
        }
        return "\(amount)"
    }
    
    // MARK: - Expense Actions
    func openExpenseModal(dateStr: String) {
        expenseDateStr = dateStr
        showExpenseModal = true
    }
    
    func closeExpenseModal() {
        showExpenseModal = false
        expenseDateStr = ""
    }
    
    func addExpense(amount: Int, note: String) {
        guard amount > 0, !expenseDateStr.isEmpty else { return }
        
        let item = ExpenseItem(
            id: UUID().uuidString,
            amount: amount,
            note: note.isEmpty ? nil : note,
            dateString: expenseDateStr
        )
        
        var list = allExpenses[expenseDateStr] ?? []
        list.append(item)
        allExpenses[expenseDateStr] = list
        saveExpensesLocally()
        Task { await uploadExpensesToDrive() }
    }
    
    func updateExpense(_ item: ExpenseItem, newAmount: Int, newNote: String) {
        guard newAmount > 0 else { return }
        guard var list = allExpenses[item.dateString] else { return }
        
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            list[idx].amount = newAmount
            list[idx].note = newNote.isEmpty ? nil : newNote
            allExpenses[item.dateString] = list
            saveExpensesLocally()
            Task { await uploadExpensesToDrive() }
        }
    }
    
    func removeExpense(_ item: ExpenseItem) {
        guard var list = allExpenses[item.dateString] else { return }
        list.removeAll { $0.id == item.id }
        if list.isEmpty {
            allExpenses.removeValue(forKey: item.dateString)
        } else {
            allExpenses[item.dateString] = list
        }
        saveExpensesLocally()
        Task { await uploadExpensesToDrive() }
    }
    
    // MARK: - Local file (cache)
    private var expenseFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MenuBarDateApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(expenseFileName)
    }
    
    private func loadExpensesLocally() {
        let url = expenseFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [ExpenseItem]].self, from: data) else {
            allExpenses = [:]
            return
        }
        allExpenses = decoded
    }
    
    private func saveExpensesLocally() {
        let url = expenseFileURL
        if let data = try? JSONEncoder().encode(allExpenses) {
            try? data.write(to: url, options: .atomic)
        }
    }
    
    // MARK: - Google Drive appDataFolder Sync
    func syncExpensesFromDrive() async {
        guard isLoggedIn else {
            loadExpensesLocally()
            return
        }
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            loadExpensesLocally()
            return
        }
        
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            .init(name: "spaces", value: "appDataFolder"),
            .init(name: "q", value: "name = 'expenses.json'"),
            .init(name: "fields", value: "files(id, name, modifiedTime)")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                loadExpensesLocally()
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let files = json["files"] as? [[String: Any]],
               let first = files.first,
               let fileId = first["id"] as? String {
                
                driveExpenseFileId = fileId
                
                let downloadURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
                var dlRequest = URLRequest(url: downloadURL)
                dlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (fileData, _) = try await URLSession.shared.data(for: dlRequest)
                if let decoded = try? JSONDecoder().decode([String: [ExpenseItem]].self, from: fileData) {
                    await MainActor.run {
                        self.allExpenses = decoded
                        self.saveExpensesLocally()
                    }
                    return
                }
            }
            
            loadExpensesLocally()
            
        } catch {
            FileLogger.shared.logError(context: "syncExpensesFromDrive", message: error.localizedDescription)
            loadExpensesLocally()
        }
    }
    
    private func uploadExpensesToDrive() async {
        guard isLoggedIn else { return }
        guard let token = await auth.refreshAccessTokenIfNeeded() else { return }
        guard let jsonData = try? JSONEncoder().encode(allExpenses) else { return }
        
        if let fileId = driveExpenseFileId {
            // Update file đã tồn tại
            let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=media")!
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    FileLogger.shared.logError(context: "uploadExpensesToDrive", message: "Update failed HTTP \(http.statusCode)")
                    if http.statusCode == 404 {
                        driveExpenseFileId = nil
                        await uploadExpensesToDrive()
                    }
                }
            } catch {
                FileLogger.shared.logError(context: "uploadExpensesToDrive", message: error.localizedDescription)
            }
        } else {
            // Tạo file mới trong appDataFolder (multipart)
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = Data()
            
            let metadata = """
            {
              "name": "expenses.json",
              "parents": ["appDataFolder"]
            }
            """
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            body.append(metadata.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(jsonData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newId = json["id"] as? String {
                    driveExpenseFileId = newId
                } else {
                    FileLogger.shared.logError(context: "uploadExpensesToDrive", message: "Create failed")
                }
            } catch {
                FileLogger.shared.logError(context: "uploadExpensesToDrive", message: error.localizedDescription)
            }
        }
    }
}
