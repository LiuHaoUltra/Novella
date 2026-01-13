import 'package:flutter/material.dart';
import 'package:novella/core/logging/models/log_entry.dart';
import 'package:novella/core/logging/models/log_diagnosis.dart';

/// 日志诊断引擎
/// 根据日志内容智能识别问题并提供解决方案
class LogDiagnostics {
  /// 诊断日志条目
  static LogDiagnosis? diagnose(LogEntry entry) {
    final msg = entry.message.toLowerCase();
    final logger = entry.loggerName;

    // ===== 同步相关问题 =====
    if (logger == 'SyncManager') {
      // 网络超时
      if (msg.contains('timeout') || msg.contains('超时')) {
        return const LogDiagnosis(
          problemId: 'sync_timeout',
          icon: Icons.wifi_off,
          title: '同步超时',
          description: 'GitHub 连接超时，可能是网络不稳定',
          solution: '检查网络连接；如果使用代理，请确保配置正确；系统会自动重试',
          severity: DiagnosisSeverity.warning,
        );
      }

      // 密码错误
      if (msg.contains('密码') || msg.contains('解密失败')) {
        return const LogDiagnosis(
          problemId: 'sync_password_error',
          icon: Icons.lock_outline,
          title: '同步密码错误',
          description: '无法解密云端数据，可能是密码不正确',
          solution: '前往【设置 → 云同步】重新设置同步密码',
          severity: DiagnosisSeverity.error,
        );
      }

      // Token 过期
      if (msg.contains('unauthorized') || msg.contains('token')) {
        return const LogDiagnosis(
          problemId: 'sync_auth_expired',
          icon: Icons.key_off,
          title: 'GitHub 授权失效',
          description: '访问令牌已过期或被撤销',
          solution: '前往【设置 → 云同步】点击"断开连接"后重新授权',
          severity: DiagnosisSeverity.error,
        );
      }

      // 重试中
      if (msg.contains('retrying') ||
          msg.contains('retry') ||
          msg.contains('重试')) {
        return const LogDiagnosis(
          problemId: 'sync_retrying',
          icon: Icons.refresh,
          title: '同步重试中',
          description: '检测到临时故障，系统正在自动重试',
          solution: '无需操作，系统会自动恢复；如果持续失败请检查网络',
          severity: DiagnosisSeverity.info,
        );
      }

      // 同步成功
      if (msg.contains('completed successfully') || msg.contains('同步完成')) {
        return const LogDiagnosis(
          problemId: 'sync_success',
          icon: Icons.cloud_done,
          title: '同步成功',
          description: '数据已成功同步到 GitHub Gist',
          solution: '数据已备份，可放心使用',
          severity: DiagnosisSeverity.info,
        );
      }
    }

    // ===== Gist 服务问题 =====
    if (logger == 'GistSyncService') {
      // Gist 不存在
      if (msg.contains('404') || msg.contains('not found')) {
        return const LogDiagnosis(
          problemId: 'gist_not_found',
          icon: Icons.cloud_off,
          title: '云端数据丢失',
          description: 'GitHub Gist 文件未找到或已被删除',
          solution: '下次同步会自动创建新的 Gist；建议手动触发一次同步',
          severity: DiagnosisSeverity.warning,
        );
      }

      // Gist 冲突
      if (msg.contains('409') || msg.contains('conflict')) {
        return const LogDiagnosis(
          problemId: 'gist_conflict',
          icon: Icons.merge_type,
          title: '同步冲突',
          description: '多设备同时修改导致冲突',
          solution: '系统会自动重试并合并数据；建议稍后检查数据一致性',
          severity: DiagnosisSeverity.warning,
        );
      }

      // Device Flow 成功
      if (msg.contains('device code received') ||
          msg.contains('access token obtained')) {
        return const LogDiagnosis(
          problemId: 'auth_success',
          icon: Icons.verified_user,
          title: 'GitHub 授权成功',
          description: '已成功连接到 GitHub',
          solution: '现在可以使用云同步功能',
          severity: DiagnosisSeverity.info,
        );
      }
    }

    // ===== Rust FFI 问题 =====
    if (msg.contains('rustlib') || msg.contains('ffi') || logger == 'Flutter') {
      if (msg.contains('failed') || msg.contains('error')) {
        return const LogDiagnosis(
          problemId: 'rust_ffi_error',
          icon: Icons.memory,
          title: 'FFI 初始化失败',
          description: '繁简转换引擎加载失败',
          solution: '繁简转换功能不可用；请检查应用是否完整安装',
          severity: DiagnosisSeverity.error,
        );
      }
    }

    // ===== 网络错误 =====
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('network error')) {
      return const LogDiagnosis(
        problemId: 'network_error',
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
        title: '网络连接失败',
        description: '无法连接到服务器',
        solution: '检查网络连接和防火墙设置',
        severity: DiagnosisSeverity.error,
      );
    }

    // ===== HTTP 错误码 =====
    if (msg.contains('403') || msg.contains('forbidden')) {
      return const LogDiagnosis(
        problemId: 'http_forbidden',
        icon: Icons.block,
        title: '访问被拒绝',
        description: '服务器拒绝了请求',
        solution: '可能是权限不足或请求过于频繁；请稍后重试',
        severity: DiagnosisSeverity.error,
      );
    }

    if (msg.contains('500') || msg.contains('internal server error')) {
      return const LogDiagnosis(
        problemId: 'server_error',
        icon: Icons.dns_outlined,
        title: '服务器错误',
        description: '服务器内部错误',
        solution: '这是服务端的问题，请稍后重试',
        severity: DiagnosisSeverity.error,
      );
    }

    return null; // 无匹配规则
  }
}
