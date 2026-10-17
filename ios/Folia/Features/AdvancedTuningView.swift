import SwiftUI

// Folia/Features/AdvancedTuningView.swift — controls generated from the upstream tuning-default manifest.
struct AdvancedTuningView: View {
    @Environment(AppSettings.self) private var settings
    @State private var mode = "classic"
    @State private var message: String?
    private let defaults = TuningManifest.defaults
    private var fields: [String: TuningValue] {
        (defaults[mode] ?? [:]).merging(settings.visual.visualizerTunings?[mode] ?? [:]) { _, override in override }
    }
    var body: some View {
        Form {
            if defaults.isEmpty {
                ContentUnavailableView(localized("调参清单不可用", "Tuning manifest unavailable"), systemImage: "slider.horizontal.3")
            } else {
                Picker(localized("歌词或背景模式", "Renderer or background"), selection: $mode) {
                    ForEach(defaults.keys.sorted(), id: \.self) { Text($0.capitalized).tag($0) }
                }
                Section {
                    ForEach(TuningManifest.leaves(fields), id: \.path) { field in
                        TuningFieldRow(path: field.path, value: field.value) { update(field.path, value: $0) }
                    }
                }
                Section {
                    Button(localized("恢复此模式默认参数", "Reset this mode to defaults"), role: .destructive) {
                        settings.visual.visualizerTunings?[mode] = nil
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.red) }
                    Text(localized("参数来自当前上游代码。数值输入只接受有限数值；实际效果和有效范围由对应渲染模式决定。", "Parameters come from the current upstream code. Numeric input accepts finite values only; each renderer determines its effective range and visual behavior.")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(localized("高级视觉调参", "Advanced visual tuning"))
        .onAppear { mode = defaults[settings.visual.renderer] != nil ? settings.visual.renderer : defaults.keys.sorted().first ?? "classic" }
    }
    private func update(_ path: [String], value: TuningValue) {
        var tunings = settings.visual.visualizerTunings ?? [:]
        tunings[mode] = TuningManifest.replacing(fields, path: path, with: value)
        do { try TuningManifest.validate(tunings); settings.visual.visualizerTunings = tunings; message = nil }
        catch { message = localized("参数超出可保存范围", "The parameter exceeds supported limits") }
    }
}

private struct TuningFieldRow: View {
    let path: [String]
    let value: TuningValue
    let onChange: (TuningValue) -> Void
    private var title: String { (path.last ?? "").replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
    var body: some View {
        Group {
            switch value {
            case .bool(let bool): Toggle(title, isOn: Binding(get: { bool }, set: { onChange(.bool($0)) }))
            case .number(let number): NumericTuningField(title: title, number: number) { onChange(.number($0)) }
            case .string(let string):
                TextField(title, text: Binding(get: { string }, set: { if $0.count <= 1024 { onChange(.string($0)) } }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            default: LabeledContent(title, value: localized("保持原始结构", "Original structure preserved"))
            }
        }.accessibilityHint(path.joined(separator: "."))
    }
}

private struct NumericTuningField: View {
    let title: String
    let number: Double
    let onChange: (Double) -> Void
    @State private var draft = ""
    private var valid: Bool { if let value = Double(draft) { return value.isFinite && abs(value) <= 100_000 }; return false }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                TextField(title, text: $draft).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel(title)
            }
            if !valid { Text(localized("请输入绝对值不超过 100000 的有限数值", "Enter a finite value within ±100000")).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { draft = String(number) }
        .onChange(of: number) { _, value in if Double(draft) != value { draft = String(value) } }
        .onChange(of: draft) { _, text in if let value = Double(text), value.isFinite, abs(value) <= 100_000 { onChange(value) } }
    }
}
