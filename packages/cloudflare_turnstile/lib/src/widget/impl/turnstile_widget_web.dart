// 忽略：需要使用 web 库进行平台交互。
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui;

import 'package:cloudflare_turnstile/src/controller/impl/turnstile_controller_web.dart';
import 'package:cloudflare_turnstile/src/turnstile_exception.dart';
import 'package:cloudflare_turnstile/src/widget/interface.dart' as i;
import 'package:cloudflare_turnstile/src/widget/turnstile_options.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class _DartTurnstile {
  const _DartTurnstile({
    this.onTokenReceived,
    this.onTokenExpired,
    this.onErrorCallback,
    this.onLoaded,
  });

  final i.OnTokenReceived? onTokenReceived;
  final i.OnTokenExpired? onTokenExpired;
  final i.OnError? onErrorCallback;
  final Function()? onLoaded;

  @JSExport('onTokenReceived')
  void onReceived(JSString token) {
    onTokenReceived?.call(token.toDart);
  }

  @JSExport('onTokenExpired')
  void onExpired() {
    onTokenExpired?.call();
  }

  @JSExport('onTokenError')
  void onError(JSString code) {
    final errorCode = int.tryParse(code.toDart) ?? -1;
    onErrorCallback?.call(TurnstileException.fromCode(errorCode));
  }

  @JSExport('onTurnstileReady')
  void onReady() {
    onLoaded?.call();
  }

  bool isScriptLoaded() => web.window.hasProperty('turnstile'.toJS).toDart;

  void loadScript() {
    if (!isScriptLoaded()) {
      final mainScript = web.HTMLScriptElement()
        ..id = 'turnstile-script'
        ..async = true
        ..defer = true
        ..src =
            'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=onTurnstileReady';

      web.document.head?.append(mainScript);
    }
  }

  web.HTMLDivElement buildWidget({
    required String siteKey,
    required TurnstileOptions options,
    String? action,
    String? cData,
  }) {
    final widget = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('data-sitekey', siteKey)
      ..setAttribute('data-theme', options.theme.name)
      ..setAttribute('data-size', options.size.name)
      ..setAttribute('data-language', options.language)
      ..setAttribute(
        'data-retry',
        options.retryAutomatically ? 'auto' : 'never',
      )
      ..setAttribute(
        'data-retry-interval',
        options.retryInterval.inMilliseconds.toString(),
      )
      ..setAttribute('data-refresh-expired', options.refreshExpired.name)
      ..setAttribute('data-refresh-timeout', options.refreshTimeout.name)
      ..setAttribute('data-feedback-enabled', 'false')
      ..setAttribute('data-callback', 'onTokenReceived')
      ..setAttribute('data-expired-callback', 'onTokenExpired')
      ..setAttribute('data-error-callback', 'onTurnstileError');

    if (action != null && action.isNotEmpty) {
      widget.setAttribute('data-action', action);
    }

    if (cData != null && cData.isNotEmpty) {
      widget.setAttribute('data-cdata', cData);
    }

    return widget;
  }
}

String _createViewType() {
  final widgetId = '_${DateTime.now().microsecondsSinceEpoch}';
  return '_turnstile_$widgetId';
}

@JS('turnstile.render')
external String? _renderWidget(String target);

