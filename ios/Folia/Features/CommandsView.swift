import SwiftUI
// ios/Folia/Features/CommandsView.swift

struct CommandsView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section(localized("播放", "Playback")) {
                    action(localized("播放或暂停", "Play or pause"), icon: "playpause") { playback.toggle() }
                    action(localized("下一首", "Next track"), icon: "forward.end") { playback.next() }
                    action(localized("上一首", "Previous track"), icon: "backward.end") { playback.previous() }
                    action(localized("切换随机播放", "Toggle shuffle"), icon: "shuffle") { playback.shuffle.toggle() }
                    action(localized("切换循环模式", "Cycle repeat mode"), icon: "repeat") {
                        let modes = RepeatMode.allCases
                        let index = modes.firstIndex(of: playback.repeatMode) ?? 0
                        playback.repeatMode = modes[(index + 1) % modes.count]
                    }
                    if let track = playback.currentTrack {
                        action(localized("收藏或取消收藏当前歌曲", "Toggle current favorite"), icon: "heart") { settings.toggleFavorite(track) }
                    }
                    if matches(localized("播放队列", "Queue")) { NavigationLink { QueueView() } label: { Label(localized("播放队列", "Queue"), systemImage: "list.bullet") } }
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        action(localized("睡眠定时", "Sleep timer") + " \(minutes) min", icon: "moon") { playback.setSleep(minutes: minutes) }
                    }
                    action(localized("取消睡眠定时", "Cancel sleep timer"), icon: "moon.zzz") { playback.setSleep(minutes: nil) }
                }
                Section(localized("服务与音质", "Services & quality")) {
                    if matches(localized("应用备份", "App backup")) { NavigationLink { BackupView() } label: { Label(localized("应用备份", "App backup"), systemImage: "externaldrive") } }
                    if matches(localized("账户与音乐服务", "Accounts & services")) { NavigationLink { AccountsView() } label: { Label(localized("账户与音乐服务", "Accounts & services"), systemImage: "person.crop.circle") } }
                    ForEach(MusicProvider.allCases) { provider in
                        action(localized("切换平台：", "Provider: ") + provider.displayName, icon: "music.note") { settings.preferredProvider = provider }
                    }
                    ForEach(AudioQuality.allCases, id: \.self) { quality in
                        action(localized("音质：", "Quality: ") + quality.rawValue, icon: "waveform") { playback.quality = quality }
                    }
                }
                Section(localized("歌词与外观", "Lyrics & appearance")) {
                    if matches(localized("主题库", "Theme library")) { NavigationLink { ThemeLibraryView() } label: { Label(localized("主题库", "Theme library"), systemImage: "paintpalette") } }
                    if matches(localized("高级视觉调参", "Advanced visual tuning")) { NavigationLink { AdvancedTuningView() } label: { Label(localized("高级视觉调参", "Advanced visual tuning"), systemImage: "slider.horizontal.3") } }
                    if matches(localized("外观同步", "Appearance sync")) { NavigationLink { FoliaSyncView() } label: { Label(localized("外观同步", "Appearance sync"), systemImage: "arrow.triangle.2.circlepath") } }
                    if matches(localized("AI 主题生成", "AI theme generation")) { NavigationLink { AIThemeView() } label: { Label(localized("AI 主题生成", "AI theme generation"), systemImage: "sparkles") } }
                    ForEach(["common", "latent", "monet", "nomand", "sora"], id: \.self) { background in
                        action(localized("背景：", "Background: ") + background, icon: "photo") { settings.visual.background = background }
                    }
                    ForEach(VisualMode.bundled) { mode in
                        action(localized("歌词动画：", "Renderer: ") + mode.label, icon: "text.alignleft") { settings.visual.renderer = mode.mode }
                    }
                    action(localized("切换翻译", "Toggle translation"), icon: "character.bubble") { settings.visual.showTranslation.toggle() }
                    action(localized("切换音译", "Toggle romanization"), icon: "textformat.abc") { settings.visual.showRomanization.toggle() }
                    action(localized("恢复默认外观", "Reset appearance"), icon: "arrow.counterclockwise") { settings.visual = VisualSettings() }
                    if matches(localized("设置与视觉配置导入导出", "Settings & visual configuration import/export")) {
                        NavigationLink { SettingsView() } label: { Label(localized("设置与视觉配置导入导出", "Settings & visual configuration import/export"), systemImage: "gearshape") }
                    }
                }
            }
            .navigationTitle(localized("命令", "Commands"))
            .searchable(text: $query, prompt: localized("搜索操作、设置、歌词模式", "Search actions, settings, renderers"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localized("完成", "Done")) { dismiss() } } }
        }
    }
    private func matches(_ title: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.localizedCaseInsensitiveContains(query)
    }
    @ViewBuilder private func action(_ title: String, icon: String, operation: @escaping () -> Void) -> some View {
        if matches(title) { Button { operation() } label: { Label(title, systemImage: icon) } }
    }
}


