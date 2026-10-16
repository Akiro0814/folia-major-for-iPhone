# Folia iPhone 移植方案

日期：2026-10-16。状态：设计草案，等待架构确认；尚未实现、构建或产出 IPA。

## 目标与交付

面向 iOS 26+，交付用户自行签名安装的 arm64 unsigned IPA。开发在 Windows 完成，Apple 平台编译与模拟器验证在 GitHub Actions 的 macOS runner 完成。无需为无签名构建提供 Apple Developer 证书；安装与签名由用户处理。

保留在线音乐、账户、歌单、歌词动画、主题和 Navidrome 功能。移除 iOS 产品中的本地音频导入、目录扫描、本地音乐库和本地歌曲播放。封面、歌词、设置缓存仍可保存在设备上，不属于本地音乐播放。

## 已核实的工程事实

- 当前目录是源码副本，没有 `.git`，因此没有可验证的本地提交、远程地址和分支。
- GitHub 连接账户为 `L1angK1NG`，目标构建仓库尚未确定；不能把原作者仓库当成可写目标。
- 原应用是 Electron + React/TypeScript，尚无 `ios/` 工程。
- 账户、搜索、曲库、播放、歌词经 `src/services/onlineMusic/omni.ts` 进入 provider；Navidrome 独立。
- 内置 provider 包含网易云、酷狗、QQ、波点；波点有桌面运行时依赖，不能无声忽略。
- 现有歌词 renderer 包含 classic、cadenza、partita、fume、lumiere、cappella、tilt、diorama、still、tempera、claddagh、monet、sonnet、pendolo。实际交付清单从 registry 导出，避免手写清单漂移。
- 原桌面应用内置 Node API；Web 版本通过部署的 API 实例提供相应能力。不能把 `/login/cellphone` 这样的适配器路由直接当作音乐平台的公开原始地址。

## 用户补充：在 App 内直接登录

用户希望点击登录即可使用微信、手机验证码或账号密码，不希望把自建服务视为前提。采用设备端直连协议的优先路线，先核验协议可移植性，再实现登录 UI。外部 API 服务仅作为可选兼容配置，不默认为必需。

| 平台 | 已确认的上游能力 | 移植与验证要求 |
| --- | --- | --- |
| 网易云 | `login_cellphone` 支持验证码或密码，项目已有扫码流程 | 同时核验发送验证码、weapi 加密、cookie、验证码挑战、登录态恢复及用户歌单读取 |
| 酷狗 | 仓库文档提供验证码、用户名密码、二维码及微信相关接口 | 按仓库版本核验签名、设备身份、多账户 userid、token 版本与验证码挑战；密码登录可能需要额外验证 |
| QQ 音乐 | 当前 adapter 声明 QQ / 微信扫码通道 | 从所依赖 API 包核验实际授权、MQTT、cookie 与播放凭证协议；手机号和密码未确认，不能预先承诺 |
| 波点 | 当前为桌面 provider | 审计其原始协议和 iOS 可用性；实际不可移植时记录原因并提出范围调整，不将其标为完成 |

微信扫码、网页授权和通过微信 SDK 一键唤起后回调是不同能力。只有经过协议和设备验证的通道才能显示为可用；不能借用其他应用的身份或把任意微信授权 code 当成 QQ 音乐登录态。同机扫码必须验证长按识别、保存二维码后识别或可用授权页面；不能假定用户还有第二台设备。

发送短信、提交密码、授权和账号变更只由用户明确操作触发。开发过程不自动向用户手机号发送短信。密码仅在提交期间持有，不持久化；token / cookie 存入 Keychain，不进入仓库、Actions secrets 示例或日志。需要用户验证码或平台验证时在运行中的 App 完成。

## 技术方案比较

1. **推荐：SwiftUI 原生应用 + 原生播放 + 独立 WebKit 歌词引擎。** 首页、账户、搜索、歌单、队列、设置和播放器控件原生实现；复用 Folia 歌词与背景 renderer。保留原作动画表现，同时获得系统材质与交互。需要明确的原生/网页数据桥及 WebKit 性能验证。
2. **全部 SwiftUI / Metal 重写。** 所有内容均原生，但现有 DOM、Three.js 与 shader 动画须逐一重写，不能承诺与原作等价且无需额外工作。
3. **Capacitor / WebView 包装完整网页。** 代码复用最多，但主要 UI 仍为网页；仅用 CSS 模糊不能满足系统原生液态玻璃要求，不推荐作为本次目标架构。

## 推荐架构与边界

`SwiftUI Features → Omni 契约 → provider adapter → native transport → 上游音乐平台`。

沿用 provider 能力与错误语义，歌曲身份包含 providerId 和 mediaId，不用裸数字跨平台去重。UI 不调用原始 provider；晚到的账户、搜索与播放结果须按会话代次丢弃。Navidrome 使用独立服务边界。

`PlaybackCoordinator → AVPlayer / AVAudioSession → Now Playing / Remote Commands`。

原生侧持有队列、当前歌曲、进度、循环和后台续播。WebKit 只渲染歌词与背景，不拥有音频、不负责锁屏后换曲。原生队列在后台可独立解析下一首流地址；URL 过期时刷新，禁止依赖后台 JavaScript 定时器。

`Native playback snapshot → versioned message bridge → bundled lyric renderer`。

renderer 打包入应用，不依赖远程网页才能打开。桥接消息包含协议版本、歌曲标识、代次、时间戳、播放状态和歌词；恢复前台时全量校准。逐帧插值发生在渲染层，避免每帧跨桥或更新 SwiftUI 状态。页面离屏、锁屏和降低动态效果时停止或降低视觉渲染。

