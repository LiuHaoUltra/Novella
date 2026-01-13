import 'package:flutter/material.dart';

/// 诊断严重程度
enum DiagnosisSeverity { info, warning, error, critical }

/// 日志诊断结果
class LogDiagnosis {
  final String problemId;
  final IconData icon;
  final String title;
  final String description;
  final String solution;
  final DiagnosisSeverity severity;

  const LogDiagnosis({
    required this.problemId,
    required this.icon,
    required this.title,
    required this.description,
    required this.solution,
    required this.severity,
  });

  /// 获取严重程度对应的颜色
  Color getColor(ColorScheme colorScheme) {
    switch (severity) {
      case DiagnosisSeverity.critical:
      case DiagnosisSeverity.error:
        return colorScheme.error;
      case DiagnosisSeverity.warning:
        return const Color(0xFFFFA726); // Material Orange 400
      case DiagnosisSeverity.info:
        return colorScheme.primary;
    }
  }

  /// 获取严重程度对应的图标
  IconData getSeverityIcon() {
    switch (severity) {
      case DiagnosisSeverity.critical:
        return Icons.dangerous;
      case DiagnosisSeverity.error:
        return Icons.error_outline;
      case DiagnosisSeverity.warning:
        return Icons.warning_amber;
      case DiagnosisSeverity.info:
        return Icons.info_outline;
    }
  }
}
