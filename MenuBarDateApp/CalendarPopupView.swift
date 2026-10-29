import SwiftUI
import Combine

struct CalendarPopupView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    @ObservedObject private var tideService = TideService.shared
    
    // Hệ màu tái tạo từ popup.css
    let bgColor = Color(hex: "#282a2e")
    let cyanColor = Color(hex: "#1bb5d6")
    let orangeColor = Color(hex: "#fbbc04")
    let redColor = Color(hex: "#ff4d4d")
    let cellBgColor = Color(hex: "#2c2f34")
    let cellOtherMonthColor = Color(hex: "#222428")
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // MARK: - Header
                HStack {
                    // 1. Tháng + Tổng tháng + Năm + Tổng năm
                    HStack(spacing: 6) {
                        // Picker Tháng
                        Picker("", selection: Binding(
                            get: { viewModel.currentMonth },
                            set: { viewModel.setMonth($0) }
                        )) {
                            ForEach(1...12, id: \.self) { month in
                                Text("Tháng \(month)").tag(month)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accentColor(.white)
                        .disabled(viewModel.isLoading)
                        
                        // Tổng chi tiêu Tháng (click → summary)
                        Button {
                            viewModel.openExpenseSummary(mode: .month)
                        } label: {
                            Text(viewModel.formatShortAmount(viewModel.monthExpenseTotal))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(orangeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#3a3d42"))
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Chi tiết chi tiêu tháng")
                        
                        // Picker Năm
                        Picker("", selection: Binding(
                            get: { viewModel.currentYear },
                            set: { viewModel.setYear($0) }
                        )) {
                            ForEach(viewModel.yearRange, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accentColor(.white)
                        .disabled(viewModel.isLoading)
                        
                        // Tổng chi tiêu Năm (click → summary)
                        Button {
                            viewModel.openExpenseSummary(mode: .year)
                        } label: {
                            Text(viewModel.formatShortAmount(viewModel.yearExpenseTotal))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(orangeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#3a3d42"))
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Chi tiết chi tiêu năm")
                    }
                    .layoutPriority(1)
                    
                    // 2. Progress giữa
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle(tint: cyanColor))
                            .padding(.horizontal, 16)
                    } else {
                        Spacer()
                    }
                    
                    // 3. Cụm nút Control
                    HStack(spacing: 8) {
                        // Nút Tide Settings
                        Button {
                            viewModel.showTideSettings = true
                        } label: {
                            Image(systemName: tideService.isEnabled ? "water.waves" : "water.waves.slash")
                                .font(.system(size: 13))
                                .frame(width: 30, height: 30)
                                .background(tideService.isEnabled ? Color(hex: "#1bb5d6").opacity(0.35) : Color(hex: "#4a4d53"))
                                .foregroundColor(tideService.isEnabled ? cyanColor : .white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Cài đặt theo dõi triều cường")
                        
                        Button(action: {
                            viewModel.login()
                        }) {
                            if viewModel.isLoggedIn {
                                if let nsImage = viewModel.profileImage {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.gray)
                                }
                            } else {
                                Image(systemName: "arrow.right.square")
                                    .padding(6)
                            }
                        }
                        .help(viewModel.isLoggedIn ? "logout" : "login")
                        .buttonStyle(PlainButtonStyle())
                        
                        HStack(spacing: 4) {
                            navButton(icon: "arrow.left", action: { viewModel.changeMonth(by: -1) })
                                .disabled(viewModel.isLoading)
                            
                            navButton(icon: "circle.fill", action: viewModel.goToToday)
                                .disabled(Calendar.current.isDate(viewModel.currentDate, equalTo: Date(), toGranularity: .month) || viewModel.isLoading)
                            
                            navButton(icon: "arrow.right", action: { viewModel.changeMonth(by: 1) })
                                .disabled(viewModel.isLoading)
                        }
                    }
                }
                .padding(.top, 12)
                
                // MARK: - Weekdays
                HStack(spacing: 4) {
                    ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(day == "CN" ? redColor : (day == "T7" ? orangeColor : cyanColor))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
                
                // MARK: - Days Grid
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach($viewModel.days) { $day in
                        DayCellView(day: day, viewModel: viewModel)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            // MARK: - Modal Layer
            if viewModel.showAddModal {
                Color.black.opacity(0.6).ignoresSafeArea()
                AddModalView(viewModel: viewModel)
            }
            
            if viewModel.showExpenseModal {
                Color.black.opacity(0.6).ignoresSafeArea()
                ExpenseModalView(viewModel: viewModel)
            }
            
            if viewModel.showExpenseSummaryModal {
                Color.black.opacity(0.6).ignoresSafeArea()
                ExpenseSummaryModalView(viewModel: viewModel)
            }
            
            if viewModel.showTideSettings {
                Color.black.opacity(0.6).ignoresSafeArea()
                TideSettingsView(viewModel: viewModel)
            }
        }
        .frame(width: 770, height: viewModel.popupHeight)
        .onAppear {
            viewModel.onPopupAppear()
            if tideService.isEnabled {
                Task { await tideService.fetchTideData() }
            }
        }
    }
    
    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#4a4d53"))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
    }
}

// MARK: - Tide Settings Panel

struct TideSettingsView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    @ObservedObject private var tideService = TideService.shared
    
    @State private var enabled: Bool = false
    @State private var redThreshold: String = "3.9"
    @State private var yellowThreshold: String = "3.4"
    @State private var iconColumns: String = "12"
    @State private var dataDays: String = "14"
    @State private var errorMsg: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Theo dõi triều cường")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    viewModel.showTideSettings = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(hex: "#1f2124"))
            
            VStack(alignment: .leading, spacing: 14) {
                // Toggle bật/tắt
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { newVal in
                        enabled = newVal
                        tideService.isEnabled = newVal
                        viewModel.objectWillChange.send()
                    }
                )) {
                    Text("Bật theo dõi triều cường")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#1bb5d6")))
                
                if enabled {
                    Divider().background(Color.white.opacity(0.15))
                    
                    settingRow(title: "Ngưỡng đỏ (m)", binding: $redThreshold, hint: "mặc định 3.9")
                    settingRow(title: "Ngưỡng vàng (m)", binding: $yellowThreshold, hint: "mặc định 3.4")
                    settingRow(title: "Số cột icon", binding: $iconColumns, hint: "1–32, mặc định 12")
                    settingRow(title: "Số ngày dữ liệu", binding: $dataDays, hint: "1–14, mặc định 14")
                    
                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#ff4d4d"))
                    }
                    
                    HStack(spacing: 10) {
                        Button("Lưu") {
                            save()
                        }
                        .buttonStyle(TidePrimaryButtonStyle())
                        
                        Button("Làm mới dữ liệu") {
                            Task { await tideService.fetchTideData(force: true) }
                        }
                        .buttonStyle(TideSecondaryButtonStyle())
                        
                        Spacer()
                        
                        if tideService.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let err = tideService.lastError {
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .background(Color(hex: "#2c2f34"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear {
            enabled = tideService.isEnabled
            redThreshold = String(tideService.redThreshold)
            yellowThreshold = String(tideService.yellowThreshold)
            iconColumns = String(tideService.iconColumns)
            dataDays = String(tideService.dataDays)
        }
    }
    
    private func settingRow(title: String, binding: Binding<String>, hint: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 130, alignment: .leading)
            
            TextField(hint, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(hex: "#1f2124"))
                .cornerRadius(5)
                .foregroundColor(.white)
                .frame(width: 80)
            
            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
        }
    }
    
    private func save() {
        errorMsg = ""
        guard let r = Double(redThreshold.replacingOccurrences(of: ",", with: ".")),
              r >= 0,
              let y = Double(yellowThreshold.replacingOccurrences(of: ",", with: ".")),
              y >= 0,
              let cols = Int(iconColumns), cols >= 1, cols <= 32,
              let days = Int(dataDays), days >= 1, days <= 14 else {
            errorMsg = "Giá trị không hợp lệ (cột 1–32, ngày 1–14, ngưỡng ≥ 0)"
            return
        }
        
        tideService.redThreshold = r
        tideService.yellowThreshold = y
        tideService.iconColumns = cols
        tideService.dataDays = days
        
        Task {
            await tideService.fetchTideData(force: true)
        }
        viewModel.objectWillChange.send()
        viewModel.showTideSettings = false
    }
}

// MARK: - Button styles

struct TidePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(hex: "#1bb5d6").opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(6)
    }
}

struct TideSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            .cornerRadius(6)
    }
}
