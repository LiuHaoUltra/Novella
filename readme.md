# 📚 Novella

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-000000?logo=rust&logoColor=white)
![License](https://img.shields.io/badge/License-AGPL%203.0-blue)

**轻书架第三方客户端**

基于 Flutter + Rust FFI 构建，提供纯净的界面和阅读体验。

<br/>

<table align="center">
    <tr>
        <td width="25%"><img src="assets/screenshots_1.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_2.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_3.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_4.PNG" width="100%"></td>
    </tr>
    <tr>
        <td width="25%"><img src="assets/screenshots_5.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_6.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_7.PNG" width="100%"></td>
        <td width="25%"><img src="assets/screenshots_8.PNG" width="100%"></td>
    </tr>
</table>

## 🚧 注意事项

- 本项目处于快速迭代阶段，功能尚不完善，可能存在较多问题。请谨慎使用。

## ✨ 核心特性

- **阅读体验**：支持字号调节、简繁转换与段落间距调整。提供多种预设纯色背景及自定义背景色。
- **界面设计**：适配 Material Design 3，支持从封面提取动态主题色，提供浅色/深色/纯黑模式。
- **云端同步**：支持 GitHub Gist 同步，阅读时长、书籍标记、多端进度互通。
- **内容发现**：集成多维度榜单，支持按等级/标签筛选或屏蔽内容。

## 🛠️ 技术栈

- **UI 框架**：Flutter (Riverpod)
- **底层核心**：Rust (通过 `flutter_rust_bridge` 调用)
- **通信协议**：SignalR + MessagePack (二进制通讯)
- **字体引擎**：基于 Rust 的 WOFF2 动态转码与解混淆

## 📬 反馈与交流

- 💡 **哇，新点子！** [前往 Discussions 讨论](https://github.com/LiuHaoUltra/Novella/discussions/7)
- 🐛 **发现问题？** [提交 Issue 反馈](https://github.com/LiuHaoUltra/Novella/issues/new?labels=bug)

## 🚀 快速开始

### 环境需求
- Flutter 3.7.2+
- Rust Stable（可选，仓库已包含预编译文件）

### 构建运行

```bash
# 1. 安装 Git LFS
git lfs install

# 2. 克隆项目
git clone https://github.com/LiuHaoUltra/Novella.git

# 3. 运行
flutter run
```

## 🙏 致谢

- 本项目参考了 [LightNovelShelf Web](https://github.com/LightNovelShelf/Web) 的实现与数据结构，特此感谢。
- 于此处前往 [轻书架](https://www.lightnovel.app) 站点。

## ⚠️ 免责声明

- 本项目仅供学习交流使用，严禁用于商业用途。
