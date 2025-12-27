/*
 * This request queue architecture is inspired by the lightnovelshelf/web project.
 * Original Repository: https://github.com/LightNovelShelf/Web
 * Original License: AGPL-3.0
 * * Reference: src/services/internal/request/createRequestQueue.ts
 * Implements client-side rate limiting to match server expectations.
 */

import 'dart:async';
import 'dart:collection';

/// 单例请求队列，管理速率限制
/// 限制 5秒内 5个请求，防止封号
class RequestQueue {
  // 单例实例
  static final RequestQueue _instance = RequestQueue._internal();

  factory RequestQueue() {
    return _instance;
  }

  RequestQueue._internal();

  // 速率限制配置
  static const int _maxRequests = 5;
  static const Duration _windowDuration = Duration(seconds: 5);

  // 最近请求时间戳队列
  final Queue<DateTime> _requestTimestamps = Queue<DateTime>();

  // 待处理请求队列
  final Queue<_PendingRequest> _pendingRequests = Queue<_PendingRequest>();

  // 顺序处理锁
  bool _isProcessing = false;

  /// 请求入队
  /// [bypassQueue] 为 true 时跳过速率限制（如 CDN 图片）
  Future<T> enqueue<T>(
    Future<T> Function() request, {
    bool bypassQueue = false,
  }) async {
    if (bypassQueue) {
      return await request();
    }

    final completer = Completer<T>();
    _pendingRequests.add(_PendingRequest<T>(request, completer));
    _processQueue();
    return completer.future;
  }

  /// 处理队列中的待处理请求
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (_pendingRequests.isNotEmpty) {
        // 清理过期时间戳
        final now = DateTime.now();
        while (_requestTimestamps.isNotEmpty &&
            now.difference(_requestTimestamps.first) > _windowDuration) {
          _requestTimestamps.removeFirst();
        }

        // 检查是否可发送请求
        if (_requestTimestamps.length < _maxRequests) {
          final pending = _pendingRequests.removeFirst();

          // 执行前记录时间戳（保守策略）
          _requestTimestamps.add(DateTime.now());

          // 执行请求
          // 此处不等待结果，允许并发但受限于速率限制
          // 仅在达到限制时阻塞

          _executeRequest(pending);
        } else {
          // 达到限制，计算等待时间
          if (_requestTimestamps.isNotEmpty) {
            final firstRequestTime = _requestTimestamps.first;
            final waitDuration =
                _windowDuration - now.difference(firstRequestTime);
            if (waitDuration > Duration.zero) {
              await Future.delayed(waitDuration);
            }
          } else {
            // 安全回退逻辑
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _executeRequest(_PendingRequest pending) async {
    try {
      final result = await pending.request();
      pending.completer.complete(result);
    } catch (e, stack) {
      pending.completer.completeError(e, stack);
    }
  }
}

class _PendingRequest<T> {
  final Future<T> Function() request;
  final Completer<T> completer;

  _PendingRequest(this.request, this.completer);
}
