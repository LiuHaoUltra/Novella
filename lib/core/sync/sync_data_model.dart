import 'dart:convert';

/// 同步数据顶层结构
class SyncData {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String appVersion;
  final DateTime syncedAt;
  final String? syncId; // 逻辑版本号，用于辅助冲突检测
  final Map<String, SyncModule> modules;

  SyncData({
    required this.schemaVersion,
    required this.appVersion,
    required this.syncedAt,
    this.syncId,
    required this.modules,
  });

  factory SyncData.create({
    required String appVersion,
    required Map<String, SyncModule> modules,
  }) {
    return SyncData(
      schemaVersion: currentSchemaVersion,
      appVersion: appVersion,
      syncedAt: DateTime.now(),
      syncId: DateTime.now().millisecondsSinceEpoch.toString(), // 简单作为版本标识
      modules: modules,
    );
  }

  factory SyncData.fromJson(Map<String, dynamic> json) {
    final modulesJson = json['modules'] as Map<String, dynamic>? ?? {};
    final modules = <String, SyncModule>{};

    for (final entry in modulesJson.entries) {
      modules[entry.key] = SyncModule.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return SyncData(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      appVersion: json['appVersion'] as String? ?? 'unknown',
      syncedAt:
          DateTime.tryParse(json['syncedAt'] as String? ?? '') ??
          DateTime.now(),
      syncId: json['syncId'] as String?,
      modules: modules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'syncedAt': syncedAt.toIso8601String(),
      'syncId': syncId,
      'modules': modules.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  /// 合并远程数据 (按时间戳)
  SyncData mergeWith(SyncData remote) {
    final mergedModules = <String, SyncModule>{};

    // 合并所有模块
    final allKeys = {...modules.keys, ...remote.modules.keys};
    for (final key in allKeys) {
      final local = modules[key];
      final remoteModule = remote.modules[key];

      if (local == null) {
        mergedModules[key] = remoteModule!;
      } else if (remoteModule == null) {
        mergedModules[key] = local;
      } else {
        // 按时间戳合并，传递模块名以启用细粒度策略
        mergedModules[key] = local.mergeWith(remoteModule, moduleName: key);
      }
    }

    return SyncData(
      schemaVersion: currentSchemaVersion,
      appVersion: appVersion,
      syncedAt: DateTime.now(),
      syncId: DateTime.now().millisecondsSinceEpoch.toString(),
      modules: mergedModules,
    );
  }
}

/// 单个模块数据
class SyncModule {
  final int version;
  final DateTime updatedAt;
  final Map<String, dynamic> data;

  SyncModule({
    required this.version,
    required this.updatedAt,
    required this.data,
  });

  factory SyncModule.fromJson(Map<String, dynamic> json) {
    return SyncModule(
      version: json['version'] as int? ?? 1,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'updatedAt': updatedAt.toIso8601String(),
      'data': data,
    };
  }

  /// 合并模块数据（细粒度策略）
  /// - bookmarks：按条目的 updatedAt 合并
  /// - readingTime：取每日最大值
  /// - 其他：整体取最新
  SyncModule mergeWith(SyncModule remote, {String? moduleName}) {
    // 需要按条目合并的模块
    final entryMergeModules = {SyncModuleNames.bookmarks};

    // 阅读时长特殊处理：取每日最大值
    if (moduleName == SyncModuleNames.readingTime) {
      return _mergeReadingTime(remote);
    }

    // bookmarks：按条目合并
    if (moduleName != null && entryMergeModules.contains(moduleName)) {
      return _mergeByEntry(remote);
    }

    // 其他模块：整体取最新
    if (remote.updatedAt.isAfter(updatedAt)) {
      return remote;
    }
    return this;
  }

  /// 按条目合并（适用于 bookmarks）
  SyncModule _mergeByEntry(SyncModule remote) {
    final mergedData = <String, dynamic>{};
    final allKeys = {...data.keys, ...remote.data.keys};

    for (final key in allKeys) {
      final localEntry = data[key];
      final remoteEntry = remote.data[key];

      if (localEntry == null) {
        mergedData[key] = remoteEntry;
      } else if (remoteEntry == null) {
        mergedData[key] = localEntry;
      } else {
        // 两边都有，按 updatedAt 选择
        final localTime = _parseEntryTime(localEntry);
        final remoteTime = _parseEntryTime(remoteEntry);
        mergedData[key] =
            remoteTime.isAfter(localTime) ? remoteEntry : localEntry;
      }
    }

    return SyncModule(
      version: version,
      updatedAt: DateTime.now(),
      data: mergedData,
    );
  }

  /// 合并阅读时长（取每日最大值）
  SyncModule _mergeReadingTime(SyncModule remote) {
    final mergedData = <String, dynamic>{};
    final allKeys = {...data.keys, ...remote.data.keys};

    for (final key in allKeys) {
      final localMinutes = data[key] as int? ?? 0;
      final remoteMinutes = remote.data[key] as int? ?? 0;
      // 取最大值（同一天可能在多设备阅读）
      mergedData[key] =
          localMinutes > remoteMinutes ? localMinutes : remoteMinutes;
    }

    return SyncModule(
      version: version,
      updatedAt: DateTime.now(),
      data: mergedData,
    );
  }

  /// 解析条目的 updatedAt 时间
  DateTime _parseEntryTime(dynamic entry) {
    if (entry is Map<String, dynamic>) {
      final timeStr = entry['updatedAt'] as String?;
      if (timeStr != null) {
        return DateTime.tryParse(timeStr) ?? DateTime(2000);
      }
    }
    return DateTime(2000); // 默认很早的时间
  }
}

/// 模块名称常量
class SyncModuleNames {
  static const String bookmarks = 'bookmarks';
  static const String readingTime = 'readingTime';
  static const String settings = 'settings';
  static const String auth = 'auth';
}

/// 书签条目 (用于详细合并)
class BookmarkEntry {
  final int status;
  final DateTime updatedAt;

  BookmarkEntry({required this.status, required this.updatedAt});

  factory BookmarkEntry.fromJson(Map<String, dynamic> json) {
    return BookmarkEntry(
      status: json['status'] as int? ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
