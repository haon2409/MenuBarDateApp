import Foundation
import SwiftUI

// Đặt extension trực tiếp ở đây
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum ItemType {
    case event, task
}

struct CalendarItem: Identifiable {
    let id: String
    var title: String
    var description: String?
    var type: ItemType
    var isCompleted: Bool = false
    var dateString: String
}

struct DayModel: Identifiable {
    let id = UUID()
    let date: Date
    let dayNumber: Int
    let lunarDay: Int
    let lunarMonth: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    var items: [CalendarItem]
    var dateString: String
}

// MARK: - Expense Type
enum ExpenseType: String, Codable, CaseIterable, Identifiable {
    case utility = "Điện + Nước + Rác + Internet + 5G"
    case daily = "Ăn uống, tiêu dùng, đi lại"
    case shopping = "Mua sắm (ngoài thiết yếu)"
    case love = "Love"
    case family = "Family (Quà Tết, SN)"
    case medical = "Viện phí"
    case other = "Phát sinh (bảo trì, sửa chữa, hiếu hỷ, đám tiệc,...)"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .utility:   return Color(hex: "#FF9500") // Cam
        case .daily:     return Color(hex: "#34C759") // Xanh lá
        case .shopping:  return Color(hex: "#AF52DE") // Tím
        case .love:      return Color(hex: "#FF2D55") // Hồng
        case .family:    return Color(hex: "#007AFF") // Xanh dương
        case .medical:   return Color(hex: "#FF3B30") // Đỏ
        case .other:     return Color(hex: "#8E8E93") // Xám
        }
    }
}

// MARK: - Expense
struct ExpenseItem: Identifiable, Codable, Equatable {
    let id: String
    var amount: Int
    var note: String?
    var dateString: String
    var type: ExpenseType
    
    init(id: String, amount: Int, note: String?, dateString: String, type: ExpenseType = .other) {
        self.id = id
        self.amount = amount
        self.note = note
        self.dateString = dateString
        self.type = type
    }
}
