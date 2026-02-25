// 忽略：需要定义常量标识符，这是 Turnstile 异常处理逻辑的一部分。
// ignore_for_file: constant_identifier_names, public_member_api_docs

/// An exception class representing various errors that can occur
/// during the Turnstile challenge process.
///
/// This exception is used to provide detailed information about errors
/// encountered while interacting with Cloudflare's Turnstile, such as
/// invalid parameters, network issues, or internal problems.
///
/// Example usage:
/// ```dart
/// try {
///   // Some Turnstile logic
/// } catch (e) {
///   if (e is TurnstileException) {
///     print(e.message);  // Display the error message
///   }
/// }
/// ```
class TurnstileException implements Exception {
  /// Creates a [TurnstileException].
  ///
  /// If no [code] is provided, the default value is `-1`.
  /// If no [errorType] is provided, the default is [TurnstileError.UNKNOWN].
  /// If no [retryable] is provided, the default is `false`.
  const TurnstileException(
    this.message, {
    this.code = -1,
    this.errorType = TurnstileError.UNKNOWN,
    this.retryable = false,
  });

  /// Factory constructor to create a [TurnstileException] from a error [code]
  ///
  /// This constructor maps an error [code] to a corresponding error type,
  /// error messages and potential solutions based on the code provided
  /// by Cloudflare Turnstile error codes.
  ///
  /// Example:
  /// ```dart
  /// var error = TurnstileException.fromCode(110100);
  /// print(error.message); // Outputs the message for invalid sitekey
  /// ```
  ///
  ///Refer to [Client-side errors](https://developers.cloudflare.com/turnstile/troubleshooting/client-side-errors/).
  factory TurnstileException.fromCode(int code) {
    var message = 'unknown error';
    var retryable = false;
    var errorType = TurnstileError.UNKNOWN;

    switch (code) {
      case var _ when code >= 100000 && code < 102000:
        errorType = TurnstileError.INITIALIZATION_PROBLEM;
        message = 'There was a problem initializing Turnstile before a '
            'challenge could be started.';
      case var _ when code >= 102000 && code < 103000:
      case var _ when code >= 103000 && code < 104000:
      case var _ when code >= 104000 && code < 105000:
      case var _ when code >= 106000 && code < 107000:
        retryable = true;
        errorType = TurnstileError.INVALID_PARAMETERS;
        message = 'The visitor sent an invalid parameter as part of the '
            'challenge towards Turnstile.';
      case var _ when code >= 105000 && code < 106000:
        errorType = TurnstileError.TURNSTILE_API_COMPATIBILITY;
        message = 'Turnstile was invoked in a deprecated or invalid way.';
      case 110100:
      case 110110:
        errorType = TurnstileError.INVALID_SITEKEY;
        message = 'Turnstile was invoked with an invalid sitekey or a '
            'sitekey that is no longer active.';
      case 110200:
        retryable = true;
        errorType = TurnstileError.UNKNOWN_DOMAIN;
        message = 'Domain not allowed.';
      case 110420:
        errorType = TurnstileError.INVALID_ACTION;
        message = 'This error occurs when an unsupported or incorrectly '
            'formatted action is submitted.';
      case 110430:
        errorType = TurnstileError.INVALID_CDATA;
        message = 'This error in Turnstile refers to an issue encountered '
            'when processing Custom Data (cData). This error occurs when '
            'the cData provided does not adhere to the expected format or '
            'contains invalid characters.';
      case 110500:
        errorType = TurnstileError.UNSUPPORTED_BROWSER;
        message = 'The visitor is using an unsupported browser.';
      case 110510:
        errorType = TurnstileError.INCONSISTENT_USER_AGENT;
        message = 'The visitor provided an inconsistent user-agent '
            'throughout the process of solving Turnstile.';
      case var _ when code >= 110600 && code < 110620:
        retryable = true;
        errorType = TurnstileError.CHALLANGE_TIMED_OUT;
        message = 'The visitor took too long to solve the challenge and '
            'the challenge timed out.';
      case var _ when code >= 110620 && code < 120000:
        retryable = true;
        errorType = TurnstileError.CHALLANGE_TIMED_OUT_VISIBLE;
        message = 'The visitor took too long to solve the interactive '
            'challenge and the challenge became outdated.';
      case var _ when code >= 120000 && code < 200010:
        errorType = TurnstileError.INTERNAL_ERROR;
        message = 'Internal Errors for Cloudflare Employees.';
      case 200010:
        errorType = TurnstileError.INVALID_CACHING;
        message = 'Some portion of Turnstile was accidentally cached.';
      case 200100:
        errorType = TurnstileError.TIME_PROBLEM;
        message = 'The visitor’s clock is incorrect.';
      case var _ when code >= 300000 && code < 301000:
        retryable = true;
        errorType = TurnstileError.GENERIC_CLIENT_EXECUTION;
        message = 'An unspecified error occurred in the visitor while '
            'they were solving a challenge.';
      case var _ when code >= 400000 && code < 401000:
        errorType = TurnstileError.INCORRECT_CONFIGURATION;
        message = 'The configuration for Turnstile is incorrect or '
            'incomplete. Check the site key, secret key, and domain setup.';
      case var _ when code >= 600000 && code < 601000:
        retryable = true;
        errorType = TurnstileError.CHALLANGE_EXECUTIION_FAILURE;
        message = 'A visitor failed to solve a Turnstile Challenge. '
            'Also used by failing testing sitekey.';
    }

    return TurnstileException(
      message,
      code: code,
      errorType: errorType,
      retryable: retryable,
    );
  }

