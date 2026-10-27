import SwiftUI

struct ExpenseModalView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    
    @State private var inputAmount: String = ""
    @State private var inputNote: String = ""
    @State private var inputType: ExpenseType = .other
    @State private var showError: Bool = false
    
    // Edit state
    @State private var editingId: String? = nil
    @State private var editAmount: String = ""
    @State private var editNote: String = ""
    @State private var editType: ExpenseType = .other
    
    private var dateTitle: String {
        let parts = viewModel.expenseDateStr.split(separator: "-")
        guard parts.count == 3 else { return viewModel.expenseDateStr }
        return "\(parts[2])/\(parts[1])"
    }
    
    private var isInputValid: Bool {
        let cleaned = inputAmount
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let amount = Int(cleaned), amount > 0 else { return false }
        return true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header + nút X
            HStack {
                Text("Chi tiêu trong ngày \(dateTitle)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    viewModel.closeExpenseModal()
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
                Text(viewModel.formatAmount(viewModel.expenseDayTotal))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#fbbc04"))
            }
            .padding(.vertical, 4)
            
            Divider().background(Color(hex: "#4a4d53"))
            
            // Danh sách chi tiêu
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(viewModel.expensesForSelectedDay) { exp in
                        if editingId == exp.id {
                            // --- Chế độ Edit ---
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    TextField("Số tiền", text: $editAmount)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .padding(6)
                                        .background(Color(hex: "#202124"))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#1bb5d6"), lineWidth: 1))
                                        .frame(width: 100)
                                        .onChange(of: editAmount) { _, newValue in
                                            editAmount = formatWhileTyping(newValue)
                                        }
                                    
                                    TextField("Ghi chú", text: $editNote)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .padding(6)
                                        .background(Color(hex: "#202124"))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#1bb5d6"), lineWidth: 1))
                                }
                                
                                HStack(spacing: 6) {
                                    Picker("", selection: $editType) {
                                        ForEach(ExpenseType.allCases) { t in
                                            Text(t.rawValue).tag(t)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Button {
                                        saveEdit(exp)
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "#1bb5d6"))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Button {
                                        editingId = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Color(hex: "#70757a"))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#25282d"))
                            .cornerRadius(4)
                        } else {
                            // --- Chế độ hiển thị ---
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(viewModel.formatAmount(exp.amount))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        Text(exp.type.rawValue)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(exp.type.color)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(exp.type.color.opacity(0.15))
                                            .cornerRadius(3)
                                            .lineLimit(1)
                                    }
                                    
                                    if let note = exp.note, !note.isEmpty {
                                        Text(note)
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(hex: "#a0a0a0"))
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    startEdit(exp)
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#1bb5d6"))
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Button {
                                    viewModel.removeExpense(exp)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "#ff4d4d"))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#202124"))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            
            // Input hàng cuối (thêm mới)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Số tiền", text: $inputAmount)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(7)
                        .background(Color(hex: "#202124"))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(showError ? Color.red : Color(hex: "#4a4d53"), lineWidth: 1))
                        .frame(width: 110)
                        .onChange(of: inputAmount) { _, newValue in
                            inputAmount = formatWhileTyping(newValue)
                            showError = false
                        }
                    
                    TextField("Ghi chú (tuỳ chọn)", text: $inputNote)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(7)
                        .background(Color(hex: "#202124"))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "#4a4d53"), lineWidth: 1))
                }
                
                HStack(spacing: 6) {
                    Picker("Loại", selection: $inputType) {
                        ForEach(ExpenseType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button {
                        addExpense()
                    } label: {
                        Text("Thêm")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isInputValid ? .white : Color(hex: "#70757a"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isInputValid ? Color(hex: "#1bb5d6") : Color(hex: "#3a3d42"))
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isInputValid)
                }
                
                if showError {
                    Text("Chỉ được nhập số nguyên hợp lệ")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(hex: "#2c2f34"))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.5), radius: 15, x: 0, y: 4)
    }
    
    // MARK: - Format số có dấu phẩy khi đang gõ
    private func formatWhileTyping(_ text: String) -> String {
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }
        
        let limited = String(digits.prefix(12))
        guard let number = Int(limited) else { return limited }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: number)) ?? limited
    }
    
    private func addExpense() {
        let cleaned = inputAmount
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let amount = Int(cleaned), amount > 0 else {
            showError = true
            return
        }
        
        showError = false
        viewModel.addExpense(
            amount: amount,
            note: inputNote.trimmingCharacters(in: .whitespacesAndNewlines),
            type: inputType
        )
        inputAmount = ""
        inputNote = ""
        inputType = .other
    }
    
    private func startEdit(_ exp: ExpenseItem) {
        editingId = exp.id
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        editAmount = formatter.string(from: NSNumber(value: exp.amount)) ?? "\(exp.amount)"
        editNote = exp.note ?? ""
        editType = exp.type
    }
    
    private func saveEdit(_ exp: ExpenseItem) {
        let cleaned = editAmount
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let amount = Int(cleaned), amount > 0 else { return }
        
        viewModel.updateExpense(
            exp,
            newAmount: amount,
            newNote: editNote.trimmingCharacters(in: .whitespacesAndNewlines),
            newType: editType
        )
        editingId = nil
    }
}
