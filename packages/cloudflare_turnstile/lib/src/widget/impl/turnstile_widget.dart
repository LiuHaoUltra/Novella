import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudflare_turnstile/src/controller/impl/turnstile_controller.dart';
import 'package:cloudflare_turnstile/src/turnstile_exception.dart';
import 'package:cloudflare_turnstile/src/widget/interface.dart' as i;
import 'package:cloudflare_turnstile/src/widget/turnstile_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const String _tokenReceivedJSHandler =
    'window.flutter_inappwebview.callHandler(`TurnstileToken`, token);';
const String _errorJSHandler =
    'window.flutter_inappwebview.callHandler(`TurnstileError`, code);';
const String _tokenExpiredJSHandler =
    'window.flutter_inappwebview.callHandler(`TokenExpired`);';
const String _widgetCreatedJSHandler =
    'window.flutter_inappwebview.callHandler(`TurnstileWidgetId`, widgetId);';

/// Cloudflare Turnstile mobile implementation
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

  /// Turnstile view builder
  static String buildHTML({
    required String siteKey,
    required TurnstileOptions options,
    required String onTokenReceived,
    required String onTurnstileError,
    required String onTokenExpired,
    required String onWidgetCreated,
    String? action,
    String? cData,
  }) {
    final exp = RegExp(
      '<TURNSTILE_(SITE_KEY|ACTION|CDATA|THEME|SIZE|LANGUAGE|RETRY|'
      'RETRY_INTERVAL|REFRESH_EXPIRED|REFRESH_TIMEOUT|READY|'
      'TOKEN_RECIVED|ERROR|TOKEN_EXPIRED|CREATED)>',
    );

    final replacedText = _source.replaceAllMapped(exp, (match) {
      switch (match.group(1)) {
        case 'SITE_KEY':
          return siteKey;
        case 'ACTION':
          return action ?? '';
        case 'CDATA':
          return cData ?? '';
        case 'THEME':
          return options.theme.name;
        case 'SIZE':
          return options.size.name;
        case 'LANGUAGE':
          return options.language;
        case 'RETRY':
          return options.retryAutomatically ? 'auto' : 'never';
        case 'RETRY_INTERVAL':
          return options.retryInterval.inMilliseconds.toString();
        case 'REFRESH_EXPIRED':
          return options.refreshExpired.name;
        case 'REFRESH_TIMEOUT':
          return options.refreshTimeout.name;
        case 'TOKEN_RECIVED':
          return onTokenReceived;
        case 'ERROR':
          return onTurnstileError;
        case 'TOKEN_EXPIRED':
          return onTokenExpired;
        case 'CREATED':
          return onWidgetCreated;
        default:
          return match.group(0) ?? '';
      }
    });

    return replacedText;
  }

  static const String _source = """
<!DOCTYPE html>
<html lang="en">

<head>
   <meta charset="UTF-8">
   <link rel="icon" href="data:,">
   <meta name="viewport"
      content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0">
   <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"></script>

   
</head>

<body>
   <div id="cf-turnstile"></div>
   <script>
      turnstile.ready(function () {
           if (!document.getElementById('cf-turnstile').hasChildNodes()) {
               const widgetId = turnstile.render('#cf-turnstile', {
                  sitekey: '<TURNSTILE_SITE_KEY>',
                  action: '<TURNSTILE_ACTION>',
                  cData: '<TURNSTILE_CDATA>',
                  theme: '<TURNSTILE_THEME>',
                  size: '<TURNSTILE_SIZE>',
                  language: '<TURNSTILE_LANGUAGE>',
                  retry: '<TURNSTILE_RETRY>',
                  'retry-interval': parseInt('<TURNSTILE_RETRY_INTERVAL>'),
                  'refresh-expired': '<TURNSTILE_REFRESH_EXPIRED>',
                  'refresh-timeout': '<TURNSTILE_REFRESH_TIMEOUT>',
                  'feedback-enabled': false,
                  callback: function (token) {
                     <TURNSTILE_TOKEN_RECIVED>
                  },
                  'error-callback': function (code) {
                     <TURNSTILE_ERROR>
                  },
                  'expired-callback': function () {
                     <TURNSTILE_TOKEN_EXPIRED>
                  }
               });

               <TURNSTILE_CREATED>
           }
        });

   </script>
   <style>
      * {
         overflow: hidden;
         margin: 0;
         padding: 0;
      }
   </style>
</body>

</html>

""";

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
  ///   errorBuilder: (context, error) {
  ///     return Text(error.message);
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
  final GlobalKey webViewKey = GlobalKey();

  // keepAlive 实例必须只创建一次，否则每次 build 都会重建 WebView
  final _keepAlive = InAppWebViewKeepAlive();

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    disableHorizontalScroll: true,
    verticalScrollBarEnabled: false,
    transparentBackground: true,
    disallowOverScroll: true,
    disableVerticalScroll: true,
    supportZoom: false,
    useWideViewPort: false,
    disableDefaultErrorPage: true,
    disableContextMenu: true,
    disableLongPressContextMenuOnLinks: true,
  );

  late String data;

  String? widgetId;

  bool _isWidgetReady = false;
  bool _isTurnstileLoaded = false;
  TurnstileException? _hasError;
  bool _isRendered = false;
  Timer? _scriptLoadTimer;

  @override
  void initState() {
    super.initState();

    // Check if the platform is supported
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS)) {
      throw UnsupportedError(
        'CloudflareTurnstile only supports Android, iOS, Windows, Macos '
        'and Web platforms.',
      );
    }

    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setTurnstileTheme();
    });

    data = CloudflareTurnstile.buildHTML(
      siteKey: widget.siteKey,
      action: widget.action,
      cData: widget.cData,
      options: widget.options,
      onTokenReceived: _tokenReceivedJSHandler,
      onTurnstileError: _errorJSHandler,
      onTokenExpired: _tokenExpiredJSHandler,
      onWidgetCreated: _widgetCreatedJSHandler,
    );

    _view = _buildView();
  }

  void _setTurnstileTheme() {
    if (widget.options.theme == TurnstileTheme.auto) {
      final brightness = MediaQuery.of(context).platformBrightness;
      final isDark = brightness == Brightness.dark;
      widget.options.theme =
          isDark ? TurnstileTheme.dark : TurnstileTheme.light;
    }
  }

  void _createChannels(InAppWebViewController controller) {
    controller
      ..addJavaScriptHandler(
        handlerName: 'TurnstileToken',
        callback: (List<dynamic> args) {
          if (!mounted) return;
          final token = args[0] as String;
          widget.controller?.token = token;
          widget.onTokenReceived?.call(token);
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TurnstileError',
        callback: (List<dynamic> args) {
          if (_hasError != null) return;
          final errorCode = int.tryParse(args[0] as String);
          _addError(TurnstileException.fromCode(errorCode ?? -1));
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TurnstileWidgetId',
        callback: (List<dynamic> args) {
          if (!mounted) return;
          widgetId = args[0] as String;
          widget.controller?.widgetId = widgetId;
          _isRendered = true;
          _scriptLoadTimer?.cancel();
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TokenExpired',
        callback: (List<dynamic> message) {
          if (!mounted) return;
          widget.onTokenExpired?.call();
        },
      );
  }

  void _resetWidget() {
    _hasError = null;
    _isWidgetReady = false;
    widget.controller?.error = null;
    widget.controller?.isWidgetReady = false;
    if (!mounted) return;
    setState(() {});
  }

  void _addError(TurnstileException error) {
    _hasError = error;
    widget.controller?.error = error;
    widget.onError?.call(_hasError!);
    if (!mounted) return;
    setState(() {});
  }

  void _ready(bool ready) {
    _isWidgetReady = ready;
    widget.controller?.isWidgetReady = ready;
    if (!mounted) return;
    setState(() {});
  }

  // _view 只在 initState 时构建一次，保证 keepAlive 实例稳定
  late final InAppWebView _view;

  // Windows 上 InAppWebViewInitialData 不会正确设置 security origin，
  // 改用 initialUrlRequest 导航到真实 baseUrl，再拦截请求注入 HTML。
  InAppWebView _buildView() {
    final baseUri = WebUri(widget.baseUrl);

    if (Platform.isWindows) {
      return InAppWebView(
        keepAlive: _keepAlive,
        key: webViewKey,
        initialUrlRequest: URLRequest(url: baseUri),
        initialSettings: _settings,
        onWebViewCreated: (controller) {
          _createChannels(controller);
          widget.controller?.setConnector(controller);
        },
        onLoadStart: (controller, _) {
          _isTurnstileLoaded = false;
          _resetWidget();
        },
        onLoadResource: (controller, resource) {
          if (_isTurnstileLoaded && _hasError != null) {
            controller.reload();
          }
        },
        shouldInterceptRequest: (controller, request) async {
          // 拦截对 baseUrl 的请求，返回本地 HTML，使 origin 正确设为真实域名
          final reqUrl = request.url.toString();
          final base = baseUri.toString().replaceAll(RegExp(r'/$'), '');
          if (reqUrl == base ||
              reqUrl == '$base/' ||
              reqUrl.startsWith('$base/?')) {
            return WebResourceResponse(
              contentType: 'text/html; charset=utf-8',
              data: Uint8List.fromList(utf8.encode(data)),
            );
          }
          return null;
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          var reqHost = navigationAction.request.url?.host;
          if (reqHost == null || reqHost.isEmpty) reqHost = 'about:srcdoc';

          final host = baseUri.host;
          final allowedHosts = RegExp(
            'localhost|'
            '${RegExp.escape(host)}|'
            r'challenges\.cloudflare\.com|'
            'about:blank|'
            'about:srcdoc',
          );

          if (allowedHosts.hasMatch(reqHost)) {
            return NavigationActionPolicy.ALLOW;
          }
          return NavigationActionPolicy.CANCEL;
        },
        onLoadStop: (controller, uri) async {
          if (!_isWidgetReady && !mounted) {
            final contentWidth = await controller.getContentWidth();
            if (contentWidth != null && contentWidth <= 0) {
              dev.log(
                'Widget mode mismatch: Please verify the widget mode in the '
                'Cloudflare dashboard settings.',
                name: 'cloudflare_turnstile',
                level: 800,
              );
            }
          }
          _isTurnstileLoaded = true;
          _ready(true);
          _scriptLoadTimer?.cancel();
          _scriptLoadTimer = Timer(const Duration(milliseconds: 8000), () {
            if (!mounted) return;
            if (!_isRendered) widget.onTimeout?.call();
          });
        },
        onConsoleMessage: (controller, consoleMessage) {},
        onReceivedError: (controller, __, error) {
          if (error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST) return;
          _ready(false);
          _addError(TurnstileException(error.description));
        },
        onPermissionRequest: (_, __) async => PermissionResponse(),
      );
    }

    // Android / iOS / macOS：保持原有 initialData 方式
    return InAppWebView(
      keepAlive: _keepAlive,
      key: webViewKey,
      initialData: InAppWebViewInitialData(data: data, baseUrl: baseUri),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        _createChannels(controller);
        widget.controller?.setConnector(controller);
      },
      onLoadStart: (controller, _) {
        _isTurnstileLoaded = false;
        _resetWidget();
      },
      onLoadResource: (controller, resource) {
        if (_isTurnstileLoaded && _hasError != null) {
          controller.reload();
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var reqHost = navigationAction.request.url?.host;
        if (reqHost == null || reqHost.isEmpty) reqHost = 'about:srcdoc';

        final host = baseUri.host;
        final allowedHosts = RegExp(
          'localhost|'
          '${RegExp.escape(host)}|'
          r'challenges\.cloudflare\.com|'
          'about:blank|'
          'about:srcdoc',
        );

        if (allowedHosts.hasMatch(reqHost)) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (controller, uri) async {
        if (!_isWidgetReady && !mounted) {
          final contentWidth = await controller.getContentWidth();
          if (contentWidth != null && contentWidth <= 0) {
            dev.log(
              'Widget mode mismatch: The current widget is Invisible, which '
              'may not match the mode set in the Cloudflare Turnstile '
              'dashboard. Please verify the widget mode in the Cloudflare '
              'dashboard settings.',
              name: 'cloudflare_turnstile',
              level: 800,
            );
          }
        }

        _isTurnstileLoaded = true;
        _ready(true);
        _scriptLoadTimer?.cancel();
        _scriptLoadTimer = Timer(const Duration(milliseconds: 8000), () {
          if (!mounted) return;
          if (!_isRendered) {
            widget.onTimeout?.call();
          }
        });
      },
      onConsoleMessage: (controller, consoleMessage) {},
      onReceivedError: (controller, __, error) {
        if (error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST) {
          return;
        }
        _ready(false);
        _addError(TurnstileException(error.description));
      },
      onPermissionRequest: (_, __) async => PermissionResponse(),
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (!Platform.isWindows) {
      InAppWebViewController.clearAllCache();
    }
    _scriptLoadTimer?.cancel();
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
      maintainState: true,
      child: AnimatedContainer(
        duration: widget.options.animationDuration!,
        width: _isWidgetReady ? widget.options.size.width : 0,
        height: _isWidgetReady ? widget.options.size.height : 0,
        curve: widget.options.curves!,
        decoration: BoxDecoration(
          color: primaryColor,
          borderRadius: widget.options.borderRadius,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: adaptiveBorderColor),
          borderRadius: widget.options.borderRadius,
        ),
        child: ClipRRect(
          clipBehavior: Clip.hardEdge,
          borderRadius: widget.options.borderRadius!.add(
            // add extra 1 px because border
            const BorderRadius.all(Radius.circular(1)),
          ),
          child: _view,
        ),
      ),
    );

    return Wrap(children: [turnstileWidget]);
  }
}

// 忽略：用于内部实现的私有 Widget，其状态管理逻辑允许其非 final 字段。
// ignore: must_be_immutable
class _TurnstileInvisible extends CloudflareTurnstile {
  _TurnstileInvisible.init({
    required String siteKey,
    required String baseUrl,
    String? action,
    String? cData,
    TurnstileOptions? options,
    super.onTokenReceived,
    super.onTokenExpired,
    super.onTimeout,
  }) : super(siteKey: siteKey, controller: TurnstileController()) {
    // Check if the platform is supported
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isMacOS)) {
      throw UnsupportedError(
        'CloudflareTurnstile only supports Android, iOS, Windows, Macos '
        'and Web platforms.',
      );
    }

    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    _completer = Completer<dynamic>();

    final data = CloudflareTurnstile.buildHTML(
      siteKey: siteKey,
      action: action,
      cData: cData,
      options: options!,
      onTokenReceived: _tokenReceivedJSHandler,
      onTurnstileError: _errorJSHandler,
      onTokenExpired: _tokenExpiredJSHandler,
      onWidgetCreated: _widgetCreatedJSHandler,
    );

    _view = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: data,
        baseUrl: WebUri(baseUrl),
      ),
      onWebViewCreated: (wController) {
        controller?.setConnector(wController);
        _createChannels(wController);
      },
      onLoadStart: (_, __) {
        controller?.isWidgetReady = false;
        controller?.error = null;
      },
      onLoadStop: (_, __) {
        controller?.isWidgetReady = true;
      },
      onConsoleMessage: (_, __) {},
      onReceivedError: (_, __, error) {
        if (error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST) {
          return;
        }
        controller?.error = TurnstileException(error.description);
        if (!_completer!.isCompleted) {
          _completer?.completeError(error);
        }
      },
      onPermissionRequest: (_, __) async => PermissionResponse(),
    );
  }

  late HeadlessInAppWebView _view;
  Completer<dynamic>? _completer;
  bool _isRendered = false;
  Timer? _scriptLoadTimer;

  void _createChannels(InAppWebViewController wController) {
    wController
      ..addJavaScriptHandler(
        handlerName: 'TurnstileToken',
        callback: (List<dynamic> args) {
          final token = args[0] as String;
          controller?.token = token;
          onTokenReceived?.call(token);
          if (!_completer!.isCompleted) {
            _completer?.complete(token);
          }
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TurnstileError',
        callback: (List<dynamic> args) {
          final errorCode = int.tryParse(args[0] as String);
          final error = TurnstileException.fromCode(errorCode ?? -1);

          if (!_completer!.isCompleted) {
            _completer?.completeError(error);
          }
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TurnstileWidgetId',
        callback: (List<dynamic> args) {
          controller!.widgetId = args[0] as String;
          _isRendered = true;
          _scriptLoadTimer?.cancel();
        },
      )
      ..addJavaScriptHandler(
        handlerName: 'TokenExpired',
        callback: (List<dynamic> message) {
          // Handle token expiration logic here
          onTokenExpired?.call();
          if (!_completer!.isCompleted) {
            _completer?.complete(null);
          }
        },
      );
  }

  @override
  Future<String?> getToken() async {
    _completer = Completer<String?>();

    if (!_view.isRunning()) {
      await _view.run();
    }

    if (token != null) {
      await controller!.refreshToken();
    }

    _scriptLoadTimer?.cancel();
    _scriptLoadTimer = Timer(const Duration(milliseconds: 8000), () {
      if (!_isRendered) {
        onTimeout?.call();
      }
    });

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
    if (!_view.isRunning() || forceRefresh) {
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
    await _view.dispose();
  }
}
