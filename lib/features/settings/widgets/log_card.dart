import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/logging/models/log_entry.dart';
import 'package:novella/features/settings/widgets/diagnosis_card.dart';

/// 单条日志卡片组件
class LogCard extends StatelessWidget {
  final LogEntry entry;

  const LogCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logColor = _getLogColor(context);
    final logIcon = _getLogIcon();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: logColor.withValues(alpha: 0.3), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () => _copyToClipboard(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：图标 + 时间 + 模块名
              Row(
                children: [
                  Icon(logIcon, size: 20, color: logColor),
                  const SizedBox(width: 8),
                  Text(
                    entry.formattedTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.loggerName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: logColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 日志级别标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: logColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.level.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: logColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 智能诊断（如果有）
              if (entry.diagnosis != null) ...[
                DiagnosisCard(diagnosis: entry.diagnosis!),
                const SizedBox(height: 8),
                Divider(color: colorScheme.outlineVariant),
                const SizedBox(height: 8),
              ],

              // 原始消息
              SelectableText(
                entry.message,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                  height: 1.4,
                ),
              ),

              // 错误信息（如果有）
              if (entry.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Error: ${entry.error}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getLogColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entry.level >= Level.SEVERE) {
      return colorScheme.error;
    } else if (entry.level >= Level.WARNING) {
      return const Color(0xFFFFA726); // Orange 400
    } else if (entry.level >= Level.INFO) {
      return colorScheme.primary;
    } else {
      return colorScheme.secondary;
    }
  }

  IconData _getLogIcon() {
    if (entry.level >= Level.SEVERE) {
      return Icons.error;
    } else if (entry.level >= Level.WARNING) {
      return Icons.warning_amber;
    } else if (entry.level >= Level.INFO) {
      return Icons.info;
    } else {
      return Icons.code;
    }
  }

  void _copyToClipboard(BuildContext context) {
    final text =
        '''
[${entry.formattedTime}] ${entry.loggerName}
Level: ${entry.level.name}
Message: ${entry.message}
${entry.error != null ? 'Error: ${entry.error}' : ''}
'''.trim();

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }
}