/// Cloudflare Turnstile web implementation
class CloudflareTurnstile extends StatefulWidget
    implements i.CloudflareTurnstile {
  /// Create a Cloudflare Turnstile Widget
  CloudflareTurnstile({
    required this.siteKey,
    super.key,
    this.action,
    this.cData,
    this.baseUrl = 'http://localhost/',
    TurnstileOptions? options,
    this.controller,
    this.onTokenReceived,
    this.onTokenExpired,
    this.onError,
    this.onTimeout,
  }) : options = options ?? TurnstileOptions() {
    if (action != null) {
      assert(
        action!.length <= 32 && RegExp(r'^[a-zA-Z0-9_-]*$').hasMatch(action!),
        'action must be contain up to 32 characters including _ and -.',
      );
    }

    if (cData != null) {
      assert(
        cData!.length <= 32 && RegExp(r'^[a-zA-Z0-9_-]*$').hasMatch(cData!),
        'action must be contain up to 32 characters including _ and -.',
      );
    }

    assert(
      this.options.retryInterval.inMilliseconds > 0 &&
          this.options.retryInterval.inMilliseconds <= 900000,
      'Duration must be greater than 0 and less than or equal to 900000 '
      'milliseconds.',
    );
  }

  /// Create a Cloudflare Turnstile invisible widget.
  ///
  /// [siteKey] - A Cloudflare Turnstile sitekey.
  /// It`s likely generated or obtained from the Cloudflare dashboard.
  ///
  /// [action] - A customer value that can be used to differentiate widgets
  /// under the some sitekey in analytics and witch is returned upon validation.
  ///
  /// [cData] - A customer payload that can be used to attach customer data
  /// to the challenge throughout its issuance and which is returned upon
  /// validation.
  ///
  /// [baseUrl] - A website url corresponding current turnstile widget.
  ///
  /// [options] - Configuration options for the Turnstile widget.
  ///
  /// [onTokenReceived] - A Callback invoked upon success of the challange.
  /// The callback is passed a `token` that can be validated.
  ///
  /// [onTokenExpired] - A Callback invoke when the token expires and does not
  /// reset the widget.
  factory CloudflareTurnstile.invisible({
    required String siteKey,
    String? action,
    String? cData,
    String baseUrl = 'http://localhost',
    i.OnTokenReceived? onTokenReceived,
    i.OnTokenExpired? onTokenExpired,
    i.OnTimeout? onTimeout,
    TurnstileOptions? options,
  }) {
    return _TurnstileInvisible.init(
      siteKey: siteKey,
      action: action,
      cData: cData,
      baseUrl: baseUrl,
      onTokenReceived: onTokenReceived,
      onTokenExpired: onTokenExpired,
      onTimeout: onTimeout,
      options: options ?? TurnstileOptions(),
    );
  }

  /// This [siteKey] is associated with the corresponding widget configuration
  /// and is created upon the widget creation.
  ///
  /// It`s likely generated or obtained from the CloudFlare dashboard.
  @override
  final String siteKey;

  /// A customer value that can be used to differentiate widgets under the
  /// same sitekey in analytics and which is returned upon validation.
  ///
  /// This can only contain up to 32 alphanumeric characters including _ and -.
  @override
  final String? action;

  /// A customer payload that can be used to attach customer data to the
  /// challenge throughout its issuance and which is returned upon validation.
  ///
  /// This can only contain up to 255 alphanumeric characters including _ and -.
  @override
  final String? cData;

  /// The base URL of the Turnstile site.
  ///
  /// Defaults to 'http://localhost/'.
  @override
  final String baseUrl;

  /// Configuration options for the Turnstile widget.
  ///
  /// If no options are provided, the default [TurnstileOptions] are used.
  @override
  final TurnstileOptions options;

  /// A controller for managing interactions with the Turnstile widget.
  @override
  final TurnstileController? controller;

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
  @override
  final i.OnTokenReceived? onTokenReceived;

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
  @override
  final i.OnTokenExpired? onTokenExpired;

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
  ///   errorBuilder: (error) {
  ///     print(error.message);
  ///   },
  /// ),
  /// ```
  ///
  /// Refer to [Client-side errors](https://developers.cloudflare.com/turnstile/troubleshooting/client-side-errors/).
  @override
  final i.OnError? onError;

  /// Called when the Turnstile script/widget fails to load within a timeout.
  @override
  final i.OnTimeout? onTimeout;

  @override
  State<CloudflareTurnstile> createState() => _CloudflareTurnstileState();

  /// Retrives the current token from the widget.
  ///
  /// Returns `null` if no token is available.
  @override
  String? get token => throw UnimplementedError(
        'This function cannot be called in interactive widget mode.',
      );

  /// Retrives the current widget id.
  ///
  /// This `id` is used to uniquely identify the Turnstile widget instance.
  @override
  String? get id => throw UnimplementedError(
        'This function cannot be called in interactive widget mode.',
      );

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
  @override
  Future<void> refresh({bool forceRefresh = true}) {
    throw UnimplementedError(
      'This function cannot be called in interactive widget mode.',
    );
  }

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
  @override
  Future<String?> getToken() {
    throw UnimplementedError(
      'This function cannot be called in interactive widget mode.',
    );
  }

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
  @override
  Future<bool> isExpired() {
    throw UnimplementedError(
      'This function cannot be called in interactive widget mode.',
    );
  }

  /// Dispose invisible Turnstile widget.
  ///
  ///
  /// This should be called when the widget is no longer needed to free
  /// up resources and clean up.
  @override
  Future<void> dispose() {
    throw UnimplementedError(
      'This function cannot be called in interactive widget mode.',
    );
  }
}

