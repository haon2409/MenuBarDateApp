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
    
    init() {
        generateCalendarGrid()
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
        }
    }
    
    func goToToday() {
        currentDate = Date()
        generateCalendarGrid()
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
        
        fetchDataFromGoogle()
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
            date: date, dayNumber: dayNum, lunarDay: lunarInfo.day, lunarMonth: lunarInfo.month,
            isCurrentMonth: isCurrentMonth, isToday: isToday, items: [], dateString: dateStr
        )
        days.append(dayModel)
    }
    
    // Mock API Call (Thay thế logic fetchMonthlyData trong JS)
    func fetchDataFromGoogle() {
        guard isLoggedIn else { return }
        // TODO: Viết logic gọi URLSession tới Google Calendar/Tasks API
    }
    
    func login() {
        // TODO: Tích hợp ASWebAuthenticationSession / GoogleSignIn
        isLoggedIn.toggle()
    }
    
    // Thêm thuộc tính này vào trong CalendarPopupViewModel
    var totalRows: Int {
        let count = days.count
        return count / 7
    }

    var popupHeight: CGFloat {
        let cellHeight: CGFloat = 75 + 4
        let headerHeight: CGFloat = 90 // Tăng nhẹ từ 70 lên 90 để bù khoảng đệm mới
        let padding: CGFloat = 24
        return headerHeight + (CGFloat(totalRows) * cellHeight) + padding
    }
}
