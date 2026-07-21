import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Creates a color from a 24-bit RGB hex value, e.g. `0x0B8C7A`.
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Creates a light/dark adaptive color. On platforms without UIKit the
    /// light value is used directly.
    init(lightHex: UInt, darkHex: UInt) {
        #if canImport(UIKit)
        self = Color(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
        #else
        self.init(hex: lightHex)
        #endif
    }
}

// MARK: - StandUp 品牌配色（浅色 / 深色自适应）

extension Color {
    /// 页面底色
    static let standCanvas = Color(lightHex: 0xF3F6F5, darkHex: 0x0D1210)
    /// 卡片表面
    static let standSurface = Color(lightHex: 0xFFFFFF, darkHex: 0x18211E)
    /// 次级表面（分段控件、行内标签）
    static let standSurfaceAlt = Color(lightHex: 0xEAF1EE, darkHex: 0x141C19)
    /// 主色：清爽的青绿色，健康、专注
    static let standAccent = Color(lightHex: 0x0B8C7A, darkHex: 0x33D6BE)
    /// 主色的浅底
    static let standAccentSoft = Color(lightHex: 0xD6EFEA, darkHex: 0x123A34)
    /// 警示：久坐超时的暖红
    static let standAlert = Color(lightHex: 0xD6493C, darkHex: 0xFF6F5E)
    /// 提示：接近阈值的琥珀
    static let standWarn = Color(lightHex: 0xDB8A2A, darkHex: 0xF2B14C)
    /// 主文字
    static let standInk = Color(lightHex: 0x182622, darkHex: 0xEAF2EF)
    /// 次要文字
    static let standInkSoft = Color(lightHex: 0x5D6C67, darkHex: 0x9AA9A4)
}

// MARK: - 复用样式

extension View {
    /// StandUp 卡片外观：圆角表面 + 轻微描边。
    func standCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.standSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.standInk.opacity(0.06), lineWidth: 1)
            )
    }
}