class _CloudflareTurnstileState extends State<CloudflareTurnstile> {
  late web.HTMLDivElement _widget;
  late String _widgetViewId;
  late _DartTurnstile _turnstile;

  String? widgetId;

  bool _isWidgetReady = false;
  TurnstileException? _hasError;
  Timer? _scriptLoadTimer;
  bool _isDisposed = false;
  bool _viewCreated = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setTurnstileTheme();
      }
    });

    _widgetViewId = _createViewType();
    _turnstile = _DartTurnstile(
      onTokenReceived: (String token) {
        if (_isDisposed) return;
        widget.onTokenReceived?.call(token);
        widget.controller?.token = token;
      },
      onTokenExpired: () {
        if (_isDisposed) return;
        widget.onTokenExpired?.call();
      },
      onErrorCallback: _addError,
      onLoaded: _onTurnstileLoaded,
    );

    // Assign the Dart methods to the global JS object
    // Use 'globalContext' from dart:js_interop_unsafe
    globalContext
      ..setProperty(
        'onTokenReceived'.toJS,
        _turnstile.onReceived.toJS,
      )
      ..setProperty(
        'onTokenExpired'.toJS,
        _turnstile.onExpired.toJS,
      )
      ..setProperty(
        'onTurnstileError'.toJS,
        _turnstile.onError.toJS,
      )
      ..setProperty(
        'onTurnstileReady'.toJS,
        _turnstile.onReady.toJS,
      );

    _widget = _turnstile.buildWidget(
      siteKey: widget.siteKey,
      options: widget.options,
      cData: widget.cData,
      action: widget.action,
    )..className = 'cf-turnstile_$_widgetViewId';

    _registerView(_widgetViewId);
  }

  void _onTurnstileLoaded() {
    if (_isDisposed || !mounted) return;
    // Only render if the view has been created in the DOM
    if (_viewCreated) {
      _renderTurnstileWidget();
    }
  }

  void _renderTurnstileWidget() {
    if (_isDisposed || !mounted) return;
    if (widgetId != null) return; // Already rendered

    widgetId = _renderWidget('.cf-turnstile_$_widgetViewId');
    widget.controller?.widgetId = widgetId;
    if (mounted) {
      setState(() => _isWidgetReady = true);
    }
    widget.controller?.isWidgetReady = _isWidgetReady;
    _scriptLoadTimer?.cancel();
  }

  void _setTurnstileTheme() {
    if (widget.options.theme == TurnstileTheme.auto) {
      final brightness = MediaQuery.of(context).platformBrightness;
      final isDark = brightness == Brightness.dark;
      widget.options.theme =
          isDark ? TurnstileTheme.dark : TurnstileTheme.light;
    }
  }

  void _registerView(String viewType) {
    ui.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId, {Object? params}) {
        return _widget;
      },
    );
  }

  void _addError(TurnstileException error) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _hasError = error;
      _isWidgetReady = error.retryable;
      widget.controller?.error = error;
      widget.controller?.isWidgetReady = error.retryable;
      widget.onError?.call(error);
    });
  }

  late final Widget _view = HtmlElementView(
    key: widget.key,
    viewType: _widgetViewId,
    onPlatformViewCreated: (id) {
      _viewCreated = true;
      _scriptLoadTimer?.cancel();
      _scriptLoadTimer = Timer(const Duration(milliseconds: 8000), () {
        if (_isDisposed || !mounted) return;
        if (!_isWidgetReady) {
          widget.onTimeout?.call();
        }
      });

      // If script is already loaded, render the widget now
      if (_turnstile.isScriptLoaded()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _renderTurnstileWidget();
        });
      } else {
        _turnstile.loadScript();
      }
    },
  );

  @override
  void dispose() {
    _isDisposed = true;
    _scriptLoadTimer?.cancel();
    _scriptLoadTimer = null;
    _widget.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _setTurnstileTheme();

    final primaryColor = widget.options.theme == TurnstileTheme.light
        ? const Color(0xFFFAFAFA)
        : const Color(0xFF232323);
    final secondaryColor = widget.options.theme == TurnstileTheme.light
        ? const Color(0xFFDEDEDE)
        : const Color(0xFF9A9A9A);
    final adaptiveBorderColor =
        _isWidgetReady ? secondaryColor : Colors.transparent;

    final isErrorResolvable = _hasError != null && _hasError!.retryable == true;

    final turnstileWidget = Visibility(
      visible: _hasError == null || isErrorResolvable,
      child: AnimatedContainer(
        duration: widget.options.animationDuration!,
        width: _isWidgetReady ? widget.options.size.width : 0.1,
        height: _isWidgetReady ? widget.options.size.height : 0.1,
        curve: widget.options.curves!,
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: adaptiveBorderColor),
          borderRadius: widget.options.borderRadius,
        ),
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: widget.options.borderRadius!.add(
            // add extra 1 px because border
            const BorderRadius.all(
              Radius.circular(1),
            ),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: _view,
      ),
    );

    return turnstileWidget;
  }
}

