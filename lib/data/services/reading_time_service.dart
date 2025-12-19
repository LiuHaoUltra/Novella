import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for tracking local reading time.
/// Stores daily reading minutes in SharedPreferences.
/// Does not sync with cloud - purely local statistics.
class ReadingTimeService {
  static final Logger _logger = Logger('ReadingTimeService');
  static final ReadingTimeService _instance = ReadingTimeService._internal();

  factory ReadingTimeService() => _instance;
  ReadingTimeService._internal();

  // Key for storing session start timestamp
  static const _sessionStartKey = 'reading_session_start';
  // Prefix for daily reading time keys
  static const _dailyTimePrefix = 'reading_time_';
  // Keep data for 60 days
  static const _maxDaysToKeep = 60;

  // In-memory cache of session start time
  int? _sessionStartMs;

  /// Start a reading session - records current timestamp.
  /// Called when entering ReaderPage or returning from background.
  Future<void> startSession() async {
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;

    // Also persist to SharedPreferences as backup
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionStartKey, _sessionStartMs!);

    _logger.info('Reading session started at $_sessionStartMs');
  }

  /// End a reading session - calculates duration and adds to daily total.
  /// Called when leaving ReaderPage or going to background.
  Future<void> endSession() async {
    // If no memory session, try checking disk for a lost session (crash recovery)
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
    final durationMinutes = durationMs ~/ 60000; // Convert to minutes

    // Only record if at least 1 minute and less than 12 hours (sanity check)
    // If it's absurdly long (e.g. 5 days from a crash), we likely discard it or cap it.
    // For now, let's discard if > 12 hours (720 min) assuming it was a mistake/crash.
    if (durationMinutes >= 1 && durationMinutes < 720) {
      await _addMinutesToDay(DateTime.now(), durationMinutes);
      _logger.info('Reading session ended: $durationMinutes minutes recorded');
    } else {
      _logger.info(
        'Reading session ignored: $durationMinutes minutes (too short or too long)',
      );
    }

    // Clear session
    _sessionStartMs = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionStartKey);
  }

  /// Recover an interrupted session (e.g. after crash).
  /// This should be called on app startup.
  /// If a session was left open, we can't reliably know when it "ended".
  /// The safest strategy is to DISCARD the old session to avoid adding 10 hours of reading time
  /// just because the user opened the app the next day.
  /// OR, we could cap it if it's within a reasonable window.
  /// Given the requirement "ensure data not lost", the user might expect *some* recovery.
  /// But "Time Stamp Difference" strategy fails if we don't have an "End" time.
  ///
  /// Decision: Simply clean up the stale flag so we don't think we are reading.
  /// Real-time updates happen on lifecycle changes, so legitimate reading is likely saved.
  Future<void> recoverSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_sessionStartKey)) {
      _logger.info('Found stale reading session, cleaning up...');
      await prefs.remove(_sessionStartKey);
    }
  }

  /// Add minutes to a specific day's total.
  Future<void> _addMinutesToDay(DateTime date, int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForDate(date);

    final existing = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, existing + minutes);

    _logger.fine('Added $minutes min to $key (total: ${existing + minutes})');

    // Cleanup old data periodically (1% chance per call)
    if (DateTime.now().millisecond % 100 == 0) {
      await _cleanupOldData();
    }
  }

  /// Get total reading minutes for the current week (Monday to Sunday).
  Future<int> getWeeklyMinutes() async {
    final now = DateTime.now();
    // Calculate the start of the week (Monday)
    final weekday = now.weekday; // 1 = Monday, 7 = Sunday
    final monday = DateTime(now.year, now.month, now.day - (weekday - 1));

    int total = 0;
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(now)) break; // Don't count future days

      final key = _keyForDate(day);
      total += prefs.getInt(key) ?? 0;
    }

    _logger.info('Weekly reading time: $total minutes');
    return total;
  }

  /// Get total reading minutes for the current month.
  Future<int> getMonthlyMinutes() async {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    int total = 0;
    final prefs = await SharedPreferences.getInstance();

    // Iterate from first day of month to today
    var day = firstDayOfMonth;
    while (!day.isAfter(now)) {
      final key = _keyForDate(day);
      total += prefs.getInt(key) ?? 0;
      day = day.add(const Duration(days: 1));
    }

    _logger.info('Monthly reading time: $total minutes');
    return total;
  }

  /// Generate storage key for a specific date.
  String _keyForDate(DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$_dailyTimePrefix$dateStr';
  }

  /// Remove reading time data older than 60 days.
  Future<void> _cleanupOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final cutoffDate = DateTime.now().subtract(Duration(days: _maxDaysToKeep));

    final allKeys = prefs.getKeys();
    int removed = 0;

    for (final key in allKeys) {
      if (!key.startsWith(_dailyTimePrefix)) continue;

      // Parse date from key: reading_time_2025-12-20
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

  /// Check if there's an active session (for debugging).
  bool get hasActiveSession => _sessionStartMs != null;
}
