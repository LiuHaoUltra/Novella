import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:novella/core/utils/time_utils.dart';
import 'package:novella/data/models/comment.dart';
import 'package:novella/features/book/book_detail_page.dart';

class CommentItemWidget extends StatelessWidget {
  final CommentItem item;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final Function(CommentReplyItem reply)? onReplyToReply;
  final Function(int replyId)? onDeleteReply;

  const CommentItemWidget({
    super.key,
    required this.item,
    this.onReply,
    this.onDelete,
    this.onReplyToReply,
    this.onDeleteReply,
  });

  @override
  Widget build(BuildContext context) {
    // 设置 timeago 语言为中文（需在 main 初始化，这里暂用默认）
    // timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主楼
        _buildMainComment(context, theme, colorScheme),

        // 楼中楼
        if (item.replies.isNotEmpty)
          Padding(
            // 整体缩进：头像宽度(40) + 间距(16) + 左边距(16) = 72
            // 调整为从文字对齐处开始绘制竖线
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                // 左侧竖线
                border: Border(
                  left: BorderSide(
                    color: colorScheme.outlineVariant, // 细微的分割线颜色
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.only(left: 12), // 竖线与内容的距离
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < item.replies.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _buildReplyItem(
                      context,
                      item.replies[i],
                      theme,
                      colorScheme,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 构建统一头像逻辑
  /// [radius] 头像半径
  /// [fontSize] 首字母字体大小
  Widget _buildAvatar(
    ColorScheme colorScheme,
    UserInfo user,
    double radius,
    double fontSize,
  ) {
    // 默认头像（首字母）
    final defaultAvatar = CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: Text(
        user.userName.isNotEmpty ? user.userName.substring(0, 1) : '?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize),
      ),
    );

    // 如果没有头像 URL，直接返回默认样式
    if (user.avatar.isEmpty) {
      return SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: defaultAvatar,
      );
    }

    // 有 URL 则尝试加载，加载中和失败都显示默认样式
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: CachedNetworkImage(
        imageUrl: user.avatar,
        memCacheWidth: 100, // 限制头像的解析内存，即使原图极大也会缩小到100宽解码
        imageBuilder:
            (context, provider) =>
                CircleAvatar(radius: radius, backgroundImage: provider),
        // 加载中显示首字母
        placeholder: (context, url) => defaultAvatar,
        // 加载失败显示首字母
        errorWidget: (context, url, err) => defaultAvatar,
      ),
    );
  }

  Widget _buildMainComment(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      // 增加垂直间距，提升呼吸感
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主头像
          _buildAvatar(colorScheme, item.user, 20, 16),
          const SizedBox(width: 16), // 增加头像与内容间距
          // 内容主体
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户名
                Text(
                  item.user.userName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // 内容
                Text(
                  item.content.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.3, // 稍微减小行高
                  ),
                ),
                const SizedBox(height: 4), // 减小间距
                // 底部操作栏
                Row(
                  children: [
                    Text(
                      TimeUtils.formatRelativeTime(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    // 回复按钮 (图标)
                    SizedBox(
                      height: 32,
                      width: 32,
                      child: IconButton(
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 18),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          foregroundColor: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: '回复',
                      ),
                    ),
                    // 删除按钮 (图标)
                    if (item.canEdit) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        width: 32,
                        child: IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            foregroundColor: colorScheme.error,
                          ),
                          tooltip: '删除',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(
    BuildContext context,
    CommentReplyItem reply,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 小头像
            _buildAvatar(colorScheme, reply.user, 12, 10),
            const SizedBox(width: 8),
            // 用户名 + 回复对象
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  children: [
                    TextSpan(
                      text: reply.user.userName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (reply.replyToUser != null) ...[
                      TextSpan(
                        text: ' 回复 ',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      TextSpan(
                        text: reply.replyToUser!.userName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 回复内容
        Text(reply.content, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        // 回复操作栏
        Row(
          children: [
            Text(
              TimeUtils.formatRelativeTime(reply.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 32,
              width: 32,
              child: IconButton(
                onPressed: () => onReplyToReply?.call(reply),
                icon: const Icon(Icons.reply_rounded, size: 16),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
                tooltip: '回复',
              ),
            ),
            if (reply.canEdit) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                width: 32,
                child: IconButton(
                  onPressed: () => onDeleteReply?.call(reply.id),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    foregroundColor: colorScheme.error,
                  ),
                  tooltip: '删除',
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