// 忽略：这是一个内部使用的私有类，用于实现不可见验证。
// 这里的非 final 字段用于跨异步操作管理状态。
// ignore: must_be_immutable
class _TurnstileInvisible extends CloudflareTurnstile {
  _TurnstileInvisible.init({
    required super.siteKey,
    super.action,
    super.cData,
    super.baseUrl = 'http://localhost',
    super.onTokenReceived,
    super.onTokenExpired,
    super.onTimeout,
    super.options,
  }) : super(
          controller: TurnstileController(),
        ) {
    _register();
  }

  void _register() {
    _iframeViewType = _createViewType();
    final turnstile = _DartTurnstile(
      onTokenReceived: (String token) {
        controller?.token = token;
        onTokenReceived?.call(token);
        if (_completer != null && !_completer!.isCompleted) {
          _completer?.complete(token);
        }
      },
      onTokenExpired: () {
        onTokenExpired?.call();
        if (!_completer!.isCompleted) {
          _completer?.complete(null);
        }
      },
      onErrorCallback: (TurnstileException error) {
        controller?.error = error;
        if (!_completer!.isCompleted) {
          _completer?.completeError(error);
        }
      },
      onLoaded: () {
        controller?.widgetId = _renderWidget('.cf-turnstile_$_iframeViewType');
        controller?.isWidgetReady = true;
        _scriptLoadTimer?.cancel();
      },
    );

    globalContext
      ..setProperty(
        'onTokenReceived'.toJS,
        turnstile.onReceived.toJS,
      )
      ..setProperty(
        'onTokenExpired'.toJS,
        turnstile.onExpired.toJS,
      )
      ..setProperty(
        'onTurnstileError'.toJS,
        turnstile.onError.toJS,
      )
      ..setProperty(
        'onTurnstileReady'.toJS,
        turnstile.onReady.toJS,
      );

    _widget = turnstile.buildWidget(
      siteKey: siteKey,
      options: options,
      cData: cData,
      action: action,
    )..className = 'cf-turnstile_$_iframeViewType';

    web.document.body?.append(_widget);
    _scriptLoadTimer?.cancel();
    _scriptLoadTimer = Timer(const Duration(milliseconds: 8000), () {
      if (controller?.isWidgetReady != true) {
        onTimeout?.call();
      }
    });
    turnstile.loadScript();

    if (turnstile.isScriptLoaded()) {
      controller?.widgetId = _renderWidget('.cf-turnstile_$_iframeViewType');
      controller?.isWidgetReady = true;
    }
  }

  late web.HTMLDivElement _widget;
  late String _iframeViewType;
  Completer<dynamic>? _completer;
  Timer? _scriptLoadTimer;

  @override
  Future<String?> getToken() async {
    _completer = Completer<String?>();

    if (token != null) {
      await controller?.refreshToken();
    }

    return _completer!.future as Future<String?>;
  }

  @override
  String? get id => controller?.widgetId;

  @override
  Future<bool> isExpired() {
    return controller!.isExpired();
  }

  @override
  Future<void> refresh({bool forceRefresh = true}) async {
    if (!controller!.isWidgetReady || forceRefresh) {
      await getToken();
    } else if (controller!.isWidgetReady) {
      _completer = Completer<String?>();

      if (token != null) {
        if (!await controller!.isExpired()) {
          if (!_completer!.isCompleted) {
            _completer?.complete(token);
            return _completer!.future;
          }
        }
      }

      await controller?.refreshToken();
      return _completer!.future;
    }
  }

  @override
  String? get token => controller?.token;

  @override
  Future<void> dispose() async {
    _scriptLoadTimer?.cancel();
    _widget.remove();
  }
}
