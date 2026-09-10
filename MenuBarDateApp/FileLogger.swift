import Foundation

class FileLogger {
    static let shared = FileLogger()
    private let logFileURL: URL
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        // Log sẽ được lưu tại: ~/Documents/CalendarApp_Error.log
        logFileURL = paths[0].appendingPathComponent("CalendarApp_Error.log")
    }
    
    func logError(context: String, message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        let logMessage = "[\(timestamp)] [\(context)] \(message)\n"
        print(logMessage) // In ra console khi debug
        
        guard let data = logMessage.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
