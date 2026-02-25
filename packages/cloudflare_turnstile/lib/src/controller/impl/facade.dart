// 忽略：作为 Facade 实现的一部分，这些参数是必要的。
// ignore_for_file: avoid_unused_constructor_parameters
// ignore: avoid_web_libraries_in_flutter
import 'package:cloudflare_turnstile/src/controller/interface.dart' as i;
import 'package:cloudflare_turnstile/src/turnstile_exception.dart';
import 'package:flutter/material.dart';

/// Facade class
class TurnstileController extends ChangeNotifier
    implements i.TurnstileController<dynamic> {
  /// The connector associated with this controller.
  @override
  late dynamic connector;

  /// Retrives the current token from the widget.
  ///
  /// Returns `null` if no token is available.
  @override
  String? get token {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Sets a new connector.
  @override
  void setConnector(dynamic newConnector) {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Sets a new token.
  ///
  /// Use this method to manually set or override the current token value.
  @override
  set token(String? token) {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Sets the error state for the Turnstile widget.
  ///
  /// This method updates the error state of the widget, allowing it to
  /// reflect the current issue encountered.
  @override
  set error(TurnstileException? error) {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Retrives the current widget ID.
  ///
  /// This ID is used to uniquely identify the Turnstile widget instance.
  @override
  String get widgetId {
    throw UnimplementedError('Cannot call this function on the facade');
  }

  /// Retrieves the widget's ready state.
  ///
  /// Returns `true` if the widget is ready for interaction, otherwise `false`.
  @override
  bool get isWidgetReady {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Sets the widget's ready state.
  ///
  /// Use this to indicate whether the widget is ready for interaction.
  @override
  set isWidgetReady(bool isReady) {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Sets the Turnstile widget ID.
  ///
  /// This assigns a new ID to the current Turnstile widget instance.
  @override
  set widgetId(String? id) {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

  /// Retrieves the current error state of the Turnstile widget, if any.
  ///
  /// Returns a [TurnstileException] object if an error exists, otherwise `null`
  @override
  TurnstileException? get error {
    throw UnimplementedError('Cannot call this function on the facade.');
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
    throw UnimplementedError('Cannot call this function on the facade.');
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
  Future<bool> isExpired() {
    throw UnimplementedError('Cannot call this function on the facade.');
  }

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
  void onError(Function(TurnstileException error) callback) {}

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
    throw UnimplementedError('Cannot call this function on the facade.');
  }
}
