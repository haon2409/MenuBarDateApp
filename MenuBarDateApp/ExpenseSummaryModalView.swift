import SwiftUI

struct ExpenseSummaryModalView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    private var title: String {
        switch viewModel.expenseSummaryMode {
        case .month:
            return "Chi tiêu Tháng \(viewModel.currentMonth)/\(viewModel.currentYear)"
        case .year:
            return "Chi tiêu Năm \(viewModel.currentYear)"
        }
    }
    
    private var total: Int {
        switch viewModel.expenseSummaryMode {
        case .month: return viewModel.monthExpenseTotal
        case .year:  return viewModel.yearExpenseTotal
        }
    }
    
    private var breakdown: [(type: ExpenseType, total: Int)] {
        viewModel.expenseBreakdown(for: viewModel.expenseSummaryMode)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    viewModel.closeExpenseSummary()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color(hex: "#4a4d53"))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Tổng
            HStack {
                Text("Tổng:")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#a0a0a0"))
                Text(viewModel.formatAmount(total))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#fbbc04"))
            }
            .padding(.vertical, 4)
            
            Divider().background(Color(hex: "#4a4d53"))
            
            // Danh sách type
            if breakdown.isEmpty {
                Text("Chưa có chi tiêu")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#70757a"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(breakdown, id: \.type) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.type.color)
                                    .frame(width: 8, height: 8)
                                
                                Text(item.type.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(viewModel.formatAmount(item.total))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(item.type.color)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#202124"))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Color(hex: "#2c2f34"))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 4)
    }
}
