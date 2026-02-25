import 'package:cloudflare_turnstile/src/controller/interface.dart';
import 'package:cloudflare_turnstile/src/turnstile_exception.dart';
import 'package:cloudflare_turnstile/src/widget/turnstile_options.dart';

/// Callback invoked upon successful token reception.
///
/// The callback receives a [token] that can be validated.
typedef OnTokenReceived = Function(String token);

/// Callback invoked when the token expires.
///
/// The callback does not reset the widget.
typedef OnTokenExpired = void Function();

/// Callback invoked when an error occurs.
///
/// The callback receives a [TurnstileException] object, [error], which provides
/// details about the error, such as network issues or a challenge failure.
///
/// The [OnError] callback is used to build a custom error widget.
/// This widget will only be displayed if the TurnstileException's `retryable`
/// property is set to `true`. For non-retriable errors, this callback may still
/// be invoked, but the display or handling of these errors might be managed
/// internally by the Turnstile widget or handled differently.
typedef OnError = Function(TurnstileException error);

/// Callback invoked when the Turnstile widget fails to load within a timeout.
///
/// This can be used to trigger a fallback flow (e.g., enable an alternative
/// verification method) if Cloudflare's script is unavailable or delayed.
typedef OnTimeout = void Function();

/// Abstract class representing a Cloudflare Turnstile widget.
abstract class CloudflareTurnstile {
  /// The [siteKey] is required and associates this widget with a
  /// Cloudflare Turnstile instance.
  /// Additional parameters like [action], [cData], [controller], and
  /// various options customize the widget's behavior.
  CloudflareTurnstile({
    required this.siteKey,
    this.action,
    this.cData,
    this.baseUrl = 'http://localhost/',
    TurnstileOptions? options,
    this.controller,
    this.onTokenReceived,
    this.onTokenExpired,
    this.onError,
    this.onTimeout,
  }) : options = options ?? TurnstileOptions();

  /// This [siteKey] is associated with the corresponding widget configuration
  /// and is created upon the widget creation.
  ///
  /// It`s likely generated or obtained from the CloudFlare dashboard.
  final String siteKey;

  /// A customer value that can be used to differentiate widgets under the
  /// same sitekey in analytics and which is returned upon validation.
  ///
  /// This can only contain up to 32 alphanumeric characters including _ and -.
  final String? action;

  /// A customer payload that can be used to attach customer data to the
  /// challenge throughout its issuance and which is returned upon validation.
  ///
  /// This can only contain up to 255 alphanumeric characters including _ and -.
  final String? cData;

  /// The base URL of the Turnstile site.
  ///
  /// Defaults to 'http://localhost/'.
  final String baseUrl;

  /// Configuration options for the Turnstile widget.
  ///
  /// If no options are provided, the default [TurnstileOptions] are used.
  final TurnstileOptions? options;

  /// A controller for managing interactions with the Turnstile widget.
  final TurnstileController<dynamic>? controller;

  /// A Callback invoked upon success of the challange.
  /// The callback is passed a `token` that can be validated.
  ///
  /// example:
  /// ```dart
  /// CloudflareTurnstile(
  ///   siteKey: '3x00000000000000000000FF',
  ///   onTokenReceived: (String token) {
  ///     print('Token: $token');
  ///   },
  /// ),
  /// ```
  final OnTokenReceived? onTokenReceived;

  /// A Callback invoke when the token expires and does not
  /// reset the widget.
  ///
  /// example:
  /// ```dart
  /// CloudflareTurnstile(
  ///   siteKey: '3x00000000000000000000FF',
  ///   onTokenExpired: () {
  ///     print('Token Expired');
  ///   },
  /// ),
  /// ```
  final OnTokenExpired? onTokenExpired;

  /// A Callback invoke when there is an error
  /// (e.g network error or challange failed).
  ///
  /// This widget will only be displayed if the TurnstileException's `retryable`
  /// property is set to `true`. For non-retriable errors, this callback
  /// may still be invoked, but the display or handling of these errors
  /// might be managed internally by the Turnstile widget or handled
  /// differently.
  ///
  /// example:
  /// ```dart
  /// CloudflareTurnstile(
  ///   siteKey: '3x00000000000000000000FF',
  ///   onError: (error) {
  ///     print(error.message);
  ///   },
  /// ),
  /// ```
  ///
  /// Refer to [Client-side errors](https://developers.cloudflare.com/turnstile/troubleshooting/client-side-errors/).
  final OnError? onError;

  /// Callback invoked when the Turnstile widget fails to load in time.
  ///
  /// This is typically triggered if the Turnstile script cannot be loaded
  /// due to a network issue or Cloudflare outage, allowing consumers to
  /// handle a fallback flow.
  final OnTimeout? onTimeout;

  /// Retrives the current token from the widget.
  ///
  /// Returns `null` if no token is available.
  String? get token;

  /// Retrives the current widget id.
  ///
  /// This `id` is used to uniquely identify the Turnstile widget instance.
  String? get id;

  /// The function can be called when widget mey become expired and
  /// needs to be refreshed otherwise, it will start a new challenge.
  ///
  /// This method can only be called when [id] is not null.
  ///
  ///
  /// example:
  /// ```dart
  /// // Initialize turnstile instance
  /// final turnstile = CloudflareTurnstile.invisible(
  ///   siteKey: '1x00000000000000000000BB', // Replace with your actual site key
  /// );
  ///
  /// await turnstile.isExpired();
  ///
  /// // finally clean up widget.
  /// await turnstile.dispose();
  /// ```
  Future<void> refresh({bool forceRefresh = true});

  /// This function starts a Cloudflare Turnstile challenge and returns token
  /// or `null` if challenge failed or error occured.
  ///
  /// example:
  /// ```dart
  /// // Initialize turnstile instance
  /// final turnstile = CloudflareTurnstile.invisible(
  ///   siteKey: '1x00000000000000000000BB', // Replace with your actual site key
  /// );
  ///
  /// final token = await turnstile.getToken();
  ///
  /// print(token);
  ///
  /// // finally clean up widget.
  /// await turnstile.dispose();
  /// ```
  Future<String?> getToken();

  /// The function that check if a widget has expired.
  ///
  /// This method can only be called when [id] is not null.
  ///
  ///
  /// example:
  /// ```dart
  /// // Initialize turnstile instance
  /// final turnstile = CloudflareTurnstile.invisible(
  ///   siteKey: '1x00000000000000000000BB', // Replace with your actual site key
  /// );
  ///
  /// // ...
  ///
  /// bool isTokenExpired = await turnstile.isExpired();
  /// print(isTokenExpired);
  ///
  /// // finally clean up widget.
  /// await turnstile.dispose();
  /// ```
  Future<bool> isExpired();

  /// Dispose invisible Turnstile widget.
  ///
  ///
  /// This should be called when the widget is no longer needed to free
  /// up resources and clean up.
  Future<void> dispose();
}
