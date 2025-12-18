# Novella - 轻小说阅读器

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.7.2+-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.7.2+-0175C2?logo=dart&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-FFI-000000?logo=rust&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS-lightgrey)

</div>

Novella 是一款基于 Flutter 的轻小说阅读器，为 [lightnovel.app](https://www.lightnovel.app) 第三方客户端。采用 Material Design 3 设计语言，支持阅读进度同步、以及智能限流保护。

## ✨ 功能特性

### 📖 阅读体验
- **阅读进度记忆** - 自动保存/恢复阅读位置和滚动状态
- **自定义阅读设置** - 支持字号、行高、主题调节
- **章节导航** - 支持上一章/下一章快速切换

### 🏠 发现与管理
- **首页推荐** - 展示热门榜单
- **搜索功能** - 快速搜索书籍
- **排行榜** - 多维度榜单浏览
- **个人书架** - 云端同步的收藏管理
- **书籍详情** - 动态渐变背景，展示书籍信息和目录

### 🔐 安全机制
- **Token 自动刷新** - 无感知的会话管理
- **智能限流队列** - 5请求/5秒 保护机制，避免账号风控

### 🎨 界面设计
- **Material Design 3** - 现代化设计语言
- **深色/浅色主题** - 支持系统跟随或手动切换

## 🏗️ 技术架构

```
lib/
├── main.dart                    # 应用入口 & 免责声明
├── core/                        # 核心层
│   ├── auth/                    # 认证服务
│   ├── network/                 # 网络层
│   │   ├── signalr_service.dart # SignalR 连接管理
│   │   ├── novel_hub_protocol.dart # MessagePack 协议实现
│   │   ├── request_queue.dart   # 限流队列
│   │   └── api_client.dart      # HTTP 客户端
│   └── utils/
│       └── font_manager.dart    # 字体下载与转换
├── data/                        # 数据层
│   ├── models/                  # 数据模型
│   └── services/                # 业务服务
│       ├── book_service.dart    # 书籍服务
│       ├── chapter_service.dart # 章节服务
│       ├── user_service.dart    # 用户服务
│       └── reading_progress_service.dart # 阅读进度
├── features/                    # 功能模块
│   ├── auth/                    # 登录认证
│   ├── home/                    # 首页
│   ├── search/                  # 搜索
│   ├── ranking/                 # 排行榜
│   ├── book/                    # 书籍详情
│   ├── reader/                  # 阅读器
│   ├── shelf/                   # 书架
│   ├── settings/                # 设置
│   └── main_page.dart           # 主页框架
├── src/
│   └── rust/                    # Rust FFI 生成代码
│       └── api/
│           └── font_converter.dart # WOFF2 转换接口
└── rust/                        # Rust 原生代码
    └── src/
        └── api/
            └── font_converter.rs  # WOFF2→TTF 转换实现
```

## 🔧 核心技术

### SignalR + MessagePack 通信
应用使用 SignalR WebSocket 与服务器通信，数据采用 MessagePack 二进制序列化 + Gzip 压缩：

```dart
// 响应处理流程
SignalR Response → MessagePack 解码 → Gzip 解压 → JSON 解析
```

### 字体反混淆 (Rust FFI)
服务器使用自定义字体进行内容混淆，需要动态加载对应字体才能正确显示：

```dart
// 字体处理流程
WOFF2 URL → 下载 → Rust FFI 转换为 TTF → FontLoader 加载 → Text 渲染
```

采用 `flutter_rust_bridge` v2 实现跨语言调用，使用 `woofwoof` 库进行 WOFF2 解码。

### 限流队列 (Request Queue)
为防止账号被封禁，实现了严格的请求限流机制：

- **最大并发**: 5 请求 / 5 秒
- **队列等待**: 超限请求自动排队
- **优先级**: 支持关键请求绕过队列

```dart
final result = await RequestQueue().enqueue(() => signalR.invoke('GetBookInfo', args: [bookId]));
```

## 📦 依赖项

### Flutter 依赖
| 包名 | 用途 |
|------|------|
| `flutter_riverpod` | 状态管理 |
| `signalr_netcore` | SignalR 客户端 |
| `msgpack_dart` | MessagePack 编解码 |
| `archive` | Gzip 解压 |
| `dio` | HTTP 请求 |
| `cached_network_image` | 图片缓存 |
| `flutter_rust_bridge` | Rust FFI 桥接 |
| `palette_generator` | 封面色彩提取 |
| `window_manager` | 桌面窗口控制 |

### Rust 依赖
| 包名 | 用途 |
|------|------|
| `woofwoof` | WOFF2 解码 |
| `anyhow` | 错误处理 |

## 🚀 快速开始

### 环境要求
- Flutter SDK 3.7.2+
- Dart SDK 3.7.2+
- Rust stable (用于 FFI 编译)
- Windows / macOS / Linux (开发环境)

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone <repository-url>
   cd Novella/App/Flutter
   ```

2. **安装 Flutter 依赖**
   ```bash
   flutter pub get
   ```

3. **生成 Rust FFI 绑定**
   ```bash
   flutter_rust_bridge_codegen generate
   ```

4. **运行应用**
   ```bash
   # Windows (开发)
   flutter run -d windows

   # Android
   flutter run -d <device_id>

   # 发布构建
   flutter run --release
   ```

## ⚙️ 配置

### 设置选项
- **主题**: 浅色 / 深色 / 跟随系统
- **首页榜单类型**: 日榜 / 周榜 / 月榜
- **字体缓存**: 开关、限制数量 (10-60)、清除缓存
- **阅读器设置**: 字号、行高

### 包名更改
如需修改应用包名：
```bash
flutter pub run change_app_package_name:main sh.celia.novella
```

## ⚠️ 免责声明

> **本软件仅供学习研究使用。**
>
> - 请勿进行高频操作
> - 因使用不当导致的账号问题概不负责
> - 严禁用于任何商业用途

应用首次启动时会显示免责声明，用户需同意后方可使用。
