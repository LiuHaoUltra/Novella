# Flutter Cloudflare Turnstile [![Pub](https://img.shields.io/pub/v/cloudflare_turnstile.svg)](https://pub.dartlang.org/packages/cloudflare_turnstile)

![head](https://github.com/user-attachments/assets/5ffd938a-93b5-490e-b0dc-a3f2a99958be)

Cloudflare turnstile is a free CAPTCHAs Alternative, Turnstile delivers frustration-free, CAPTCHA-free web experiences to website visitors - with just a simple snippet of free code. Moreover, Turnstile stops abuse and confirms visitors are real without the data privacy concerns or awful user experience of CAPTCHAs.

> [!WARNING]
>
> This package is unofficial and not endorsed by Cloudflare. Use it at your own discretion.

## Installation

```sh
flutter pub add cloudflare_turnstile
```

For Windows platform, please follow the inappwebview windows setup [instructions](https://inappwebview.dev/docs/intro/#setup-windows).

# Example

Here's a quick example that shows how to add Cloudflare Turnstile widget to your flutter app

```dart
import 'package:flutter/material.dart';
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Turnstile widget configuration
    final TurnstileOptions options = const TurnstileOptions(
      size: TurnstileSize.normal,
      theme: TurnstileTheme.light,
      language: 'ar',
      retryAutomatically: false,
      refreshTimeout: TurnstileRefreshTimeout.manual,
    );

    return Scaffold(
      body: Center(
        child: CloudflareTurnstile(
          siteKey: '3x00000000000000000000FF', //Change with your site key
          baseUrl: 'http://localhost/',
          onTokenReceived: (token) {
            print(token);
          },
        ),
      ),
    );
  }
}
```
> For Android and iOS platforms you need to provide the `baseUrl` parameter with the actual URL of your Turnstile Widget Domains list. `baseUrl` must be the same as the list of domains when creating a Widget.

## Using Turnstile invisible mode

Here's how to use Cloudflare's invisible Turnstile, which automatically solves the challenge in the background 

```dart
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';


class TurnstileService {
  /// Retrieves the CloudFlare Turnstile token using invisible mode.
  static Future<String?> get token async {
    // Initialize an instance of invisible Cloudflare Turnstile with your site key
    final turnstile = CloudflareTurnstile.invisible(
      siteKey: '1x00000000000000000000BB', // Replace with your actual site key
    );

    try {
      // Get the Turnstile token
      final token = await turnstile.getToken();
      return token; // Return the token upon success
    } on TurnstileException catch (e) {
      // Handle Turnstile failure
      print('Challenge failed: ${e.message}');
    } finally {
      // Ensure the Turnstile instance is properly disposed of
      turnstile.dispose();
    }

    // Return null if the token couldn't be generated
    return null;
  }
}
```

> [!WARNING]
>
> It's important to call `dispose()` on the `CloudflareTurnstile` instance when you no longer need it. This ensures that resources are properly cleaned up, preventing any potential memory issues.

## Contribution
Your contributions are welcome and greatly valued! If you have ideas, suggestions, or improvements, feel free to open an issue or submit a pull request. Every bit of help is appreciated, and your input can make a big difference. Just ensure your contributions fit with the project's goals and guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE.md](./LICENSE) file for details.
