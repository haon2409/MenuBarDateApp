import Foundation

// Model lưu trữ ngày âm[cite: 2]
struct LunarDate {
    var day: Int
    var month: Int
    var year: Int
    var leap: Int
    var jd: Int
}

class LunarEngine {
    // Dữ liệu thế kỷ 21 (2000 - 2099) và 22 (2100 - 2199)[cite: 2]
    static let TK21: [Int] = [
        0x46c960, 0x2ed954, 0x54d4a0, 0x3eda50, 0x2a7552, 0x4e56a0, 0x38a7a7, 0x5ea5d0, 0x4a92b0, 0x32aab5,
        0x58a950, 0x42b4a0, 0x2cbaa4, 0x50ad50, 0x3c55d9, 0x624ba0, 0x4ca5b0, 0x375176, 0x5c5270, 0x466930,
        0x307934, 0x546aa0, 0x3ead50, 0x2a5b52, 0x504b60, 0x38a6e6, 0x5ea4e0, 0x48d260, 0x32ea65, 0x56d520,
        0x40daa0, 0x2d56a3, 0x5256d0, 0x3c4afb, 0x6249d0, 0x4ca4d0, 0x37d0b6, 0x5ab250, 0x44b520, 0x2edd25,
        0x54b5a0, 0x3e55d0, 0x2a55b2, 0x5049b0, 0x3aa577, 0x5ea4b0, 0x48aa50, 0x33b255, 0x586d20, 0x40ad60,
        0x2d4b63, 0x525370, 0x3e49e8, 0x60c970, 0x4c54b0, 0x3768a6, 0x5ada50, 0x445aa0, 0x2fa6a4, 0x54aad0,
        0x4052e0, 0x28d2e3, 0x4ec950, 0x38d557, 0x5ed4a0, 0x46d950, 0x325d55, 0x5856a0, 0x42a6d0, 0x2c55d4,
        0x5252b0, 0x3ca9b8, 0x62a930, 0x4ab490, 0x34b6a6, 0x5aad50, 0x4655a0, 0x2eab64, 0x54a570, 0x4052b0,
        0x2ab173, 0x4e6930, 0x386b37, 0x5e6aa0, 0x48ad50, 0x332ad5, 0x582b60, 0x42a570, 0x2e52e4, 0x50d160,
        0x3ae958, 0x60d520, 0x4ada90, 0x355aa6, 0x5a56d0, 0x462ae0, 0x30a9d4, 0x54a2d0, 0x3ed150, 0x28e952
    ]
    
    // Thuật toán Julian Day Number[cite: 2]
    static func jdn(dd: Int, mm: Int, yy: Int) -> Int {
        let a = (14 - mm) / 12
        let y = yy + 4800 - a
        let m = mm + 12 * a - 3
        return dd + ((153 * m + 2) / 5) + 365 * y + (y / 4) - (y / 100) + (y / 400) - 32045
    }
    
    // Giải mã năm âm lịch[cite: 2]
    static func decodeLunarYear(yy: Int, k: Int) -> [LunarDate] {
        var ly = [LunarDate]()
        let monthLengths = [29, 30]
        var regularMonths = Array(repeating: 0, count: 12)
        let offsetOfTet = k >> 17
        let leapMonth = k & 0xf
        let leapMonthLength = monthLengths[(k >> 16) & 0x1]
        let solarNY = jdn(dd: 1, mm: 1, yy: yy)
        var currentJD = solarNY + offsetOfTet
        var j = k >> 4
        
        for i in 0..<12 {
            regularMonths[12 - i - 1] = monthLengths[j & 0x1]
            j >>= 1
        }
        
        if leapMonth == 0 {
            for mm in 1...12 {
                ly.append(LunarDate(day: 1, month: mm, year: yy, leap: 0, jd: currentJD))
                currentJD += regularMonths[mm - 1]
            }
        } else {
            for mm in 1...leapMonth {
                ly.append(LunarDate(day: 1, month: mm, year: yy, leap: 0, jd: currentJD))
                currentJD += regularMonths[mm - 1]
            }
            ly.append(LunarDate(day: 1, month: leapMonth, year: yy, leap: 1, jd: currentJD))
            currentJD += leapMonthLength
            for mm in (leapMonth + 1)...12 {
                ly.append(LunarDate(day: 1, month: mm, year: yy, leap: 0, jd: currentJD))
                currentJD += regularMonths[mm - 1]
            }
        }
        return ly
    }
    
