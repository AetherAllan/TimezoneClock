# TimezoneClock

原生 SwiftUI 菜单栏时钟。默认显示北京时间，点击菜单栏文字打开世界时钟。

## 使用

- 点击一个时区，将它设为菜单栏常驻时区。
- 点击右上角 `+`，搜索城市名称、时区标识或中文时区名称后添加。
- 点击时区右侧 `−` 移除；至少保留一个时区。移除常驻时区后自动切换到第一个剩余时区。
- 选择会自动保存，退出并重新打开后恢复。
- “登录时启动”读取系统的真实注册状态；如系统要求批准，点击面板里的“打开登录项设置”。

常用城市使用中文名称，其他城市使用系统时区标识中的城市名。可以搜索 `北京`、`Los Angeles`、`America/New_York` 等。

## 构建与检查

要求 macOS 14 或更新版本，以及支持 Swift 6 的 Xcode。项目不使用第三方依赖。

```sh
./check.sh
xcodebuild -project TimezoneClock.xcodeproj -scheme TimezoneClock \
  -configuration Release -derivedDataPath /tmp/TimezoneClockBuild build
```

构建产物位于 `/tmp/TimezoneClockBuild/Build/Products/Release/TimezoneClock.app`。Xcode 工程使用本机运行签名；当前交付用于本机，不包含商店发布、公证或自动更新。

登录启动前请将应用放在稳定的位置，例如 `/Applications/TimezoneClock.app`，并从该位置启动。更新已安装的应用前先从时钟面板退出，替换后再打开。

## 系统时区

在“系统设置 → 通用 → 日期与时间”中，保持自动设置日期与时间，关闭根据当前位置自动设置时区，选择洛杉矶。

应用独立使用每个时区的标识换算同一个当前时刻，自动处理夏令时，不更改系统时区或实际时刻。
