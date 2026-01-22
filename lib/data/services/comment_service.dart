import 'package:logging/logging.dart';
import 'package:novella/core/network/signalr_service.dart';
import 'package:novella/data/models/comment.dart';
import 'package:novella/features/book/book_detail_page.dart';

class CommentService {
  static final Logger _logger = Logger('CommentService');
  final SignalRService _signalRService = SignalRService();

  /// 获取评论列表并组装数据
  Future<CommentPageData> getComments({
    required CommentType type,
    required int id,
    int page = 1,
  }) async {
    try {
      final result = await _signalRService.invoke<Map<dynamic, dynamic>>(
        'GetComments',
        args: [
          {'Type': type.value, 'Id': id, 'Page': page},
          {'UseGzip': true},
        ],
      );

      // 解析基础字段
      final int totalPages = result['TotalPages'] as int? ?? 0;
      final int currentPage = result['Page'] as int? ?? 1;

      // 原始字典数据
      final usersMap = result['Users'] as Map<dynamic, dynamic>? ?? {};
      final commentariesMap =
          result['Commentaries'] as Map<dynamic, dynamic>? ?? {};
      final dataList = result['Data'] as List<dynamic>? ?? [];

      // 辅助函数：从 Users 字典构建 UserInfo
      UserInfo? getUser(int userId) {
        final userData = usersMap[userId.toString()] ?? usersMap[userId];
        if (userData != null) {
          return UserInfo.fromJson(userData);
        }
        return null;
      }

      // 辅助函数：从 Commentaries 字典获取内容
      Map<dynamic, dynamic>? getCommentary(int commentId) {
        return commentariesMap[commentId.toString()] ??
            commentariesMap[commentId];
      }

      // 组装结果列表
      final List<CommentItem> items = [];

      for (final rootNode in dataList) {
        final rootId = rootNode['Id'] as int;
        final replyIds = (rootNode['Reply'] as List?)?.cast<int>() ?? [];

        final rootData = getCommentary(rootId);
        if (rootData == null) continue;

        final rootUserId = rootData['UserId'] as int;
        final rootUser = getUser(rootUserId);
        if (rootUser == null) continue;

        // 构建楼中楼回复
        final List<CommentReplyItem> replies = [];
        for (final replyId in replyIds) {
          final replyData = getCommentary(replyId);
          if (replyData == null) continue;

          final replyUserId = replyData['UserId'] as int;
          final replyUser = getUser(replyUserId);
          if (replyUser == null) continue;

          // 处理 "回复某人" 逻辑
          // 如果该回复有 ReplyId 指向父级评论下的某条评论，则找到那个被回复的人
          UserInfo? replyToUser;
          final targetReplyId = replyData['ReplyId'] as int?;
          if (targetReplyId != null) {
            final targetData = getCommentary(targetReplyId);
            if (targetData != null) {
              final targetUserId = targetData['UserId'] as int;
              replyToUser = getUser(targetUserId);
            }
          }

          replies.add(
            CommentReplyItem(
              id: replyId,
              user: replyUser,
              content: replyData['Content'] as String? ?? '',
              createdAt:
                  DateTime.tryParse(replyData['CreatedAt']?.toString() ?? '') ??
                  DateTime.now(),
              canEdit: replyData['CanEdit'] as bool? ?? false,
              replyToUser: replyToUser,
            ),
          );
        }

        items.add(
          CommentItem(
            id: rootId,
            user: rootUser,
            content: rootData['Content'] as String? ?? '',
            createdAt:
                DateTime.tryParse(rootData['CreatedAt']?.toString() ?? '') ??
                DateTime.now(),
            canEdit: rootData['CanEdit'] as bool? ?? false,
            replies: replies,
          ),
        );
      }

      return CommentPageData(
        totalPages: totalPages,
        currentPage: currentPage,
        items: items,
      );
    } catch (e) {
      _logger.severe('Failed to get comments: $e');
      rethrow;
    }
  }

  /// 发表评论
  Future<void> postComment(PostCommentRequest req) async {
    try {
      await _signalRService.invoke(
        'PostComment',
        args: [
          req.toJson(),
          {'UseGzip': true},
        ],
      );
    } catch (e) {
      _logger.severe('Failed to post comment: $e');
      rethrow;
    }
  }

  /// 回复评论
  Future<void> replyComment(PostCommentRequest req) async {
    try {
      await _signalRService.invoke(
        'ReplyComment',
        args: [
          req.toJson(),
          {'UseGzip': true},
        ],
      );
    } catch (e) {
      _logger.severe('Failed to reply comment: $e');
      rethrow;
    }
  }

  /// 删除评论
  Future<void> deleteComment(int id) async {
    try {
      await _signalRService.invoke(
        'DeleteComment',
        args: [
          {'Id': id},
          {'UseGzip': true},
        ],
      );
    } catch (e) {
      _logger.severe('Failed to delete comment: $e');
      rethrow;
    }
  }
}
