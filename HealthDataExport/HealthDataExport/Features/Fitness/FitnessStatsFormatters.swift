import SwiftUI

// MARK: - Shared stats formatting helpers
//
// 训练统计相关视图共用的配色与数值格式化工具。这些函数被
// StrengthVolumeAnalysisCard 与 FitnessSessionStatsDetailSheet 等多个文件引用，
// 因此保持 internal 访问级别。

func regionColor(_ code: String) -> Color {
    switch code {
    case "chest": return Color(hex: "F15B4A")
    case "arms": return Color(hex: "F6B94D")
    case "back": return Color(hex: "5B8DEF")
    case "core": return Color(hex: "7CC93F")
    case "shoulders": return Color(hex: "A885F7")
    case "legs": return Color(hex: "17BCCB")
    default: return Color(hex: "8A8F9C")
    }
}

func formatVolume(_ kg: Double) -> String {
    if kg >= 1000 {
        return String(format: "%.2fK kg", kg / 1000)
    }
    if kg.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(kg)) kg"
    }
    return String(format: "%.1f kg", kg)
}

func formatChartVolume(_ kg: Double) -> String {
    if kg >= 1000 {
        return String(format: "%.2fK kg", kg / 1000)
    }
    if kg.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(kg)) 千克"
    }
    return String(format: "%.1f 千克", kg)
}

func formatCalories(_ kcal: Double?) -> String {
    guard let kcal else { return "--" }
    if kcal.truncatingRemainder(dividingBy: 1) == 0 {
        return "\(Int(kcal)) kcal"
    }
    return String(format: "%.1f kcal", kcal)
}

func formatDuration(_ seconds: Int?) -> String {
    guard let seconds else { return "--" }
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}

func formatSessionDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}
