import 'package:cloudflare_turnstile/src/turnstile_exception.dart';

/// Interface for the Turnstile Controller.
abstract class TurnstileController<T> {
  /// The connector associated with this controller.
  late T connector;

  /// Retrives the current token from the widget.
  ///
  /// Returns `null` if no token is available.
  String? get token;

  /// Retrives the current widget ID.
  ///
  /// This ID is used to uniquely identify the Turnstile widget instance.
  String? get widgetId;

  /// Retrieves the widget's ready state.
  ///
  /// Returns `true` if the widget is ready for interaction, otherwise `false`.
  bool get isWidgetReady;

  /// Retrieves the current error state of the Turnstile widget, if any.
  ///
  /// Returns a [TurnstileException] object if an error exists, otherwise `null`
  TurnstileException? get error;

  /// Sets a new connector.
  void setConnector(T newConnector);

  /// Sets a new token.
  ///
  /// Use this method to manually set or override the current token value.
  set token(String? token);

  /// Sets the Turnstile widget ID.
  ///
  /// This assigns a new ID to the current Turnstile widget instance.
  set widgetId(String? id);

  /// Sets the widget's ready state.
  ///
  /// Use this to indicate whether the widget is ready for interaction.
  set isWidgetReady(bool isReady);

  /// Sets the error state for the Turnstile widget.
  ///
  /// This method updates the error state of the widget, allowing it to
  /// reflect the current issue encountered.
  set error(TurnstileException? error);

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
  Future<void> refreshToken();

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
  Future<bool> isExpired();

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
  void onError(Function(TurnstileException error) callback);

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
  void onTokenReceived(Function(String token) callback);
}
