import 'package:novella/features/book/book_detail_page.dart';

enum CommentType {
  booked,
  announcement;

  /// 这里做个转换匹配后端字符串
  /// Web端代码：Book = 'Book', Announcement = 'Announcement'
  String get value {
    switch (this) {
      case CommentType.booked:
        return 'Book';
      case CommentType.announcement:
        return 'Announcement';
    }
  }
}

/// 发送/回复评论请求
class PostCommentRequest {
  final CommentType type;
  final int id;
  final String content;
  final int? replyId;
  final int? parentId;

  PostCommentRequest({
    required this.type,
    required this.id,
    required this.content,
    this.replyId,
    this.parentId,
  });

  Map<String, dynamic> toJson() {
    return {
      'Type': type.value,
      'Id': id,
      'Content': content,
      if (replyId != null) 'ReplyId': replyId,
      if (parentId != null) 'ParentId': parentId,
    };
  }
}

/// UI 使用的聚合评论模型
/// 已经将 User 和 Content 聚合在一起，方便 UI 直接渲染
class CommentItem {
  final int id;
  final UserInfo user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;

  // 楼中楼回复
  final List<CommentReplyItem> replies;

  CommentItem({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    this.replies = const [],
  });
}

/// 楼中楼回复模型
class CommentReplyItem {
  final int id;
  final UserInfo user;
  final String content;
  final DateTime createdAt;
  final bool canEdit;

  // 回复对象（如果有）
  // 如果是回复楼主，通常 replyTo 为空或特定逻辑；如果是楼中楼互回，则有值
  final UserInfo? replyToUser;

  CommentReplyItem({
    required this.id,
    required this.user,
    required this.content,
    required this.createdAt,
    required this.canEdit,
    this.replyToUser,
  });
}

/// 分页数据包装
class CommentPageData {
  final int totalPages;
  final int currentPage;
  final List<CommentItem> items;

  CommentPageData({
    required this.totalPages,
    required this.currentPage,
    required this.items,
  });
}