  /// The error code associated with the Turnstile error.
  ///
  /// Defaults to `-1` if no specific code is provided.
  /// Refer to [Troubleshooting widget](https://developers.cloudflare.com/turnstile/troubleshooting/troubleshooting-the-widget/).
  final int code;

  /// The error message associated with the Turnstile error.
  ///
  /// This message provides insight into what went wrong
  /// during the turnstile challange.
  final String message;

  /// The specific type of error categorized by [TurnstileError]
  ///
  /// Defaults to [TurnstileError.UNKNOWN] if no specific error type is
  /// identified.
  final TurnstileError errorType;

  /// Indicates whether the error is retryable.
  ///
  /// If `true`, it suggests that the operation can be retried to potentially
  /// resolve the error.
  /// Defaults to `false` if not specified.
  final bool retryable;

  /// Provides a string representation of the [TurnstileException].
  @override
  String toString() {
    if (code <= 0) {
      return 'TurnstileException $code: $message';
    }

    return 'TurnstileException: $message';
  }
}

/// Enum representing different types of Turnstile errors.
///
/// Refer to [Client-side errors](https://developers.cloudflare.com/turnstile/troubleshooting/client-side-errors/).
enum TurnstileError {
  /// There was an issue during Turnstile initialization.
  INITIALIZATION_PROBLEM,

  /// An invalid parameter was provided during the challenge.
  INVALID_PARAMETERS,

  /// Compatibility issue with Turnstile API or deprecated usage.
  TURNSTILE_API_COMPATIBILITY,

  /// The provided sitekey is invalid or inactive.
  INVALID_SITEKEY,

  /// Domain is not allowed by Turnstile.
  UNKNOWN_DOMAIN,

  /// An unsupported or incorrectly formatted action was submitted.
  INVALID_ACTION,

  /// Custom Data (cData) provided is invalid or incorrectly formatted.
  INVALID_CDATA,

  /// The visitor is using an unsupported browser.
  UNSUPPORTED_BROWSER,

  /// The user-agent provided by the visitor was inconsistent during
  /// the challenge.
  INCONSISTENT_USER_AGENT,

  /// The configuration for Turnstile is incorrect or incomplete.
  INCORRECT_CONFIGURATION,

  /// The challenge timed out before the visitor could solve it.
  CHALLANGE_TIMED_OUT,

  /// The interactive challenge timed out and became outdated.
  CHALLANGE_TIMED_OUT_VISIBLE,

  /// Internal error within Turnstile, typically used for Cloudflare employees.
  INTERNAL_ERROR,

  /// Part of Turnstile was accidentally cached, causing issues.
  INVALID_CACHING,

  /// The visitor’s device clock is incorrect, causing time-related issues.
  TIME_PROBLEM,

  /// A generic error occurred on the client side during the challenge.
  GENERIC_CLIENT_EXECUTION,

  /// The visitor failed to solve the Turnstile challenge.
  CHALLANGE_EXECUTIION_FAILURE,

  /// An unknown error occurred.
  UNKNOWN,
}
