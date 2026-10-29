import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - Models

struct TideEntry: Identifiable, Codable, Equatable {
    var id: String { "\(hour)-\(level)" }
    let hour: Int
    let level: Double
}

struct TideDayData: Identifiable, Codable, Equatable {
    var id: String { date }
    let date: String          // dd/MM/yyyy
    let entries: [TideEntry]
    let labels: [String]
    let data: [Double]
}

// MARK: - Service

@MainActor
final class TideService: ObservableObject {
    static let shared = TideService()
    
    private let tideURL = URL(string: "https://thegioimoicau.com/dia-danh/sai-gon/trang-1")!
    
    // Settings keys
    static let enabledKey = "tideTrackingEnabled"
    static let redThresholdKey = "tideRedThreshold"
    static let yellowThresholdKey = "tideYellowThreshold"
    static let iconColumnsKey = "tideIconColumns"
    static let dataDaysKey = "tideDataDays"
    
    // Defaults (theo yêu cầu)
    static let defaultRedThreshold: Double = 3.9
    static let defaultYellowThreshold: Double = 3.4
    static let defaultIconColumns: Int = 12
    static let defaultDataDays: Int = 14
    
    @Published private(set) var tideDays: [TideDayData] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    
    private var refreshTimer: Timer?
    private var lastFetch: Date?
    
    private init() {
        // Load cached nếu có
        loadCached()
        if isEnabled {
            startAutoRefresh()
            Task { await fetchTideData() }
        }
    }
    
