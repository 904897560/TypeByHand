# TypeByHand

一个 macOS 小工具：把密码**逐字符模拟键盘输入**，用来填写那些禁止粘贴的密码框。

A tiny macOS app that types your password key by key, for password fields that block paste.

## 功能

- 密码输入框，可勾选“显示密码”核对内容
- 自定义延迟（0 到 600 秒，支持小数），点按钮后倒计时，期间切换到目标输入框
- 全局快捷键：在任意程序里按下，立即向当前焦点输入框键入密码
- 快捷键与延迟会保存，密码**不会**保存，退出即丢失

## 安装

需要 macOS 13 及以上，以及 Xcode 或 Command Line Tools（含 Swift）。

```sh
git clone https://github.com/904897560/TypeByHand.git
cd TypeByHand
./build_app.sh
open TypeByHand.app
```

可选：在项目根目录放一个 `AppIcon.icns`，构建时会自动作为应用图标。

## 使用

1. 首次打开，点“授予辅助功能权限”，在 系统设置 > 隐私与安全性 > 辅助功能 中打开 TypeByHand，然后重启应用。
2. 输入密码。
3. 二选一：
   - 点“开始输入”，在倒计时结束前点击目标密码框
   - 点“快捷键”录制组合键（需包含 ⌘ ⌃ ⌥ ⇧ 之一），之后在目标程序里按下即可

## 注意

- 应用使用 ad-hoc 签名。重新构建后，macOS 可能要求重新授权辅助功能；从网上下载的版本首次打开需要右键选“打开”。
- 开启了 Secure Input 的程序（如部分终端设置）可能拦截模拟输入，可尝试加大延迟或关闭该选项。
- 快捷键被其他程序占用时会提示注册失败，换一个组合即可。
- 本工具通过辅助功能权限向其他程序发送按键事件。请只用于输入你自己的密码，并在可信的设备上使用。

## 工作原理

- `CGEvent` + `keyboardSetUnicodeString` 逐字符发送键盘事件，不依赖键盘布局
- Carbon `RegisterEventHotKey` 注册全局快捷键
- 纯 AppKit 实现，无第三方依赖

## 许可证

[MIT](LICENSE)