    static func getYearInfo(yyyy: Int) -> [LunarDate] {
        let index = yyyy - 2000
        
        guard index >= 0 && index < TK21.count else {
            print("LỖI: Năm \(yyyy) nằm ngoài phạm vi dữ liệu!")
            return []
        }
        
        let yearCode = TK21[index]
        return decodeLunarYear(yy: yyyy, k: yearCode)
    }
    
    
    // Tìm ngày âm[cite: 2]
    static func findLunarDate(jd: Int, ly: [LunarDate]) -> LunarDate {
        guard !ly.isEmpty else { return LunarDate(day: 0, month: 0, year: 0, leap: 0, jd: jd) }
        var i = ly.count - 1
        while jd < ly[i].jd && i > 0 {
            i -= 1
        }
        let off = jd - ly[i].jd
        return LunarDate(day: ly[i].day + off, month: ly[i].month, year: ly[i].year, leap: ly[i].leap, jd: jd)
    }
    
    // Hàm gọi chính[cite: 2]
    static func getLunarDate(dd: Int, mm: Int, yyyy: Int) -> LunarDate {
        var ly = getYearInfo(yyyy: yyyy)
        let jd = jdn(dd: dd, mm: mm, yy: yyyy)
        if !ly.isEmpty && jd < ly[0].jd {
            ly = getYearInfo(yyyy: yyyy - 1)
        }
        return findLunarDate(jd: jd, ly: ly)
    }
    
    static func jdnToSolarDate(jd: Int) -> (day: Int, month: Int, year: Int) {
        let Z: Int = jd
        var A: Int
        if Z < 2299161 {
            A = Z
        } else {
            let zDouble = Double(Z)
            let alphaDouble = (zDouble - 1867216.25) / 36524.25
            let alpha = Int(alphaDouble)
            A = Z + 1 + alpha - (alpha / 4)
        }
        let B: Int = A + 1524
        let bDouble = Double(B)
        let cDouble = (bDouble - 122.1) / 365.25
        let C: Int = Int(cDouble)
        let dDouble = 365.25 * Double(C)
        let D: Int = Int(dDouble)
        let bdDouble = Double(B - D)
        let eDouble = bdDouble / 30.6001
        let E: Int = Int(eDouble)
        
        let product: Double = 30.6001 * Double(E)
        let intProduct: Int = Int(product)
        let dd: Int = (B - D) - intProduct
        
        let mm: Int = (E < 14) ? (E - 1) : (E - 13)
        let yyyy: Int = (mm < 3) ? (C - 4715) : (C - 4716)
        
        return (dd, mm, yyyy)
    }
    
    static func getSolarDate(day: Int, month: Int, year: Int, leap: Int = 0) -> Date? {
        let ly = getYearInfo(yyyy: year)
        
        guard let monthData = ly.first(where: { $0.month == month && $0.leap == leap }) else {
            return nil
        }
        
        let targetJD = monthData.jd + (day - 1)
        
        // Sử dụng hàm jdnToSolarDate đã viết ở bước trước để lấy day, month, year
        let solar = jdnToSolarDate(jd: targetJD)
        
        // Chuyển đổi sang Date để phù hợp với kiểu trả về mong đợi của ViewModel
        var components = DateComponents()
        components.year = solar.year
        components.month = solar.month
        components.day = solar.day
        components.timeZone = TimeZone.current
        
        return Calendar.current.date(from: components)
    }
}
