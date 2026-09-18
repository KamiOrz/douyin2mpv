# douyin2mpv

<p><img src="assets/AppIcon.png" width="96" alt="douyin2mpv icon"></p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

原生 macOS GUI：粘贴抖音直播链接，获取临时直播流并使用本机 mpv 播放。SwiftUI + Swift Package Manager，无第三方代码依赖。

## 使用

打开 `dist/Douyin2MPV.app`，粘贴链接，点击「用 mpv 播放」。默认使用直播源的最高档 HLS。主界面采用紧凑不透明横条，颜色自动跟随系统浅色 / 深色外观，仅保留链接输入、播放和状态。需要更改画质时打开右上角设置，点击「解析画质」，选择画质 / 格式，再播放。每次点击播放会重新获取地址，并尽量保留所选画质。

支持：

- `https://live.douyin.com/640145788197`
- `https://www.douyin.com/follow/live/640145788197?anchor_id=…`
- `https://www.douyin.com/jingxuan/search/…?live_web_rid=640145788197&type=general`
- 纯数字房间号，以及包含上述 URL 的分享文本 / Markdown

不支持短链接 `v.douyin.com`、普通视频链接或单独的搜索关键词。直播间号与主播账号 ID 不一定相同。

自动寻找 `/Applications/mpv.app`、用户 Applications 中的 mpv.app、`/opt/homebrew/bin/mpv` 和 `/usr/local/bin/mpv`。也可以选择自己的 mpv 程序。播放器路径及上次输入保存在 macOS UserDefaults 中。应用不读取浏览器 Cookie。

「复制地址」与「导出 M3U」使用当前解析结果，地址有有效期。关闭工具不会关闭已启动的 mpv。再次播放会打开新的 mpv 实例。

## 开发与构建

要求 macOS 13+、Swift 6 工具链（Xcode Command Line Tools）和单独安装的 mpv。

```sh
git clone https://github.com/KamiOrz/douyin2mpv.git
cd douyin2mpv
swift test
./script/build_and_run.sh
```

`build-app.sh` 构建 debug 可执行文件、组装 app bundle 并做本机 ad-hoc 签名。产物适用于当前 Mac 的架构；未做 Developer ID 签名或公证。

测试在线直播（可选，房间必须正在直播）：

```sh
DOUYIN_TEST_ROOM=640145788197 swift test --filter testLiveIntegration
```

## 实现与限制

从官方直播页面的 `hls_pull_url_map` / `flv_pull_url` 解析 URL，并解码 JSON 中的转义字符。通过 Foundation Process 直接传递参数启动 mpv，不将用户输入交给 shell。网络解析异步执行，可取消，单次页面请求超时为 25 秒。

直播未开播、页面需要验证或抖音修改页面结构时，解析会失败。此时可在浏览器确认直播状态后重试；工具不绕过验证码。画质名称是源端档位的提示，实际分辨率取决于主播及 CDN。播放器成功启动不代表一定有画面；mpv 非零退出时会在工具中提示。

播放器诊断日志：`~/Library/Application Support/douyin2mpv/mpv.log`。日志可能含临时直播 URL，请勿直接公开。

## 目录

- `Sources/DouyinCore`：链接识别、页面请求和流解析
- `Sources/Douyin2MPV`：SwiftUI 窗口和 mpv 启动
- `Tests/DouyinCoreTests`：离线解析测试和可选在线验证
- `scripts/build-app.sh`：生成可双击的应用

## 应用图标

米白底、黑色播放符号和红色切片。源图为 `assets/AppIcon.png`，由内置图像生成工具按已选方案提取；`scripts/build-icon.sh` 使用系统 sips / iconutil 生成完整尺寸的 ICNS。打包脚本自动加入应用资源与图标配置，主窗口也使用同一图标。

## 贡献

欢迎提交 Issue 和 Pull Request。修改解析逻辑时请补充离线测试，并运行 `swift test`；涉及界面的改动请同时验证 `./script/build_and_run.sh`。

## 协议

本项目采用 [MIT License](LICENSE)。mpv 为独立安装的外部程序，不包含在本项目中。本项目与抖音及 mpv 官方无隶属关系。
