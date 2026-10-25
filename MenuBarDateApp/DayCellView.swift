import SwiftUI

struct DayCellView: View {
    let day: DayModel
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    @State private var isHoveringDollar = false
    
    private var dayTotal: Int {
        viewModel.totalExpense(for: day.dateString)
    }
    
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
            Spacer()
        }
        .frame(height: 75)
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

// ItemView giữ nguyên như trước
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
