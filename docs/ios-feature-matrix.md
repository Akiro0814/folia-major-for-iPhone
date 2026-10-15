# iOS 功能对照与验证边界

本表对照原项目 README、`src/components/visualizer/registry.tsx` 与 iOS 代码。代码存在、编译成功、模拟器通过、真机可用是不同状态；没有实际执行记录时，不把“已实现”当作“已验证”。本地 Windows 环境不能运行 Xcode；最终构建证据以对应 GitHub Actions 运行及其附件为准。

已交付首版 `0.1.0 (8)`：[成功的 Actions 运行](https://github.com/Akiro0814/folia-major-for-iPhone/actions/runs/39086278493)，源码 `8b8e403`。50 项常规原生单测、2 项 UI 测试及独立的网易云／酷狗匿名原生搜索探针通过，横竖屏整屏截图已核对，IPA 已下载并校验。文件与 SHA-256 见[实施与验证记录](ios-implementation-status.md)。真实账号与签名设备仍未验证。

| 原项目能力 / iOS 目标 | iOS 实现入口 | 当前范围与限制 |
| --- | --- | --- |
| 原生 iOS 26 界面、液态玻璃 | `ios/Folia/App/RootView.swift`、`Features/PlayerView.swift` | SwiftUI 系统 Tab、导航、底部附件与 glassEffect；不是 Electron 套壳。模拟器导航和截图已验证，真机外观待确认。 |
| 横竖屏切换、iPad | `Info.plist`、`Features/PlayerView.swift` | 系统方向声明，按可用宽高切换播放器布局；iPad 声明四方向。旋转、分屏与大字号需设备验证。 |
| 网易云搜索、播放、歌词 | `Services/NeteaseTransport.swift`、`OmniService.swift` | 设备端加密协议与 URLSession；不包含 Node API 服务。可播放资源受账号、会员、地区和平台风控限制。 |
| 网易云短信、密码、扫码登录 | `Services/OmniAuthentication.swift`、`Features/AccountsView.swift` | 原生流程、Keychain 会话及取消轮询；仍需真实账号验证，不能把协议测试当登录成功。 |
| 酷狗登录、播放与歌单 | `Services/PublicDiscoveryTransport.swift`、`KuGouAuthentication.swift`、`KuGouLibrary.swift` | 已写设备端搜索、播放、逐字歌词、短信 / 密码 / 扫码、歌单、收藏、编辑与推荐协议；上游等价匿名签名搜索及 KRC 解析已成功，所测版权歌曲匿名无完整播放地址。真实账号登录与写入仍未验证。 |
| QQ 音乐登录、播放与歌单 | `Services/QQProvider.swift`、`QQAppQR.swift`、`QQCatalog.swift`、`QQMutations.swift` | 已写设备绑定、微信二维码授权、QQ App MQTT 扫码事件、凭证交换校验、授权搜索 / 播放、QRC 逐字歌词、歌单、收藏、编辑与推荐。匿名搜索可能被平台拒绝；没有真实用户授权成功与播放证明，不能将代码存在写为已登录可用。 |
| 波点音乐 | `Services/BodianProvider.swift`、`BodianCodec.swift`、`BodianGETBodyHTTP.swift` | 按实际 bodian-music-api 0.1.2 移植搜索、权益检查、音频、逐字歌词、扫码、账户歌单、收藏与编辑。原生 HTTPS/1.1 保留签名 GET JSON body；拒绝把试听当完整歌曲。专辑 / 歌手发现来自匹配歌曲的真实引用，再读对应目录接口。上游匿名搜索、歌词、试听权益已实测，原生运行和真实登录未验证。 |
| 一键微信授权后返回 App | `Features/AccountsView.swift` | 没有开发者账号与平台应用注册，不能承诺第三方官方 SDK OAuth。扫码票据、授权链接与“唤起微信并自动返回”不是同一种能力。 |
| Navidrome / Subsonic | `Services/NavidromeProvider.swift` | 自有服务器直连，ping 验证、盐化 MD5、账户配置存 Keychain；搜索、专辑、歌手、歌单、播放、封面、结构化歌词、收藏和歌单编辑。HTTP 服务器还受 ATS 系统策略限制，优先 HTTPS。歌曲 / 歌单附服务器命名空间；切换服务器后拒绝旧引用，避免串库。真实服务器尚需联调。 |
| 在线歌单、每日推荐、喜欢歌曲 | `Services/OmniService.swift`、`Features/TrackList.swift` | 提供服务接口及曲库入口；不同 provider 不强行共用未实现能力。Navidrome 的随机歌曲与平台每日个性推荐语义不同。 |
| 播放队列、随机 / 循环、睡眠定时 | `Playback/PlaybackQueue.swift`、`PlaybackCoordinator.swift` | 原生队列与持久化歌曲引用，不保存音频文件。队列逻辑由 XCTest 覆盖。 |
| 后台播放、锁屏、耳机、AirPlay | `Playback/PlaybackSystem.swift`、`Features/PlayerView.swift` | AVPlayer、MPRemoteCommandCenter、中断 / 拔耳机处理；系统后台音频模式。后台、蓝牙、AirPlay、电话中断仍需已签名真机测试。 |
| 多种全屏歌词动画和背景 | `ios-web/main.tsx`、`src/components/visualizer/VisualizerRenderer.tsx` | WKWebView 复用原项目 renderer、模式 registry 与歌词解析器，音频和导航由原生负责；基于生成清单新增高级参数编辑，仍不等于完整桌面设置与模组系统。 |
| LRC / YRC / QRC / KRC / TTML / AWLRC 时序 | `ios-web/main.tsx`、`src/utils/lyrics/parserCore.ts` | 复用实际解析器；通过原生消息传递歌词与播放时钟，支持歌词点击跳转、翻译、音译、偏移。已写入实际解码 PCM 的 MTAudioProcessingTap / FFT 分析与原生到歌词画面的频段桥接；HLS、受保护或不兼容流明确不提供分析。尚需原生运行和真机音频证据，不能把实现存在当作所有流均支持音频响应背景。 |
| 外观设置导入导出 | `Features/AppSettings.swift`、`Features/SettingsView.swift` | JSON 包含当前原生设置的动画、背景、字号、翻译、音译、偏移、四颜色主题和高级调参；另有版本化应用备份，保存设备收藏、队列、主题库和偏好，排除账户凭证与音频。原生备份不等于 Windows 全部配置格式兼容。 |
| 深浅色、减少动态效果、无障碍 | `Features/PlayerView.swift`、`WebLyrics/FoliaLyricsView.swift` | 系统颜色与原生控件可访问标签；歌词 Web 内容的 VoiceOver 完整性、超大字号和减少动态效果需专项检查。 |
| AI 主题生成、完整主题编辑器 | `Services/AIThemeService.swift`、`Features/AIThemeView.swift` | 已接用户配置的 HTTPS chat/completions 服务、模型与独立 Keychain API key；仅用户主动操作时发送上下文，解析四个 hex 颜色并写入可导出的原生视觉配置。新增本机命名四颜色主题库与系统颜色编辑；真实 API 调用待验证。原项目 DualTheme 全参数库与同步不是此四颜色库。 |
| 自托管设置 / 主题同步 | `Services/FoliaSyncService.swift`、`Features/FoliaSyncView.swift` | 原服务器 schema 1 与 Bearer API 的手动设置上传 / 下载，保留桌面专属字段并回读确认；支持原生设置子集和高级调参，迁移 legacy tuning 时保留未编辑模式及桌面专属字段。主题库、自动同步和歌词偏移未接入。真实服务器待验证。 |
| 命令面板、完整快捷键系统 | `Features/CommandsView.swift` | 原生 searchable List 覆盖播放、队列、睡眠、平台、音质、歌词模式、字幕与设置入口；完整桌面命令注册、硬件快捷键与模组命令未移植。 |
| 模组市场、Node / ffmpeg 插件 | 原项目 Folium | 桌面 Node 模组不能在 iOS 沙箱直接运行，未实现 iOS 模组执行器。 |
| 桌面外部 Now Playing 服务、OBS、透明视频导出 | 原项目 Electron / OBS 模块 | 未移植；iOS 系统锁屏控制与“读取其他应用播放时间驱动歌词”不同。 |
| 全局均衡器、ReplayGain 与桌面音频处理 | 原项目音频管线 | 当前原生 AVPlayer 路径未实现原项目全部 DSP；不能以系统音量或音质选择代替。 |
| 本地音乐、文件夹扫描、标签写入、本地歌词文件 | 无 | 按需求移除。不会扫描导入本地音频，也不提供本地音频播放入口。 |
| GitHub Actions 未签名 IPA | `.github/workflows/ios-build.yml`、`ios/Scripts/build-unsigned.sh` | build 8 已通过 iOS 26 模拟器 XCTest / UI 测试及 iPhoneOS arm64 构建；打包后校验 Mach-O、MinimumOSVersion、歌词资源和 SHA-256，已下载并通过本机复核。 |
| 签名安装、App Store | 用户自行签名 | IPA 无开发团队签名或 embedded provisioning profile；本仓库不负责 App Store 上架。安装、后台权限和账号业务最终以用户签名后的设备验证为准。 |

## 当前明确未完成的全量迁移项

已有原生四颜色主题编辑与本机主题库；尚未覆盖原项目 DualTheme 全参数编辑与远端主题库同步、自动同步、完整桌面命令与快捷键、桌面模组、OBS / 外部播放器跟随、视频导出和桌面 DSP。因此当前交付不能称为“除本地音乐外全部功能已经移植”。原生系统适配和可构建 IPA 也不能替代这些产品能力。

## 最小验收顺序

1. GitHub Actions 记录 Xcode 与 iOS SDK 版本，模拟器测试通过。
2. 下载 IPA 与 SHA-256；验证是真实 iPhoneOS arm64 应用且歌词静态资源完整。
3. 用户签名安装后，分别测试在线搜索、真实账号登录、会员歌曲和退出重登；不要使用生产凭证进入 CI 日志。
4. 真机验证旋转、后台 / 锁屏、耳机拔出、中断恢复、AirPlay、歌词同步和 WebKit 恢复。
5. 对本表中明确缺失的功能继续实施，或在发行说明中持续保留缺失项。

## 匿名协议实测记录（2026-10-17）

本地 Node 使用仓库已安装的原协议包直连，不等于 iOS 运行证明：网易云加密搜索返回 code 200；酷狗签名搜索 status 1，KRC 4192 bytes 解码 8405 字符；波点搜索返回两首歌，id 228908 的歌词正文 1463 字符、逐字歌词 7127 字符，音频接口仅给试听。波点带 JSON body 的 GET 权益请求实际返回 HTTP 200 / code 200 / status 3，未压缩且采用 chunked 响应。没有发送真实账号凭证、短信或歌单修改请求。
