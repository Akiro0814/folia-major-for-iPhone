# Folia for iPhone

iOS 26+ 原生客户端：SwiftUI 负责界面、系统液态玻璃和横竖屏；AVFoundation 负责在线播放与后台音频；内置 WebKit 页面复用 Folia 歌词动画。iOS 产品不包含本地音频导入、目录扫描或本地音乐播放。

## 获取 IPA

打开本仓库 Actions 的 **iOS unsigned IPA** 工作流，选择成功的运行，在 Artifacts 下载 `Folia-iOS-unsigned-<运行号>`。解压下载的 ZIP 后得到 `Folia-iOS-unsigned.ipa` 和同名 SHA-256 文件。

这是未签名的 iPhoneOS arm64 包，不能直接点击安装。使用你已有的签名工具导入 IPA、选择自己的签名身份，签名后安装到 iOS 26+ 设备。仓库不包含证书、描述文件或平台账号密码，也不要求 App Store 上架。签名工具如需修改 bundle identifier，应在工具中完成并保持应用与 Keychain 权限一致。

Windows 验证下载文件：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath .\Folia-iOS-unsigned.ipa
```

将结果与构建附件中的 `.sha256` 比较。只有成功的工作流才会上传 IPA；失败日志或模拟器 `.app` 不是可交付的 IPA。

## 使用

1. 在“设置 → 账户与音乐服务”选择音乐平台。登录方式按实际实现能力展示，短信发送、密码提交和扫码授权由你主动触发。
2. 在线服务由设备端协议访问，不要求先部署 Node API。会员、版权、地区与风控限制仍由平台决定。账号登录实现及验证状态见[功能对照](../docs/ios-feature-matrix.md)。
3. Navidrome 使用你自己的服务器地址和账号，建议 HTTPS。服务器密码为生成 Subsonic 盐化鉴权所必需，存入系统 Keychain。
4. 在搜索页搜索歌曲后播放；长按歌曲可收藏、加入队列或执行平台支持的歌单操作。设备收藏仅保存歌曲引用。
5. 从底部播放器打开播放页，系统旋转触发横竖布局调整；锁屏、控制中心、耳机和 AirPlay 经原生播放器处理。
6. 设置中可切换内置歌词与背景模式、翻译和音译、字号、偏移，导入导出视觉配置。AI 主题需要你提供兼容服务的 HTTPS 地址、模型和密钥；生成前页面说明发送内容。
7. 现有 Folia sync-server 可用于手动同步受支持的外观设置；不会覆盖服务器里不属于本客户端的桌面设置字段。

## 构建

Windows 可编辑 Swift 和网页源码、运行纯 JS 测试及歌词打包；Xcode 编译和原生测试交由 macOS Actions。

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm run test:ios-bridge
npm run build:ios-lyrics
```

在 macOS、Xcode 26+ 和 XcodeGen 环境中：

```sh
xcodegen generate --spec ios/project.yml
bash ios/Scripts/build-unsigned.sh
```

设备构建禁用签名，脚本验证 iPhoneOS 平台、arm64 可执行文件、最低系统版本及歌词资源，再打包 `Payload/Folia.app`。Actions 还运行 XCTest 和模拟器 UI 测试并保存截图、日志与测试结果。

## 验证边界

功能矩阵持续区分源码实现、只读协议探针、模拟器测试、无签名 IPA 和签名后真机验证。真实账号登录、平台风控、蓝牙 / AirPlay、后台续播和授权跳转，最终需要你安装后验证。没有这些记录时不视为已验证。

原项目来源：[chthollyphile/folia-major](https://github.com/chthollyphile/folia-major)，沿用仓库 AGPL-3.0 许可证及原有署名。
