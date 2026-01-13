import 'package:logging/logging.dart';
import 'package:novella/core/logging/models/log_entry.dart';

/// 日志缓冲服务
/// 捕获所有应用日志到内存缓冲区
class LogBufferService {
  static final List<LogEntry> _buffer = [];
  static const int _maxSize = 1000;
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;

    // 设置日志级别为 INFO，过滤掉过于详细的调试日志 (FINEST/FINER/FINE)
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      final entry = LogEntry.fromRecord(record);
      _buffer.add(entry);

      // 保持缓冲区大小限制
      if (_buffer.length > _maxSize) {
        _buffer.removeAt(0);
      }
    });

    _initialized = true;
  }

  /// 获取所有日志
  static List<LogEntry> getLogs({Level? minLevel, String? loggerName}) {
    var logs = List<LogEntry>.from(_buffer);

    // 按日志级别过滤
    if (minLevel != null) {
      logs = logs.where((e) => e.level >= minLevel).toList();
    }

    // 按模块名过滤
    if (loggerName != null) {
      logs = logs.where((e) => e.loggerName == loggerName).toList();
    }

    return logs;
  }

  /// 清空日志缓冲区
  static void clear() {
    _buffer.clear();
  }

  /// 获取所有模块名
  static Set<String> getLoggerNames() {
    return _buffer.map((e) => e.loggerName).toSet();
  }

  /// 获取日志统计信息
  static Map<Level, int> getStatistics() {
    final stats = <Level, int>{};
    for (final entry in _buffer) {
      stats[entry.level] = (stats[entry.level] ?? 0) + 1;
    }
    return stats;
  }
}
