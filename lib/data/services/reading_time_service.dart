import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读时长追踪服务
/// 存储每日阅读分钟数
/// 不云同步 - 纯本地统计
class ReadingTimeService {
  static final Logger _logger = Logger('ReadingTimeService');
  static final ReadingTimeService _instance = ReadingTimeService._internal();

  factory ReadingTimeService() => _instance;
  ReadingTimeService._internal();

  // 会话开始时间键
  static const _sessionStartKey = 'reading_session_start';
  // 每日时长键前缀
  static const _dailyTimePrefix = 'reading_time_';
  // 保留 60 天
  static const _maxDaysToKeep = 60;

  // 会话开始时间内存缓存
  int? _sessionStartMs;

  /// 开始阅读会话
  /// 进入阅读页或从后台返回时调用
  Future<void> startSession() async {
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;

    // 持久化备份
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionStartKey, _sessionStartMs!);

    _logger.info('Reading session started at $_sessionStartMs');
  }

  /// 结束会话 - 计算时长并累加
  /// 离开阅读页或进入后台时调用
  Future<void> endSession() async {
    // 尝试恢复丢失会话（崩溃恢复）
    if (_sessionStartMs == null) {
      final prefs = await SharedPreferences.getInstance();
      _sessionStartMs = prefs.getInt(_sessionStartKey);
    }

    if (_sessionStartMs == null) {
      _logger.warning('endSession called but no session was started');
      return;
    }

    final endMs = DateTime.now().millisecondsSinceEpoch;
    final durationMs = endMs - _sessionStartMs!;
    final durationMinutes = durationMs ~/ 60000; // 转为分钟

    // 仅记录 1分钟 - 12小时（合理性检查）
    // 假设 > 12小时 为异常，丢弃
    if (durationMinutes >= 1 && durationMinutes < 720) {
      await _addMinutesToDay(DateTime.now(), durationMinutes);
      _logger.info('Reading session ended: $durationMinutes minutes recorded');
    } else {
      _logger.info(
        'Reading session ignored: $durationMinutes minutes (too short or too long)',
      );
    }

    // 清除会话
    _sessionStartMs = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStartKey);
  }

  /// 恢复中断会话（如崩溃后）。
  /// 决定：清理陈旧标志。
  Future<void> recoverSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_sessionStartKey)) {
      _logger.info('Found stale reading session, cleaning up...');
      await prefs.remove(_sessionStartKey);
    }
  }

  /// 增加指定日期的分钟数
  Future<void> _addMinutesToDay(DateTime date, int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForDate(date);

    final existing = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, existing + minutes);

    _logger.fine('Added $minutes min to $key (total: ${existing + minutes})');

    // 定期清理旧数据（1%概率）
    if (DateTime.now().millisecond % 100 == 0) {
      await _cleanupOldData();
    }
  }

  /// 获取本周总阅读分钟数（周一至周日）
  Future<int> getWeeklyMinutes() async {
    final now = DateTime.now();
    // Calculate the start of the week (Monday)
    final weekday = now.weekday; // 1 = 周一, 7 = 周日
    final monday = DateTime(now.year, now.month, now.day - (weekday - 1));

    int total = 0;
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(now)) break; // 不统计未来日期

      final key = _keyForDate(day);
      total += prefs.getInt(key) ?? 0;
    }

    _logger.info('Weekly reading time: $total minutes');
    return total;
  }

  /// 获取本月总阅读分钟数
  Future<int> getMonthlyMinutes() async {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    int total = 0;
    final prefs = await SharedPreferences.getInstance();

    // 遍历本月至今
    var day = firstDayOfMonth;
    while (!day.isAfter(now)) {
      final key = _keyForDate(day);
      total += prefs.getInt(key) ?? 0;
      day = day.add(const Duration(days: 1));
    }

    _logger.info('Monthly reading time: $total minutes');
    return total;
  }

  /// 生成日期键
  String _keyForDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$_dailyTimePrefix$dateStr';
  }

  /// 移除 60 天前的数据
  Future<void> _cleanupOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final cutoffDate = DateTime.now().subtract(Duration(days: _maxDaysToKeep));

    final allKeys = prefs.getKeys();
    int removed = 0;

    for (final key in allKeys) {
      if (!key.startsWith(_dailyTimePrefix)) continue;

      // 解析日期
      final dateStr = key.substring(_dailyTimePrefix.length);
      try {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final date = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );

          if (date.isBefore(cutoffDate)) {
            await prefs.remove(key);
            removed++;
          }
        }
      } catch (e) {
        // Invalid key format, skip
      }
    }

    if (removed > 0) {
      _logger.info('Cleaned up $removed old reading time entries');
    }
  }

  /// 检查是否有活跃会话（调试）
  bool get hasActiveSession => _sessionStartMs != null;
}
