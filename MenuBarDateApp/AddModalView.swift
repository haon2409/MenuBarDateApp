import SwiftUI

struct AddModalView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.isTaskMode ? "Thêm Công việc (\(viewModel.selectedDateStr))" : "Thêm Sự kiện (\(viewModel.selectedDateStr))")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            
            TextField("Nhập tiêu đề...", text: $viewModel.modalTitle)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(8)
                .background(Color(hex: "#202124"))
                .foregroundColor(.white)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#4a4d53"), lineWidth: 1))
            
            TextEditor(text: $viewModel.modalDesc)
                .frame(height: 60)
                .padding(4)
                .background(Color(hex: "#202124"))
                .foregroundColor(.white)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#4a4d53"), lineWidth: 1))
            
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    viewModel.showAddModal = false
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(hex: "#4a4d53"))
                .foregroundColor(.white)
                .cornerRadius(4)
                
                Button("OK") {
                    // Logic Lưu
                    viewModel.showAddModal = false
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(hex: "#1bb5d6"))
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .frame(width: 260)
        .background(Color(hex: "#2c2f34"))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 4)
    }
}
