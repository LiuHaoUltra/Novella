import 'dart:io';
import 'package:flutter/foundation.dart';

/// 提供平台检测和 iOS 版本信息
///
/// 此类帮助确定当前平台和 iOS 版本，以根据平台功能启用自适应组件渲染。
class PlatformInfo {
  /// 用于测试或用户偏好的样式覆盖
  ///
  /// 设置为 'ios26' 强制使用 iOS 26 样式，'ios18' 为 iOS 18 样式，
  /// 'md3' 为 Material Design 3，或设为 null 以使用默认平台检测。
  static String? styleOverride;

  /// 如果当前平台是 iOS，则返回 true
  static bool get isIOS {
    if (styleOverride == 'md3') return false;
    return !kIsWeb && Platform.isIOS;
  }

  /// 如果当前平台是 Android，则返回 true
  static bool get isAndroid {
    if (styleOverride == 'md3') return true;
    return !kIsWeb && Platform.isAndroid;
  }

  /// 如果当前平台是 macOS，则返回 true
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// 如果当前平台是 Windows，则返回 true
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 如果当前平台是 Linux，则返回 true
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 如果当前平台是 Fuchsia，则返回 true
  static bool get isFuchsia => !kIsWeb && Platform.isFuchsia;

  /// 如果在 Web 上运行，则返回 true
  static bool get isWeb => kIsWeb;

  /// 返回 iOS 主版本号
  ///
  /// 如果未在 iOS 上运行或无法确定版本，则返回 0。
  /// 示例：对于 iOS 26.1.2，返回 26
  static int get iOSVersion {
    if (!(!kIsWeb && Platform.isIOS)) return 0;

    try {
      final version = Platform.operatingSystemVersion;
      // 从字符串如 "Version 26.1.2 (Build 20A123)" 中提取主版本号
      final match = RegExp(r'Version (\d+)').firstMatch(version);
      if (match != null) {
        return int.parse(match.group(1)!);
      }

      // 回退：尝试解析版本字符串中的第一个数字
      final fallbackMatch = RegExp(r'(\d+)').firstMatch(version);
      if (fallbackMatch != null) {
        return int.parse(fallbackMatch.group(1)!);
      }
    } catch (e) {
      debugPrint('Error parsing iOS version: $e');
    }

    return 0;
  }

  /// 如果 iOS 版本为 26 或更高，则返回 true
  ///
  /// 用于确定是否应使用 iOS 26+ 特定组件。
  /// 如果设置了 [styleOverride]，则其优先级高于平台检测。
  static bool isIOS26OrHigher() {
    // 首先检查样式覆盖
    if (styleOverride != null && isIOS) {
      return styleOverride == 'ios26';
    }
    return isIOS && iOSVersion >= 26;
  }

  /// 如果物理设备确实是 iOS 26+，则返回 true (忽略样式覆盖)
  static bool isNativeIOS26OrHigher() {
    return !kIsWeb && Platform.isIOS && iOSVersion >= 26;
  }

  /// 如果 iOS 版本为 18 或更低（pre-iOS 26），则返回 true
  ///
  /// 用于确定是否应使用旧版 Cupertino 组件。
  /// 如果设置了 [styleOverride]，则其优先级高于平台检测。
  static bool isIOS18OrLower() {
    // 首先检查样式覆盖
    if (styleOverride != null && isIOS) {
      return styleOverride == 'ios18';
    }
    return isIOS && iOSVersion > 0 && iOSVersion < 26;
  }

  /// 如果应使用 Material Design 3 样式，则返回 true
  ///
  /// 对于 Android，或者如果在 iOS 上 [styleOverride] 为 'md3'，则为 true。
  static bool useMD3Style() {
    if (styleOverride != null && isIOS) {
      return styleOverride == 'md3';
    }
    return isAndroid;
  }

  /// 如果 iOS 版本在特定范围内，则返回 true
  ///
  /// [min] - 最小 iOS 版本（包含）
  /// [max] - 最大 iOS 版本（包含）
  static bool isIOSVersionInRange(int min, int max) {
    return isIOS && iOSVersion >= min && iOSVersion <= max;
  }

  /// 返回人类可读的平台描述
  static String get platformDescription {
    if (isIOS) return 'iOS $iOSVersion';
    if (isAndroid) return 'Android';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (isFuchsia) return 'Fuchsia';
    if (isWeb) return 'Web';
    return 'Unknown';
  }
}
