import 'package:logging/logging.dart';
import 'package:novella/core/logging/models/log_diagnosis.dart';
import 'package:novella/core/logging/log_diagnostics.dart';

/// 日志条目模型
class LogEntry {
  final Level level;
  final String loggerName;
  final String message;
  final DateTime time;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.level,
    required this.loggerName,
    required this.message,
    required this.time,
    this.error,
    this.stackTrace,
  });

  /// 从 LogRecord 创建
  factory LogEntry.fromRecord(LogRecord record) {
    return LogEntry(
      level: record.level,
      loggerName: record.loggerName,
      message: record.message,
      time: record.time,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }

  /// 获取智能诊断结果
  LogDiagnosis? get diagnosis => LogDiagnostics.diagnose(this);

  /// 获取格式化的时间字符串
  String get formattedTime {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
