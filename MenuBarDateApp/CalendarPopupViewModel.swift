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
    
    // Thuộc tính cho Edit Mode
    @Published var isEditMode: Bool = false
    private var editingItemId: String? = nil
    private var editingItemDateStr: String? = nil
    
    private let calendar = Calendar.current
    private let auth = GoogleAuthManager.shared
    
    init() {
        generateCalendarGrid()
        
        // Đồng bộ trạng thái login
        isLoggedIn = auth.isLoggedIn
    }
    
    func onPopupAppear() {
        // Reset về tháng hiện tại
        currentDate = Date()
        generateCalendarGrid()
        
        // Chỉ fetch khi thực sự cần thiết (khi mở popup)
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
    func fetchDataFromGoogle(isRetry: Bool = false) async {
        print("🔄 [Debug] Bắt đầu fetchDataFromGoogle...")
        
        // Nếu là lần thử lại (isRetry = true), ép buộc gọi API refresh token mới
        guard let token = await auth.refreshAccessTokenIfNeeded(forceRefresh: isRetry) else {
            print("❌ [Debug] Lỗi: Không thể lấy hoặc refresh access token.")
            return
        }
        
        print("✅ [Debug] Đã lấy được access token thành công. Độ dài token: \(token.count)")
        
        // Clear items cũ
        for i in days.indices {
            days[i].items.removeAll()
        }
        
        let eventsSuccess = await fetchCalendarEvents(token: token)
        let tasksSuccess = await fetchTasks(token: token)
        
        // Nếu gặp lỗi 401 và chưa thử lại -> Thực hiện force refresh token 1 lần
        if (!eventsSuccess || !tasksSuccess) && !isRetry {
            print("⚠️ [Debug] Token hết hạn (Lỗi 401), đang tiến hành làm mới token...")
            await fetchDataFromGoogle(isRetry: true)
            return
        }
        
        print("✅ [Debug] Fetch xong hoàn tất. Tổng số item trên lịch:", days.flatMap { $0.items }.count)
    }
    
    private var visibleDateRange: (start: Date, end: Date)? {
        guard let first = days.first?.date,
              let last = days.last?.date else { return nil }
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
                print("📅 [Debug] Calendar API Status Code: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 401 { return false } // Trả về false nếu dính 401
                if httpResponse.statusCode != 200 { return true }
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
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
            print("❌ [Debug] Calendar fetch exception error:", error)
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
                print("✅ [Debug] Tasks API Status Code: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 401 { return false } // Trả về false nếu dính 401
                if httpResponse.statusCode != 200 { return true }
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tasks = json["items"] as? [[String: Any]] {
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
                    }
                }
            }
        } catch {
            print("❌ [Debug] Tasks fetch exception error:", error)
        }
        return true
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
    
    // MARK: - Thao tác Dữ liệu
    func deleteItem(_ item: CalendarItem) async {
        guard let token = await auth.refreshAccessTokenIfNeeded() else { return }
        
        let urlString = item.type == .event
            ? "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(item.id)"
            : "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(item.id)"
        
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
        } catch {
            print("❌ Lỗi khi xóa: \(error)")
        }
    }

    func toggleTaskStatus(_ item: CalendarItem) async {
        guard item.type == .task else { return }
        
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }),
               let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == item.id }) {
                days[dayIndex].items[itemIndex].isCompleted.toggle()
            }
        }
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            await rollbackStatus(item)
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
                    if let newToken = await auth.refreshAccessTokenIfNeeded(forceRefresh: true) {
                        request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        let (_, retryResponse) = try await URLSession.shared.data(for: request)
                        if let retryHttp = retryResponse as? HTTPURLResponse, !(200...299).contains(retryHttp.statusCode) {
                            await rollbackStatus(item)
                        }
                    } else {
                        await rollbackStatus(item)
                    }
                } else if !(200...299).contains(httpResponse.statusCode) {
                    await rollbackStatus(item)
                }
            }
        } catch {
            print("❌ [Debug] Lỗi đổi trạng thái task:", error)
            await rollbackStatus(item)
        }
    }

    private func rollbackStatus(_ item: CalendarItem) async {
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == item.dateString }),
               let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == item.id }) {
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
        
        self.showAddModal = true
    }
    
    // MARK: - Gửi Request Cập Nhật (PATCH)
    // MARK: - Gửi Request Cập Nhật (PATCH)
    func submitEditItem() async {
        print("🔄 [DEBUG EDIT] Bắt đầu gọi hàm submitEditItem()")
        
        guard let id = editingItemId,
              let dateStr = editingItemDateStr else {
            print("❌ [DEBUG EDIT] Thất bại: editingItemId hoặc editingItemDateStr đang bị nil")
            return
        }
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            print("❌ [DEBUG EDIT] Thất bại: Không lấy được Access Token")
            return
        }
        
        let isTask = isTaskMode
        let newTitle = modalTitle
        let newDesc = modalDesc
        
        print("📝 [DEBUG EDIT] Dữ liệu chuẩn bị gửi - isTask: \(isTask), id: \(id), title: \(newTitle)")
        
        // 1. Optimistic UI: Hiển thị thay đổi ngay lập tức
        await MainActor.run {
            if let dayIndex = days.firstIndex(where: { $0.dateString == dateStr }),
               let itemIndex = days[dayIndex].items.firstIndex(where: { $0.id == id }) {
                days[dayIndex].items[itemIndex].title = newTitle
                days[dayIndex].items[itemIndex].description = newDesc
                self.showAddModal = false
                print("✅ [DEBUG EDIT] Đã cập nhật Optimistic UI cục bộ")
            } else {
                print("⚠️ [DEBUG EDIT] Không tìm thấy item trong ViewModel array để cập nhật UI cục bộ")
            }
        }
        
        // 2. Gọi API PATCH
        let urlString = isTask
            ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(id)"
            : "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)"
        
        guard let url = URL(string: urlString) else {
            print("❌ [DEBUG EDIT] Lỗi parse URL: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = isTask
            ? ["title": newTitle, "notes": newDesc]
            : ["summary": newTitle, "description": newDesc]
        
        print("🌐 [DEBUG EDIT] URL: \(urlString)")
        print("📦 [DEBUG EDIT] Body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [DEBUG EDIT] HTTP Status Code: \(httpResponse.statusCode)")
                
                if !(200...299).contains(httpResponse.statusCode) {
                    // In ra chi tiết lỗi Google trả về
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ [DEBUG EDIT] Lỗi từ API Google: \n\(errorString)")
                    }
                    await fetchDataFromGoogle() // Rollback dữ liệu nếu lỗi
                } else {
                    print("✅ [DEBUG EDIT] Lưu (PATCH) thành công trên server Google!")
                }
            }
        } catch {
            print("❌ [DEBUG EDIT] Lỗi kết nối / Network error:", error.localizedDescription)
            await fetchDataFromGoogle() // Rollback dữ liệu nếu lỗi
        }
    }
    
    // MARK: - Gửi Request Thêm Mới (POST)
    func submitAddItem() async {
        print("🔄 [DEBUG ADD] Bắt đầu gọi hàm submitAddItem()")
        
        guard let token = await auth.refreshAccessTokenIfNeeded() else {
            print("❌ [DEBUG ADD] Thất bại: Không lấy được Access Token")
            return
        }
        
        let isTask = isTaskMode
        let newTitle = modalTitle.isEmpty ? "(Không có tiêu đề)" : modalTitle
        let newDesc = modalDesc
        let targetDate = selectedDateStr // format "yyyy-MM-dd"
        
        // 1. Đóng modal ngay lập tức để UX mượt (Optimistic UI part 1)
        await MainActor.run {
            self.showAddModal = false
        }
        
        // 2. Cấu hình URL cho API POST
        let urlString = isTask
            ? "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks"
            : "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 3. Chuẩn bị Body JSON dựa trên loại
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
        
        print("📦 [DEBUG ADD] Body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 [DEBUG ADD] HTTP Status Code: \(httpResponse.statusCode)")
                
                if (200...299).contains(httpResponse.statusCode) {
                    // 4. Lấy ID từ server và cập nhật UI nội bộ
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let newItemId = json["id"] as? String {
                        
                        let newItem = CalendarItem(
                            id: newItemId,
                            title: newTitle,
                            description: newDesc.isEmpty ? nil : newDesc,
                            type: isTask ? .task : .event,
                            isCompleted: false,
                            dateString: targetDate
                        )
                        
                        await MainActor.run {
                            if let dayIndex = days.firstIndex(where: { $0.dateString == targetDate }) {
                                days[dayIndex].items.append(newItem)
                                print("✅ [DEBUG ADD] Thêm thành công vào UI: \(newItem.title)")
                            }
                        }
                    }
                } else {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ [DEBUG ADD] Lỗi từ API Google: \n\(errorString)")
                    }
                    await fetchDataFromGoogle() // Tải lại đồng bộ nếu có lỗi
                }
            }
        } catch {
            print("❌ [DEBUG ADD] Lỗi kết nối:", error.localizedDescription)
            await fetchDataFromGoogle() // Tải lại đồng bộ nếu có lỗi
        }
    }
}
