import SwiftUI

struct CalendarPopupView: View {
    @ObservedObject var viewModel: CalendarPopupViewModel
    
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
                    // 1. Select Tháng + Năm
                    HStack(spacing: 8) {
                        // Picker Tháng (1→12)
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
                        
                        // Picker Năm (±50 năm)
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
                    }
                    .layoutPriority(1)
                    
                    // 2. Thanh Progress nằm giữa (thay thế Spacer khi đang load)
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(LinearProgressViewStyle(tint: cyanColor))
                            .padding(.horizontal, 16)
                    } else {
                        Spacer()
                    }
                    
                    // 3. Cụm nút Control
                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.login()
                        }) {
                            HStack {
                                Image(systemName: viewModel.isLoggedIn ? "person.crop.circle" : "arrow.right.square")
                            }
                            .padding(6)
                            .background(Color(hex: "#4a4d53"))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                        .disabled(viewModel.isLoading)
                        
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
        }
        .frame(width: 770, height: viewModel.popupHeight) // Co giãn chiều cao động theo viewModel
        .onAppear {
            // Sự kiện này xảy ra mỗi khi Popup được mở
            viewModel.onPopupAppear()
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