建议目录为 `ios/Folia/{App,Features,Domain,Services,Playback,WebLyrics,Resources}`，测试放 `ios/FoliaTests` 与 `ios/FoliaUITests`，构建脚本放 `ios/Scripts`；网页歌词入口独立于完整 `App.tsx`，禁止继续扩大桌面入口职责。

## 功能迁移与平台差异

- 原生首页、搜索、在线收藏、专辑/歌手/歌单详情、推荐与平台切换。
- 各 provider 按真实能力提供登录、登出、恢复登录态、喜欢、收藏和自建歌单变更；无权限、未支持和网络失败分别处理。
- 原生播放器提供播放暂停、前后曲、拖动、随机/循环、队列编辑、睡眠定时和音质选择。
- 歌词保留逐行/逐字、翻译、音译、偏移与主题参数；视觉设置进入导入导出。跨平台不兼容的字体、格式或音频处理必须明确报告。
- AI 主题生成保留为可配置功能；密钥由用户提供并保护，不打入公共 IPA；模型和账号付费不属于 IPA 构建条件。
- 设置、主题、收藏缓存和播放进度需持久化；导入旧设置时拒绝本地路径与本地歌曲队列，提供迁移报告。
- 原桌面的托盘、壁纸窗口、桌面歌词、全局快捷键、Node 模组与本机外部播放器抓取不能原样运行于 iOS。逐项记录对应的 iOS 替代能力或平台不支持原因，不能将其冒充完整保留。
- OBS / Stage / Remote、同步、Automix、音效与模组需独立审计网络及原生依赖；在完整能力清单中逐项验收，不能仅交付搜索播放器就宣称完整移植。

## iOS 原生体验

- 最低系统 iOS 26，使用系统 TabView、NavigationStack、sheet、toolbar 和适用的 glassEffect；液态玻璃用于导航与控制层。
- 竖屏优先封面、核心控制与可展开歌词；横屏按实际可用尺寸排列封面/控制和歌词。使用 size class、容器尺寸和安全区，不用旋转网页模拟横屏。
- Info.plist 声明竖屏和左右横屏；旋转保持播放、队列和歌词进度，不重建播放器。尊重系统旋转锁定。
- 原生接入后台音频、锁屏及控制中心、耳机命令、音频打断、拔出耳机、路由切换和系统分享。
- 支持 VoiceOver、动态字体、深浅色、减少动态效果和降低透明度。WebKit 渲染失败提供可读歌词及错误状态。

## 构建与交付

先确定用户可写的 GitHub 目标仓库，再导入源码并保留上游身份与许可证。当前无 `.git`，不可擅自宣称已经创建 fork 或推送。

Actions 分为环境探针、契约/业务测试、模拟器 UI 验证、iphoneos Release 构建、IPA 打包和产物校验。使用明确的 macOS runner 和经实际验证的 Xcode 26+，记录 `xcodebuild -version` 与 SDK；不可仅依赖 `macos-latest` 默认工具链。

设备构建使用 `CODE_SIGNING_ALLOWED=NO`，确认输出为 arm64 的 iPhoneOS `.app`；将真实构建结果放入 `Payload/Folia.app` 后打包 IPA，不用需要证书的签名导出流程冒充无签名交付。校验包结构、可执行文件、bundle id、最低系统、资源完整性与 SHA-256。

产物包括 `Folia-iOS-unsigned.ipa`、SHA-256、构建日志、模拟器截图和中文签名安装说明。说明自签可能需要的 bundle id 调整及功能限制；不把未签名 IPA 当成已安装运行。

## 执行顺序和验收门槛

1. 从代码建立完整能力清单；逐项分类保留、移除本地音乐或 iOS 平台替代。确定远程构建仓库。
2. 优先验证设备端登录协议与会话可用性：匿名只读探针不等于真实登录；登录成功还需验证用户信息和曲库请求。
3. 建立原生启动、系统玻璃导航、横竖屏和 Actions 首次无签名 arm64 构建。
4. 完成原生 Omni、平台登录与曲库、原生播放与后台队列，再接歌词引擎。
5. 按能力清单完成设置、主题、同步和其他适用功能；每项更新实际实现与验证状态。
6. 自动测试覆盖 provider 身份隔离、取消旧请求、登录轮询退出、错误分类、队列与循环、过期链接刷新、歌词时间桥、设置迁移和本地来源拒绝。
7. 模拟器验证页面导航、状态恢复、旋转、字号、减少动态效果与可访问性；截图必须来自构建的应用。
8. Actions 成功后下载并校验 IPA。后台续播、平台授权唤起、蓝牙/AirPlay 和签名后的设备体验由用户安装后反馈验证；模拟器通过不能替代这些证据。

## 当前待确认项

- 是否接受推荐的“原生业务界面与播放 + WebKit 歌词引擎”架构，或要求歌词和所有动画也全部原生重写。
- GitHub 构建目标仓库地址。
- 设备端协议验证失败时，是否接受可选自托管 API 兼容模式；尚无此授权，不自动部署付费服务或使用第三方公共账号代理。

## 参考

- 原项目：https://github.com/chthollyphile/folia-major
- Apple Liquid Glass：https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Apple 音频会话：https://developer.apple.com/documentation/avfaudio/avaudiosession
- Apple 远程播放事件：https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications
- GitHub macOS runner：https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
- 网易云手机号协议：https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/blob/main/module/login_cellphone.js
- 酷狗登录文档：https://github.com/MakcRe/KuGouMusicApi/blob/main/docs/README.md

上述接口文档和代码证明存在实现参考，不证明当前用户账号已登录、设备端协议已完成或 iOS 真机已验证。
