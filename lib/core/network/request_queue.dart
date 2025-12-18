import 'dart:async';
import 'dart:collection';

/// A singleton queue to manage API requests and enforce rate limiting.
///
/// Limits requests to 5 per 5 seconds to prevent account bans.
class RequestQueue {
  // Singleton instance
  static final RequestQueue _instance = RequestQueue._internal();

  factory RequestQueue() {
    return _instance;
  }

  RequestQueue._internal();

  // Rate limiting configuration
  static const int _maxRequests = 5;
  static const Duration _windowDuration = Duration(seconds: 5);

  // Queue of timestamps of recent requests
  final Queue<DateTime> _requestTimestamps = Queue<DateTime>();

  // Queue of pending requests
  final Queue<_PendingRequest> _pendingRequests = Queue<_PendingRequest>();

  // Lock to ensure sequential processing check
  bool _isProcessing = false;

  /// Enqueues a request execution.
  ///
  /// [bypassQueue] can be set to true for requests that should not be rate limited
  /// (e.g., CDN images, though usually those are handled by UI components directly).
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

  /// Processes the queue of pending requests.
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (_pendingRequests.isNotEmpty) {
        // Clean up old timestamps
        final now = DateTime.now();
        while (_requestTimestamps.isNotEmpty &&
            now.difference(_requestTimestamps.first) > _windowDuration) {
          _requestTimestamps.removeFirst();
        }

        // Check if we can send a request
        if (_requestTimestamps.length < _maxRequests) {
          final pending = _pendingRequests.removeFirst();

          // Record timestamp BEFORE execution to be conservative
          _requestTimestamps.add(DateTime.now());

          // Execute request
          // We don't await the result here to block the queue processing loop
          // (concurrent requests allowed within limit), but since we are
          // enforcing a strict limit, we can just launch it.
          // However, the PRD says "Max 5 requests per 5 seconds".
          // It doesn't strictly say "Serial execution", but "Global Request Queue" suggests serialization might be desired or just rate limiting.
          // "If limit reached, strictly await and block subsequent requests."
          // So we only block if limit is reached.

          _executeRequest(pending);
        } else {
          // Limit reached, calculate time to wait
          if (_requestTimestamps.isNotEmpty) {
            final firstRequestTime = _requestTimestamps.first;
            final waitDuration =
                _windowDuration - now.difference(firstRequestTime);
            if (waitDuration > Duration.zero) {
              await Future.delayed(waitDuration);
            }
          } else {
            // Should not happen if length >= max, but safe fallback
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
