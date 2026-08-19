import SwiftUI

struct DayCellView: View {
    let day: DayModel
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    var body: some View {
        VStack(spacing: 2) {
            // Header Ngày
            HStack(alignment: .center) {
                Spacer()
                Text("\(day.dayNumber)")
                    .font(.system(size: 15))
                    .frame(width: 22, height: 22)
                    .background(day.isToday ? Color(hex: "#fbbc04") : Color.clear)
                    .foregroundColor(day.isToday ? Color(hex: "#282a2e") : .white)
                    .clipShape(Circle())
                    .fontWeight(day.isToday ? .bold : .regular)
                Spacer()
                Text("\(day.lunarDay)/\(day.lunarMonth)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#70757a"))
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // List Items (Tasks & Events)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(day.items) { item in
                        ItemView(item: item)
                    }
                }
            }
            Spacer()
        }
        .frame(height: 75) // min-height: 68px, max-height: 75px
        .background(day.isCurrentMonth ? Color(hex: "#2c2f34") : Color(hex: "#222428"))
        .opacity(day.isCurrentMonth ? 1.0 : 0.45)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(hex: "#3b3e43"), lineWidth: 1)
        )
        // MARK: - Context Menu
        .contextMenu {
            Button {
                viewModel.selectedDateStr = day.dateString
                viewModel.isTaskMode = true
                viewModel.showAddModal = true
            } label: {
                Text("+ Task")
            }
            
            Button {
                viewModel.selectedDateStr = day.dateString
                viewModel.isTaskMode = false
                viewModel.showAddModal = true
            } label: {
                Text("+ Event")
            }
        }
    }
}

struct ItemView: View {
    let item: CalendarItem
    var body: some View {
        HStack {
            Text(item.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("×")
                .font(.system(size: 11, weight: .bold))
                .opacity(0.6)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(item.type == .event ? Color(hex: "#1bb5d6") : Color(hex: "#3b5998"))
        .foregroundColor(item.type == .event ? .black : .white)
        .cornerRadius(2)
        .strikethrough(item.isCompleted)
        .opacity(item.isCompleted ? 0.7 : 1.0)
    }
}
