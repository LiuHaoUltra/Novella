import 'package:flutter/material.dart';
import 'package:novella/core/logging/models/log_diagnosis.dart';

/// 智能诊断卡片组件
class DiagnosisCard extends StatelessWidget {
  final LogDiagnosis diagnosis;

  const DiagnosisCard({super.key, required this.diagnosis});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = diagnosis.getColor(colorScheme);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(diagnosis.icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diagnosis.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Icon(diagnosis.getSeverityIcon(), size: 16, color: color),
            ],
          ),

          const SizedBox(height: 8),

          // 描述
          Text(
            diagnosis.description,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 8),

          // 解决方案
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  diagnosis.solution,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
