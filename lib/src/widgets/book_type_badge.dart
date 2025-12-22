import 'package:flutter/material.dart';
import 'package:novella/data/models/book.dart';

/// A badge widget that displays book type (录入/翻译/转载) as an icon
/// Positioned at bottom-right corner, similar style to ranking badge
class BookTypeBadge extends StatelessWidget {
  final BookCategory? category;

  const BookTypeBadge({super.key, this.category});

  @override
  Widget build(BuildContext context) {
    if (category == null || category!.shortName.isEmpty) {
      return const SizedBox.shrink();
    }

    final icon = _getIcon(category!.shortName);
    if (icon == null) return const SizedBox.shrink();

    final color = _parseColor(category!.color);

    return Positioned(
      right: 4,
      bottom: 4,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color ?? Colors.grey.shade700,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }

  IconData? _getIcon(String shortName) {
    switch (shortName) {
      case '录入':
        return Icons.edit_note;
      case '翻译':
        return Icons.translate;
      case '转载':
        return Icons.reply;
      default:
        return null;
    }
  }

  Color? _parseColor(String colorStr) {
    if (colorStr.isEmpty) return null;
    try {
      // Handle hex color like "#FF5733" or "FF5733"
      String hex = colorStr.replaceFirst('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex'; // Add alpha
      }
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }
}
