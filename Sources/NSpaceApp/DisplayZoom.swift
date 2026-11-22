import AppKit

/// ⌘ + 滚轮缩放的共用步进器（QSpace 同款交互）。
///
/// 两个细节决定手感：
/// 1. **精确增量（触控板）要累积**：`scrollingDeltaY` 在触控板上每次只有零点几到几点，
///    一次轻扫会连发几十个事件——直接按事件步进会「一碰就放到最大」。这里累积到阈值才走一步。
/// 2. **非精确增量（鼠标滚轮）一格一步**：滚轮每格的 delta 是 1 或 3，且没有 phase，
///    按累积处理会感觉迟钝。
///
/// 方向约定：向上滚（`scrollingDeltaY > 0`）= 放大，与 Finder/QSpace 一致。
enum DisplayZoom {
    /// 触控板累积到多少才走一步（pt）
    static let preciseThreshold: CGFloat = 4

    /// 喂入滚轮增量，返回本次应走的步数（正=放大，负=缩小，0=还不够一格）
    static func steps(delta: CGFloat, precise: Bool, accumulated: inout CGFloat) -> Int {
        guard precise else {
            if delta > 0 { return 1 }
            if delta < 0 { return -1 }
            return 0
        }
        accumulated += delta
        var result = 0
        while abs(accumulated) >= preciseThreshold {
            let dir: CGFloat = accumulated > 0 ? 1 : -1
            accumulated -= dir * preciseThreshold
            result += Int(dir)
        }
        return result
    }

    /// 列表/分栏视图的字号缩放：写偏好并广播（与外观设置页走同一条重建路径）。
    /// 返回是否真的变了（到边界时返回 false，避免无谓重建）。
    @MainActor
    static func stepListFont(by steps: Int) -> Bool {
        let range = Preferences.listFontRange
        let current = Preferences.listFontSize
        let target = min(range.upperBound, max(range.lowerBound, current + steps))
        guard target != current else { return false }
        Preferences.listFontSize = target
        NotificationCenter.default.post(name: .nspaceColumnsChanged, object: nil)
        return true
    }
}
