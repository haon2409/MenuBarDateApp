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
        // MARK: - Context Menu 3: Vùng trống trong ô ngày
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
        }
    }
}

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
        // MARK: - Context Menu 1 & 2: Click trực tiếp vào Task hoặc Event
        .contextMenu {
            if item.type == .task {
                // Context Menu 1: Click chuột phải vào Task
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
                // Context Menu 2: Click chuột phải vào Event
                Button {
                    viewModel.openEditModal(for: item)
                } label: {
                    Text("Edit")
                }
            }
        }
    }
}
