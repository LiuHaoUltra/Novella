class TimeUtils {
  /// 格式化相对时间（仿 dayjs / Web端逻辑）
  /// [dateTime] 输入时间
  static String formatRelativeTime(DateTime dateTime) {
    // 确保使用 UTC 进行计算，或者都转为 Local
    // 这里建议转为 Local 进行比较
    final now = DateTime.now();
    final date = dateTime.toLocal();
    final diff = now.difference(date);

    final seconds = diff.inSeconds;
    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (seconds < 0) {
      // 防止未来时间显示异常
      return '刚刚';
    }

    if (seconds < 45) {
      return '刚刚';
    } else if (seconds < 90) {
      return '1分钟前';
    } else if (minutes < 45) {
      return '$minutes分钟前';
    } else if (minutes < 90) {
      return '1小时前';
    } else if (hours < 22) {
      return '$hours小时前';
    } else if (hours < 36) {
      return '1天前';
    } else if (days < 26) {
      // 26天以内直接显示天数
      return '$days天前'; // 原逻辑是 roundedDays，这里直接用 days 应该也行，或者保持原逻辑
    } else if (days < 46) {
      return '1个月前';
    } else if (days < 320) {
      // 46 ~ 320 天：按月算
      final months = (days / 30.4).round(); // Average days per month
      return '$months个月前';
    } else if (days < 548) {
      // 320 ~ 548 (1.5年)：1年前
      return '1年前';
    } else {
      // > 1.5年：按年四舍五入
      final years = (days / 365.25).round(); // Account for leap years
      return '$years年前';
    }
  }
}
