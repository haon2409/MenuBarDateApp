import SwiftUI

struct AddModalView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 1. Tiêu đề động
            let modeText = viewModel.isEditMode ? "Sửa" : "Thêm"
            let typeText = viewModel.isTaskMode ? "Công việc" : "Sự kiện"
            let dateText = viewModel.selectedDateStr.isEmpty ? "" : " (\(viewModel.selectedDateStr))"
            
            Text("\(modeText) \(typeText)\(viewModel.isEditMode ? "" : dateText)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            
            // 2. Thành phần dùng chung: Title & Description
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
            
            // 3. Tùy chọn Lặp lại (Áp dụng Tab Dương/Âm lịch)
            if viewModel.isTaskMode && !viewModel.isEditMode {
                Button(action: {
                    viewModel.isRepeat.toggle()
                }) {
                    HStack {
                        Image(systemName: viewModel.isRepeat ? "checkmark.square.fill" : "square")
                            .foregroundColor(viewModel.isRepeat ? Color(hex: "#1bb5d6") : .gray)
                        Text("Lặp lại công việc này")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if viewModel.isRepeat {
                    VStack(spacing: 8) {
                        // Nút chuyển đổi Tab
                        HStack(spacing: 0) {
                            Button(action: { viewModel.selectedTab = .solar }) {
                                Text(CalendarTab.solar.rawValue)
                                    .font(.system(size: 11, weight: viewModel.selectedTab == .solar ? .bold : .regular))
                                    .foregroundColor(viewModel.selectedTab == .solar ? Color(hex: "#1bb5d6") : .gray)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(viewModel.selectedTab == .solar ? Color(hex: "#4a4d53") : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: { viewModel.selectedTab = .lunar }) {
                                Text(CalendarTab.lunar.rawValue)
                                    .font(.system(size: 11, weight: viewModel.selectedTab == .lunar ? .bold : .regular))
                                    .foregroundColor(viewModel.selectedTab == .lunar ? Color(hex: "#1bb5d6") : .gray)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(viewModel.selectedTab == .lunar ? Color(hex: "#4a4d53") : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .background(Color(hex: "#202124"))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#4a4d53"), lineWidth: 1))
                        
                        // Nội dung theo Tab
                        // ... bên trong khối if viewModel.isRepeat ...

                        if viewModel.selectedTab == .solar {
                            // --- Nội dung Tab Dương Lịch (Giữ nguyên) ---
                            HStack(spacing: 4) {
                                Text("Mỗi:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                
                                Picker("", selection: $viewModel.repeatInterval) {
                                    ForEach(1...30, id: \.self) { i in Text("\(i)").tag(i) }
                                }
                                .frame(width: 45).clipped()
                                
                                Picker("", selection: $viewModel.repeatUnit) {
                                    Text("Ngày").tag("days")
                                    Text("Tuần").tag("weeks")
                                    Text("Tháng").tag("months")
                                    Text("Năm").tag("years")
                                }
                                .frame(width: 75).clipped()
                                
                                Text("- Số lần:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                
                                TextField("3", text: $viewModel.repeatTimes)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 11))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 30)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "#202124"))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        } else {
                            // --- Nội dung Tab Âm Lịch (Mới) ---
                            HStack(spacing: 4) {
                                Text("Mỗi 1 năm")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                                
                                Spacer()
                                
                                Text("- Số lần:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                
                                TextField("3", text: $viewModel.repeatTimes)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 11))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 30)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "#202124"))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            
            // 4. Buttons Submit
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
                    Task {
                        if viewModel.isEditMode {
                            await viewModel.submitEditItem()
                        } else {
                            await viewModel.submitAddItem()
                        }
                    }
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
