[![Flutter Community: flutter_blurhash](https://fluttercommunity.dev/_github/header/flutter_blurhash)](https://github.com/fluttercommunity/community)

[![pub package](https://img.shields.io/pub/v/flutter_blurhash.svg)](https://pub.dev/packages/flutter_blurhash)
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/cloudposse.svg?style=social&label=%20%40BlueAquilae)](https://twitter.com/blueaquilae)

# flutter_blurhash

[Blurhash](https://blurha.sh) is compact representation of a blurred image, often used fo

This package implements the blurhash-decoding algorithm in pure Dart and provides the `BlurHash` widget that displays
the blurhash and can transition into the actual image once it is loaded.

It doesn't currently support encoding of Blurhash.

## Generation

A fast and easy way to get a blurhash for your image is to upload it to https://blurha.sh.

<img width="1211" alt="Blurhash demo" src="https://user-images.githubusercontent.com/1295961/75059847-129d6800-54de-11ea-8832-d19ea58eb7eb.png">

## Example

Constrain your widget's render area and let BlurHash fill the pixels.

```dart
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("BlurHash")),
        body: const SizedBox.expand(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.6,
              child: BlurHash(hash: "L5H2EC=PM+yV0g-mq.wG9c010J}I"),
            ),
          ),
        ),
      ),
    );
  }
}
```

## Optimization Modes

- **None** (`BlurHashOptimizationMode.none`): The original algorithm, provided for backward compatibility.
- **Standard** (`BlurHashOptimizationMode.standard`): Optimized decoding with better cache locality and performance.
- **Approximation** (`BlurHashOptimizationMode.approximation`): Fastest mode with an approximated sRGB conversion that produces slightly darker results but significantly improves performance.

```dart
class BlurHashApp extends StatelessWidget {
  const BlurHashApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text("BlurHash")),
      body: const SizedBox.expand(
        child: Center(
          child: AspectRatio(
            aspectRatio: 1.6,
            child: BlurHash(
              hash: "L5H2EC=PM+yV0g-mq.wG9c010J}I",
              optimizationMode: BlurHashOptimizationMode.approximation,
            ),
          ),
        ),
      ),
    ),
  );
}
```
