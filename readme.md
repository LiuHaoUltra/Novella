# Novella

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-000000?logo=rust&logoColor=white)
![License](https://img.shields.io/badge/License-AGPL%203.0-blue)

**简洁的轻小说阅读器**

基于 Flutter + Rust FFI 构建，为您提供流畅、纯净的阅读体验。

</div>

## ✨ 核心特性

- **阅读体验**：自定义排版、字体与主题，支持沉浸式阅读与阅读时长统计。
- **流畅性能**：通过 Rust FFI 优化核心逻辑，快速加载。
- **界面设计**：采用 Material Design 3 设计语言，支持动态色彩提取。
- **内容丰富**：集成多维度榜单、搜索与详细的书籍元数据。
- **智能防护**：内置请求队列与自动限流机制，保障服务稳定性。

## 🛠️ 技术栈

- **UI 框架**: Flutter (Riverpod 状态管理)
- **底层核心**: Rust (通过 `flutter_rust_bridge` 调用)
- **通信协议**: SignalR + MessagePack (二进制通讯)
- **字体引擎**: 基于 Rust 的 WOFF2 动态转码与解混淆

## 🚀 快速开始

### 环境需​​求
- Flutter 3.7.2+
- Rust Stable
- Windows / macOS / Linux / Android / iOS

### 构建运行

```bash
# 1. 克隆项目
git clone https://github.com/LiuHaoUltra/Novella.git

# 2. 生成 FFI 绑定
flutter_rust_bridge_codegen generate

# 3. 运行
flutter run
```

## 🙏 致谢

本项目参考了 [LightNovelShelf Web](https://github.com/LightNovelShelf/Web) 的实现与数据结构，特此感谢。

## ⚠️ 免责声明

本项目仅供学习交流使用，严禁用于商业用途。