    // MARK: - Settings accessors
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                startAutoRefresh()
                Task { await fetchTideData() }
            } else {
                stopAutoRefresh()
                tideDays = []
            }
            objectWillChange.send()
        }
    }
    
    var redThreshold: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Self.redThresholdKey)
            return v > 0 ? v : Self.defaultRedThreshold
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.redThresholdKey) }
    }
    
    var yellowThreshold: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Self.yellowThresholdKey)
            return v > 0 ? v : Self.defaultYellowThreshold
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.yellowThresholdKey) }
    }
    
    var iconColumns: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.iconColumnsKey)
            return v > 0 ? v : Self.defaultIconColumns
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.iconColumnsKey) }
    }
    
    var dataDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.dataDaysKey)
            return v > 0 ? min(v, 14) : Self.defaultDataDays
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), 14), forKey: Self.dataDaysKey) }
    }
    
    // MARK: - Public helpers
    
    func tideData(for dateString: String) -> TideDayData? {
        // dateString từ DayModel thường là yyyy-MM-dd hoặc dd/MM/yyyy
        let normalized = normalizeDateString(dateString)
        return tideDays.first { normalizeDateString($0.date) == normalized }
    }
    
    /// Levels cho icon: từ giờ hiện tại trở đi, đúng số cột
    func levelsForIcon() -> [Double] {
        guard isEnabled, !tideDays.isEmpty else { return [] }
        
        let flat: [(date: String, hour: Int, level: Double)] = tideDays.flatMap { day in
            day.entries.map { (day.date, $0.hour, $0.level) }
        }
        
        let today = todayString()
        let currentHour = Calendar.current.component(.hour, from: Date())
        let currentIndex = flat.firstIndex { $0.date == today && $0.hour == currentHour }
        
        var levels: [Double] = []
        let cols = iconColumns
        
        if let idx = currentIndex {
            for i in idx..<(idx + cols) {
                if i < flat.count {
                    levels.append(flat[i].level)
                } else {
                    levels.append(0)
                }
            }
        } else {
            levels = Array(repeating: 0, count: cols)
        }
        return levels
    }
    
    func color(for level: Double) -> Color {
        if level >= redThreshold {
            return Color(red: 1, green: 0, blue: 0)          // đỏ
        } else if level >= yellowThreshold {
            return Color(red: 1, green: 0.84, blue: 0)       // vàng/gold
        } else {
            return Color(red: 0.21, green: 0.635, blue: 0.922) // xanh
        }
    }
    
    // MARK: - Fetch & Parse
    
    func fetchTideData(force: Bool = false) async {
        guard isEnabled else { return }
        // Tránh spam nếu vừa fetch < 4 phút (trừ khi force)
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 240 {
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            let needed = dataDays
            // Mỗi trang ~8 ngày → tính số trang cần (tối đa 2 trang cho 14 ngày)
            let pagesNeeded = min(3, max(1, (needed + 7) / 8))
            var allParsed: [TideDayData] = []
            var seenDates = Set<String>()
            
            for page in 1...pagesNeeded {
                guard allParsed.count < needed else { break }
                
                guard let url = URL(string: "https://thegioimoicau.com/dia-danh/sai-gon/trang-\(page)") else { continue }
                var request = URLRequest(url: url)
                request.setValue("text/html", forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 20
                
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let html = String(data: data, encoding: .utf8) else {
                    throw URLError(.badServerResponse)
                }
                
                let pageParsed = parseTideTables(html: html, maxTables: needed)
                for day in pageParsed {
                    guard !seenDates.contains(day.date) else { continue }
                    seenDates.insert(day.date)
                    allParsed.append(day)
                    if allParsed.count >= needed { break }
                }
            }
            
            tideDays = Array(allParsed.prefix(needed))
            lastFetch = Date()
            cache(tideDays)
        } catch {
            lastError = error.localizedDescription
            // Giữ cache cũ nếu có
        }
        
        isLoading = false
    }
    
    private func parseTideTables(html: String, maxTables: Int) -> [TideDayData] {
        var result: [TideDayData] = []
        
        // Tìm tất cả table class="table table-striped"
        let tablePattern = #"<table class="table table-striped">[\s\S]*?</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: []) else { return [] }
        
        let nsHtml = html as NSString
        let matches = tableRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHtml.length))
        
        for (i, match) in matches.enumerated() {
            if i >= maxTables { break }
            let table = nsHtml.substring(with: match.range)
            
            var date = ""
            var tideData: [String] = []
            
            // Parse progress-bar content
            let barPattern = #"<div class="progress-bar[^>]*>([^<]+)</div>"#
            guard let barRegex = try? NSRegularExpression(pattern: barPattern, options: []) else { continue }
            let barMatches = barRegex.matches(in: table, options: [], range: NSRange(location: 0, length: (table as NSString).length))
            
            for bm in barMatches {
                let text = (table as NSString).substring(with: bm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.range(of: #"Dương lịch \d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil {
                    date = text.replacingOccurrences(of: "Dương lịch ", with: "")
                } else if text.range(of: #"^\d{1,2}h$"#, options: .regularExpression) != nil
                            || text.range(of: #"^\d+[.,]\d+m$"#, options: .regularExpression) != nil {
                    tideData.append(text.replacingOccurrences(of: ",", with: "."))
                }
            }
            
            var entries: [TideEntry] = []
            var labels: [String] = []
            var data: [Double] = []
            
            var j = 0
            while j < tideData.count - 1 {
                let hourStr = tideData[j]
                let levelStr = tideData[j + 1]
                let hour = Int(hourStr.replacingOccurrences(of: "h", with: "")) ?? -1
                let level = Double(levelStr.replacingOccurrences(of: "m", with: "")) ?? -1
                
                if hour >= 0 && level >= 0 {
                    entries.append(TideEntry(hour: hour, level: level))
                    labels.append(hourStr)
                    data.append(level)
                }
                j += 2
            }
            
            if !date.isEmpty && !entries.isEmpty {
                result.append(TideDayData(date: date, entries: entries, labels: labels, data: data))
            }
        }
        return result
    }
    
    // MARK: - Cache
    
    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuBarDateApp", isDirectory: true)
            .appendingPathComponent("tide_cache.json")
    }
    
    private func cache(_ data: [TideDayData]) {
        do {
            let dir = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: cacheURL, options: .atomic)
        } catch { }
    }
    
    private func loadCached() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([TideDayData].self, from: data) else { return }
        tideDays = decoded
    }
    
    // MARK: - Auto refresh
    
    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchTideData()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Helpers
    
    private func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: Date())
    }
    
    private func normalizeDateString(_ s: String) -> String {
        // Chấp nhận dd/MM/yyyy hoặc yyyy-MM-dd → chuẩn hóa dd/MM/yyyy
        if s.contains("-") {
            let parts = s.split(separator: "-")
            if parts.count == 3 {
                return "\(parts[2])/\(parts[1])/\(parts[0])"
            }
        }
        return s
    }
}
