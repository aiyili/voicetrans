# 声译通 VoiceTrans

**免费开源**的长时间录音 + 实时翻译 App（Android / iOS）。开会、上课、听讲座时打开它：边录音、边识别、边翻译，结束后可回放录音、查看和复制完整双语转写。

- 🎙 **长时间录音**：录音持续写入本地文件（AAC/m4a），时长仅受存储与电量限制；Android 由前台服务保障锁屏/切后台继续录音
- ⚡ **实时识别 + 实时翻译**：说话的同时逐句显示原文与译文（未定稿文字实时刷新）
- 🔒 **翻译完全离线**：使用 Google ML Kit 端上翻译模型（每个语言约 30MB，首次联网下载后永久离线可用），**免费、不限量、不上传任何语音或文本**
- 🌐 15 种常用语言互译：中/英/日/韩/法/德/西/俄/葡/意/泰/越/印尼/印地/阿拉伯
- 📚 **历史记录**：自动保存每次会话，支持录音回放、双语对照、一键复制、左滑删除
- 🌙 深色模式、屏幕常亮、语言模型按需管理

> 实时语音识别由系统语音服务提供（Android RecognitionService / iOS Speech 框架），免费使用；部分系统的识别服务需要网络。录音与转写数据只保存在你的手机上。

## 下载安装

到本仓库的 **[Releases](../../releases)** 页面：

| 平台 | 文件 | 说明 |
|---|---|---|
| Android | `app-release.apk` | 下载后直接安装（需允许未知来源） |
| iOS | `VoiceTrans-ios-unsigned.ipa` | 未签名包：需 AltStore / Sideloadly 自签，或 Mac + Xcode 自行签名（见下方） |

iOS 说明：Apple 不允许未付费分发签名应用，本仓库无法提供可直接安装的签名 IPA。最简单的方式是在电脑上用 [AltStore](https://altstore.io) / Sideloadly 侧载未签名 IPA；或按“自行构建”用你自己的 Apple ID 签名。

## 自行构建

```bash
git clone https://github.com/<你的用户名>/voicetrans.git
cd voicetrans
flutter pub get

# Android（需要 Android SDK）
flutter build apk --release

# iOS（需要 macOS + Xcode）
open ios/Runner.xcworkspace   # 在 Xcode 中设置签名后运行
```

要求：Flutter stable（≥3.24）、Android minSdk 23 / iOS 15.5+。

推送到 GitHub 后，仓库自带的 GitHub Actions（`.github/workflows/build.yml`）会自动构建 APK；打 `v*` 标签（如 `git tag v1.0.0 && git push --tags`）会同时构建 iOS 未签名包并发布到 Releases。

## 目录结构

```
lib/
├── main.dart                 # 入口 + 底部导航
├── app_state.dart            # 核心状态机：录音/识别/翻译/持久化
├── models.dart               # Session / Segment 数据模型
├── languages.dart            # 支持的语言表
├── widgets.dart              # 共享组件
├── services/
│   ├── stt_service.dart      # 实时语音识别（speech_to_text）
│   ├── recorder_service.dart # 长时间录音（record）
│   └── translation_service.dart # 离线翻译（google_mlkit_translation）
└── screens/                  # 主页 / 历史 / 详情 / 设置
```

## 常见问题

- **首次开始时提示“正在准备离线翻译模型”**：正常，每个语言约 30MB，只需一次，之后完全离线。
- **Android 每次开始/停顿有提示音**：系统识别服务的自带行为，无法由应用关闭。
- **长时间连续识别**：系统会在静音或约 1 分钟后结束单次识别会话，应用会自动无缝重启识别；录音不受影响。
- **iOS 识别用量限制**：iOS 的 Speech 服务按设备/应用有每日额度限制（Apple 官方策略），超限后需次日再用。

## 许可

MIT（见 [LICENSE](LICENSE)）。语音识别、录音、翻译分别依赖 [speech_to_text](https://pub.dev/packages/speech_to_text)、[record](https://pub.dev/packages/record)、[google_mlkit_translation](https://pub.dev/packages/google_mlkit_translation)。
