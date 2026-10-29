import SwiftUI

struct DayCellView: View {
    let day: DayModel
    @ObservedObject var viewModel: CalendarPopupViewModel
    @ObservedObject private var tideService = TideService.shared
    
    @State private var isHoveringDollar = false
    
    private var dayTotal: Int {
        viewModel.totalExpense(for: day.dateString)
    }
    
    private var tideData: TideDayData? {
        guard tideService.isEnabled else { return nil }
        return tideService.tideData(for: day.dateString)
    }
    
    private let chartHeight: CGFloat = 18
    
    var body: some View {
        VStack(spacing: 2) {
            // Header Ngày
            HStack(alignment: .center, spacing: 2) {
                // Trái: $ + tổng rút gọn
                Button {
                    viewModel.openExpenseModal(dateStr: day.dateString)
                } label: {
                    HStack(spacing: 1) {
                        Text("$")
                            .font(.system(size: 10, weight: .bold))
                        if dayTotal > 0 {
                            Text(viewModel.formatShortAmount(dayTotal))
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(dayTotal > 0 ? Color(hex: "#fbbc04") : Color(hex: "#70757a"))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(isHoveringDollar ? Color.white.opacity(0.12) : Color.clear)
                    .cornerRadius(3)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 28, alignment: .leading)
                .onHover { hovering in
                    isHoveringDollar = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Spacer(minLength: 0)
                
                // Giữa: Ngày
                Text("\(day.dayNumber)")
                    .font(.system(size: 15))
                    .frame(width: 22, height: 22)
                    .background(day.isToday ? Color(hex: "#fbbc04") : Color.clear)
                    .foregroundColor(day.isToday ? Color(hex: "#282a2e") : .white)
                    .clipShape(Circle())
                    .fontWeight(day.isToday ? .bold : .regular)
                
                Spacer(minLength: 0)
                
                // Phải: Âm lịch
                Text("\(day.lunarDay)/\(day.lunarMonth)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#70757a"))
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // List Items (Tasks & Events)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(day.items) { item in
                        ItemView(item: item, viewModel: viewModel)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Biểu đồ triều cường (đáy ô)
            if let tide = tideData, !tide.data.isEmpty {
                let currentHourIndex: Int? = {
                    guard day.isToday else { return nil }
                    let h = Calendar.current.component(.hour, from: Date())
                    // labels dạng "0h", "1h", ... khớp index trong data
                    if let idx = tide.labels.firstIndex(where: { $0 == "\(h)h" }) {
                        return idx
                    }
                    // fallback theo entries
                    return tide.entries.firstIndex(where: { $0.hour == h })
                }()
                
                TideBarChartView(
                    levels: tide.data,
                    labels: tide.labels,
                    redThreshold: tideService.redThreshold,
                    yellowThreshold: tideService.yellowThreshold,
                    height: chartHeight,
                    highlightedIndex: currentHourIndex
                )
                .frame(height: chartHeight)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
        }
        .frame(height: tideService.isEnabled ? 95 : 75)
        .background(day.isCurrentMonth ? Color(hex: "#2c2f34") : Color(hex: "#222428"))
        .opacity(day.isCurrentMonth ? 1.0 : 0.45)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(hex: "#3b3e43"), lineWidth: 1)
        )
        .contextMenu {
            Button {
                viewModel.openAddModal(isTask: true, dateStr: day.dateString)
            } label: {
                Text("+ Task")
            }
            
            Button {
                viewModel.openAddModal(isTask: false, dateStr: day.dateString)
            } label: {
                Text("+ Event")
            }
            
            Button {
                viewModel.openExpenseModal(dateStr: day.dateString)
            } label: {
                Text("Chi tiêu")
            }
        }
    }
}

// MARK: - Tide Bar Chart (dùng chung cho DayCell)

struct TideBarChartView: View {
    let levels: [Double]
    var labels: [String] = []
    let redThreshold: Double
    let yellowThreshold: Double
    let height: CGFloat
    var highlightedIndex: Int? = nil   // cột giờ hiện tại → gạch chéo
    
    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let barWidth = geo.size.width / CGFloat(count)
            let maxLevel = max(redThreshold, levels.max() ?? redThreshold)
            
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(levels.enumerated()), id: \.offset) { idx, level in
                    let ratio = maxLevel > 0 ? min(1.0, level / maxLevel) : 0
                    let h = max(1, ratio * height)
                    let isHighlight = highlightedIndex == idx
                    let hourLabel = idx < labels.count ? labels[idx] : "\(idx)h"
                    let tooltip = "\(hourLabel): \(formatLevel(level))m"
                    
                    ZStack(alignment: .bottom) {
                        // Vùng hit full height để dễ hover
                        Color.clear
                            .frame(width: barWidth, height: height)
                        
                        ZStack {
                            Rectangle()
                                .fill(barColor(for: level))
                            
                            // Gạch chéo cho giờ hiện tại
                            if isHighlight {
                                DiagonalStripePattern()
                                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
                                    .clipShape(Rectangle())
                            }
                        }
                        .frame(width: barWidth, height: h)
                    }
                    .frame(width: barWidth, height: height, alignment: .bottom)
                    .contentShape(Rectangle())
                    .help(tooltip)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    private func formatLevel(_ level: Double) -> String {
        String(format: "%g", level)
    }
    
    private func barColor(for level: Double) -> Color {
        if level >= redThreshold {
            return Color(red: 1, green: 0, blue: 0)
        } else if level >= yellowThreshold {
            return Color(red: 1, green: 0.84, blue: 0)
        } else {
            return Color(red: 0.21, green: 0.635, blue: 0.922)
        }
    }
}

/// Vẽ các đường chéo lặp lại trong khung
struct DiagonalStripePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 4
        // Đường chéo từ dưới-trái → trên-phải
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}

// MARK: - ItemView

struct ItemView: View {
    let item: CalendarItem
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    var body: some View {
        HStack {
            Text(item.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            Button(action: {
                Task {
                    await viewModel.deleteItem(item)
                }
            }) {
                Text("×")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(item.type == .event ? .black : .white)
            .opacity(0.7)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(item.type == .event ? Color(hex: "#1bb5d6") : Color(hex: "#3b5998"))
        .foregroundColor(item.type == .event ? .black : .white)
        .cornerRadius(2)
        .strikethrough(item.isCompleted)
        .opacity(item.isCompleted ? 0.7 : 1.0)
        .help(item.description?.isEmpty == false ? "\(item.title)\n\(item.description!)" : item.title)
        .contextMenu {
            if item.type == .task {
                Button {
                    viewModel.openEditModal(for: item)
                } label: {
                    Text("Edit")
                }
                
                Button {
                    Task {
                        await viewModel.toggleTaskStatus(item)
                    }
                } label: {
                    Text(item.isCompleted ? "Incomplete" : "Complete")
                }
            } else {
                Button {
                    viewModel.openEditModal(for: item)
                } label: {
                    Text("Edit")
                }
            }
        }
    }
}
