// 忽略：作为 Web 平台实现，必须访问 web 库。
// ignore: avoid_web_libraries_in_flutter

import 'dart:js_interop' show JS;

import 'package:cloudflare_turnstile/src/controller/interface.dart' as i;
import 'package:cloudflare_turnstile/src/turnstile_exception.dart';
import 'package:flutter/material.dart';

@JS('turnstile.isExpired')
external bool _isTokenExpired([String? widgetId]);

@JS('turnstile.reset')
external void _resetWidget([String? widgetId]);

/// Turnstile controller web implementation.
class TurnstileController extends ChangeNotifier
    implements i.TurnstileController<dynamic> {
  /// The connector associated with the controller.
  @override
  late dynamic connector;

  String? _token;

  TurnstileException? _error;

  String? _widgetId = '';

  bool _isReady = false;

  /// Retrives the current token from the widget.
  ///
  /// Returns `null` if no token is available.
  @override
  String? get token => _token;

  /// Retrives the current widget ID.
  ///
  /// This ID is used to uniquely identify the Turnstile widget instance.
  @override
  String? get widgetId => _widgetId;

  /// Retrieves the widget's ready state.
  ///
  /// Returns `true` if the widget is ready for interaction, otherwise `false`.
  @override
  bool get isWidgetReady => _isReady;

  /// Retrieves the current error state of the Turnstile widget, if any.
  ///
  /// Returns a [TurnstileException] object if an error exists, otherwise `null`
  @override
  TurnstileException? get error => _error;

  /// Sets a new connector.
  @override
  void setConnector(dynamic newConnector) {}

  /// Sets a new token.
  ///
  /// Use this method to manually set or override the current token value.
  @override
  set token(String? token) {
    _token = token;

    if (token != null && token.isNotEmpty) {
      _onTokenReceived?.call(token);
    }

    notifyListeners();
  }

  /// Sets the Turnstile widget ID.
  ///
  /// This assigns a new ID to the current Turnstile widget instance.
  @override
  set widgetId(String? id) {
    if (_widgetId != id) {
      _widgetId = id;
      notifyListeners();
    }
  }

  /// Sets the widget's ready state.
  ///
  /// Use this to indicate whether the widget is ready for interaction.
  @override
  set isWidgetReady(bool isReady) {
    if (_isReady != isReady) {
      _isReady = isReady;
      notifyListeners();
    }
  }

  /// Sets the error state for the Turnstile widget.
  ///
  /// This method updates the error state of the widget, allowing it to
  /// reflect the current issue encountered.
  @override
  set error(TurnstileException? error) {
    _error = error;
    if (error != null) {
      _onError?.call(error);
    }
    notifyListeners();
  }

  /// The function can be called when widget mey become expired and
  /// needs to be refreshed.
  ///
  /// This method can only be called when [widgetId] is not null.
  ///
  /// example:
  /// ```dart
  /// // Initialize controller
  /// TurnstileController controller = TurnstileController();
  ///
  /// await controller.refreshToken();
  /// ```
  @override
  Future<void> refreshToken() async {
    _resetWidget(_widgetId);
    _token = null;
  }

  /// The function that check if a widget has expired.
  ///
  /// This method can only be called when [widgetId] is not null.
  ///
  ///
  /// example:
  /// ```dart
  /// // Initialize controller
  /// TurnstileController controller = TurnstileController();
  ///
  /// bool isTokenExpired = await controller.isExpired();
  /// print(isTokenExpired);
  /// ```
  @override
  Future<bool> isExpired() async {
    if (!_isReady || _widgetId == null || token == null || token!.isEmpty) {
      return true;
    }

    final expired = _isTokenExpired(_widgetId);
    return Future.value(expired);
  }

  /// dispose resources
  @override
  void dispose() {
    super.dispose();
  }

  Function(TurnstileException error)? _onError;
  Function(String token)? _onTokenReceived;

  /// Registers a callback to be invoked when an error occurs.
  ///
  /// The [callback] function is invoked whenever an error arises in processes
  /// like token fetching or widget initialization. This is essential for
  /// handling issues such as network failures or invalid tokens.
  ///
  /// This method helps in capturing and responding errors.
  ///
  /// example:
  /// ```dart
  /// // Initialize controller
  /// TurnstileController controller = TurnstileController();
  ///
  /// controller.onError((error) {
  ///   print('Error: $error');
  /// });
  /// ```
  @override
  void onError(Function(TurnstileException error) callback) {
    _onError = callback;
  }

  /// Registers a callback to be invoked when a new `token` is
  /// successfully received.
  ///
  /// Use this method to track when new tokens are generated.
  ///
  /// example:
  /// ```dart
  /// TurnstileController controller = TurnstileController();
  ///
  /// controller.onTokenReceived((token) {
  ///   print('New token: $token');
  /// });
  /// ```
  @override
  void onTokenReceived(Function(String token) callback) {
    _onTokenReceived = callback;
  }
}
