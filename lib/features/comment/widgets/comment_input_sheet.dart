import 'package:flutter/material.dart';

class CommentInputSheet extends StatefulWidget {
  final String hintText;
  final Function(String content) onSubmit;

  const CommentInputSheet({
    super.key,
    required this.hintText,
    required this.onSubmit,
  });

  @override
  State<CommentInputSheet> createState() => _CommentInputSheetState();
}

class _CommentInputSheetState extends State<CommentInputSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _canSubmit = _controller.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    widget.onSubmit(_controller.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 获取底部键盘高度 + 安全区域
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      decoration: BoxDecoration(
        color: theme.dialogBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('发送'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
