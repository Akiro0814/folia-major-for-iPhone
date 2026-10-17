import SwiftUI

// Folia/Features/ThemeLibraryView.swift — named four-color palettes with native color editing and device persistence.
struct SavedPalette: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colors: [String]
}

struct ThemeLibraryView: View {
    @Environment(AppSettings.self) private var settings
    @State private var name = ""
    @State private var editing: UUID?
    @State private var colors: [Color] = [.black, .white, .green, .gray]
    @State private var message: String?
    private let labels = [localized("背景", "Background"), localized("主要文字", "Primary text"), localized("强调色", "Accent"), localized("次要文字", "Secondary text")]
    var body: some View {
        Form {
            Section(localized("调配主题", "Palette editor")) {
                TextField(localized("主题名称", "Palette name"), text: $name)
                ForEach(0..<4, id: \.self) { index in ColorPicker(labels[index], selection: $colors[index], supportsOpacity: false) }
                Button(localized("应用当前配色", "Apply palette")) { settings.visual.themeColors = hexColors(); message = localized("已应用", "Applied") }
                Button(localized("保存到主题库", "Save to library"), systemImage: "square.and.arrow.down") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                if editing != nil { Button(localized("新建主题", "New palette")) { editing = nil; name = "" } }
                if let message { Text(message).font(.caption) }
            }
            Section(localized("已保存主题", "Saved palettes")) {
                if settings.palettes.isEmpty { Text(localized("保存 AI 配色或手动创建的主题", "Save an AI palette or create one with the color editor")).foregroundStyle(.secondary) }
                ForEach(settings.palettes) { palette in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(palette.name).font(.headline)
                            Spacer()
                            ForEach(Array(palette.colors.enumerated()), id: \.offset) { _, hex in
                                Circle().fill(color(hex)).frame(width: 20, height: 20).accessibilityLabel(hex)
                            }
                        }
                        HStack {
                            Button(localized("应用", "Apply")) { settings.visual.themeColors = palette.colors; message = localized("已应用：", "Applied: ") + palette.name }
                            Spacer()
                            Button(localized("编辑", "Edit")) { editing = palette.id; name = palette.name; colors = palette.colors.map(color) }
                        }.buttonStyle(.borderless)
                    }.swipeActions { Button(role: .destructive) { settings.palettes.removeAll { $0.id == palette.id } } label: { Label(localized("删除", "Delete"), systemImage: "trash") } }
                }
            }
        }
        .navigationTitle(localized("主题库", "Theme library"))
        .onAppear { if let current = settings.visual.themeColors { colors = current.map(color) } }
    }
    private func save() {
        let palette = SavedPalette(id: editing ?? UUID(), name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)), colors: hexColors())
        if let index = settings.palettes.firstIndex(where: { $0.id == palette.id }) { settings.palettes[index] = palette }
        else if settings.palettes.count < 100 { settings.palettes.append(palette) }
        else { message = localized("主题库最多保存 100 项", "The library holds up to 100 palettes"); return }
        editing = palette.id; message = localized("主题已保存在此设备", "Palette saved on this device")
    }
    private func hexColors() -> [String] {
        colors.map { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
    }
    private func color(_ hex: String) -> Color {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
