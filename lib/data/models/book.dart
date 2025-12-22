/// Book category information from API
class BookCategory {
  final String shortName; // "录入" / "翻译" / "转载"
  final String name; // "录入完成" / "翻译中" etc.
  final String color; // Hex color from server

  const BookCategory({
    required this.shortName,
    required this.name,
    required this.color,
  });

  factory BookCategory.fromJson(Map<dynamic, dynamic> json) {
    return BookCategory(
      shortName: json['ShortName'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      color: json['Color'] as String? ?? '',
    );
  }
}

class Book {
  final int id;
  final String title;
  final String cover;
  final String author;
  final DateTime lastUpdatedAt;
  final String? userName;
  final int? level;
  final BookCategory? category;

  Book({
    required this.id,
    required this.title,
    required this.cover,
    required this.author,
    required this.lastUpdatedAt,
    this.userName,
    this.level,
    this.category,
  });

  factory Book.fromJson(Map<dynamic, dynamic> json) {
    // Helper to handle Key case sensitivity if needed, but SignalR MsgPack usually preserves exact keys.
    // 'LastUpdatedAt' from Typescript ref says it might lose Date object and become string?
    // Let's handle both.

    DateTime parseDate(dynamic date) {
      if (date is String) {
        return DateTime.tryParse(date) ?? DateTime.now();
      }
      return DateTime.now();
    }

    // Parse category if present
    BookCategory? category;
    if (json['Category'] is Map) {
      category = BookCategory.fromJson(json['Category']);
    }

    return Book(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? 'Unknown',
      cover: json['Cover'] as String? ?? '',
      author:
          json['Author'] as String? ??
          'Unknown', // Sometimes in 'User' object or root? BookInList has it.
      lastUpdatedAt: parseDate(json['LastUpdatedAt']),
      userName: json['UserName'] as String?,
      level: json['Level'] as int?,
      category: category,
    );
  }
}

class Chapter {
  final int id;
  final String title;

  Chapter({required this.id, required this.title});

  factory Chapter.fromJson(Map<dynamic, dynamic> json) {
    return Chapter(
      id: json['Id'] as int? ?? 0,
      title: json['Title'] as String? ?? '',
    );
  }
}

enum ShelfItemType { book, folder }

class ShelfItem {
  final dynamic id; // int for books, String for folders
  final ShelfItemType type;
  final String title;
  final List<String> parents;
  final int index;
  final DateTime updatedAt;

  ShelfItem({
    required this.id,
    required this.type,
    this.title = '',
    this.parents = const [],
    this.index = 0,
    required this.updatedAt,
  });

  factory ShelfItem.fromJson(Map<dynamic, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'BOOK';
    final type =
        typeStr == 'FOLDER' ? ShelfItemType.folder : ShelfItemType.book;

    return ShelfItem(
      id: json['id'], // dynamic
      type: type,
      title: json['title'] as String? ?? '',
      parents:
          (json['parents'] as List?)?.map((e) => e.toString()).toList() ?? [],
      index: json['index'] as int? ?? 0,
      updatedAt:
          DateTime.tryParse(json['updateAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == ShelfItemType.folder ? 'FOLDER' : 'BOOK',
      'title': title,
      'parents': parents,
      'index': index,
      'updateAt': updatedAt.toIso8601String(),
    };
  }
}
