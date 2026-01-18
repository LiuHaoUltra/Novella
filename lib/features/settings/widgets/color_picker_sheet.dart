import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class BottomColorPickerSheet extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onPreviewChange;

  const BottomColorPickerSheet({
    super.key,
    required this.initialColor,
    required this.onPreviewChange,
  });

  @override
  State<BottomColorPickerSheet> createState() => _BottomColorPickerSheetState();
}

class _BottomColorPickerSheetState extends State<BottomColorPickerSheet> {
  late Color _pickerColor;
  late TextEditingController _hexController;
  final _focusNode = FocusNode();
  String? _errorText;

  // 跟踪指针交互状态
  bool _isTrackingPointer = false;
  bool _hasPointerMoved = false;

  @override
  void initState() {
    super.initState();
    _pickerColor = widget.initialColor;
    _hexController = TextEditingController(
      text:
          '#${_pickerColor.toARGB32().toRadixString(16).toUpperCase().substring(2)}',
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onColorChanged(Color color) {
    setState(() {
      _pickerColor = color;
    });

    // 仅在未获焦点时更新文本，避免干扰用户输入
    if (!_focusNode.hasFocus) {
      final hex = color.toARGB32().toRadixString(16).toUpperCase().substring(2);
      _hexController.text = '#$hex';
      _errorText = null; // 有效颜色更改清除错误
    }

    // 如果未跟踪指针（例如松手后的点击事件），即便没有拖动也立即更新预览。
    // 这捕获了色轮上的单击操作。
    if (!_isTrackingPointer) {
      widget.onPreviewChange(color);
    }
  }

  void _onHexChanged(String value) {
    if (value.isEmpty) return;

    // 移除可能存在的 #
    String hex = value.replaceAll('#', '');
    if (hex.length == 6) {
      // 验证十六进制
      final validHex = RegExp(r'^[0-9a-fA-F]{6}$');
      if (validHex.hasMatch(hex)) {
        try {
          final color = Color(int.parse('FF$hex', radix: 16));
          setState(() {
            _pickerColor = color;
            _errorText = null;
          });
          // 立即更新文本输入的预览
          widget.onPreviewChange(color);
        } catch (e) {
          // 正则应已过滤，保险起见
        }
      } else {
        setState(() {
          _errorText = '格式错误';
        });
      }
    } else if (hex.length > 6) {
      setState(() {
        _errorText = '格式错误';
      });
    } else {
      // 输入中... 清除错误或保持最小干扰
      if (_errorText != null) {
        setState(() {
          _errorText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自定义颜色',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 包裹在 Listener 中的颜色选择器，用于拖动结束检测
            Listener(
              onPointerDown: (_) {
                _isTrackingPointer = true;
                _hasPointerMoved = false;
              },
              onPointerMove: (_) {
                _hasPointerMoved = true;
              },
              onPointerUp: (_) {
                _isTrackingPointer = false;

                // 拖动结束 -> 更新预览
                // 仅当移动过（拖动）时更新。如果未移动（单击），交由 onColorChanged 处理。
                if (_hasPointerMoved) {
                  widget.onPreviewChange(_pickerColor);

                  // 如果需要，也更新文本控制器
                  if (!_focusNode.hasFocus) {
                    final hex = _pickerColor
                        .toARGB32()
                        .toRadixString(16)
                        .toUpperCase()
                        .substring(2);
                    _hexController.text = '#$hex';
                  }
                }
              },
              child: ColorPicker(
                pickerColor: _pickerColor,
                onColorChanged: _onColorChanged,
                colorPickerWidth: 300,
                pickerAreaHeightPercent: 0.7,
                enableAlpha: false,
                displayThumbColor: true,
                hexInputBar: false, // 禁用自带输入栏
                paletteType: PaletteType.hsvWithHue,
                labelTypes: const [],
              ),
            ),

            const SizedBox(height: 24),

            // Custom Hex Input
            TextField(
              controller: _hexController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'HEX 颜色代码',
                hintText: '#RRGGBB',
                errorText: _errorText,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tag, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(7), // # + 6 位字符
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              ],
              onChanged: _onHexChanged,
              onSubmitted: (value) {
                // 提交时进行最终检查
                _onHexChanged(value);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
