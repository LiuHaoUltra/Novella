import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 Expressive (M3E) Loading Indicator (手动实现版)。
///
/// 设计目标：替代 APP 内所有传统「转圈」加载（例如 `CircularProgressIndicator`），
/// 提供带形态变换（morphing）+ 全局旋转的 MD3 Expressive 视觉效果。
///
/// 关键实现点（对应文档）：
/// - 双控制器：旋转周期 4666ms（线性 repeat），形变周期 650ms（7 形状循环）。
/// - 形状插值：不使用 `Path.lerp`，而是对固定采样点（按角度 θ 采样）做顶点 lerp，
///   规避拓扑不一致导致的插值瑕疵。
/// - 性能：7 组形状顶点在 initState 预计算；每帧仅进行插值 + 绘制。
/// - 默认颜色：`Theme.of(context).colorScheme.primary`。
/// - 默认样式：填充（[M3ELoadingIndicatorStyle.fill]）；也支持描边。
class M3ELoadingIndicator extends StatefulWidget {
  const M3ELoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.semanticsLabel,
    this.style = M3ELoadingIndicatorStyle.fill,
    this.strokeWidth,
    this.sampleCount = 96,
  }) : assert(sampleCount >= 24, 'sampleCount 过小会导致形状明显锯齿/插值不稳定');

  /// 组件外框尺寸（正方形）。
  ///
  /// - 为空时使用默认 48（贴近 M3E 规范中的容器标准尺寸）。
  final double? size;

  /// 指示器颜色；为空时使用主题色 `colorScheme.primary`。
  final Color? color;

  /// 无障碍语义 label；为空时使用英文 "Loading"。
  final String? semanticsLabel;

  /// 填充/描边。
  final M3ELoadingIndicatorStyle style;

  /// 描边宽度（仅当 style=stroke 生效）。为空时使用 3.0。
  final double? strokeWidth;

  /// 归一化采样点数量。
  ///
  /// 越大形状越平滑，但每帧插值成本越高。96 通常足够。
  final int sampleCount;

  @override
  State<M3ELoadingIndicator> createState() => _M3ELoadingIndicatorState();
}

enum M3ELoadingIndicatorStyle {
  fill,
  stroke,
}

class _M3ELoadingIndicatorState extends State<M3ELoadingIndicator>
    with TickerProviderStateMixin {
  static const Duration _rotationDuration = Duration(milliseconds: 4666);
  static const Duration _morphDuration = Duration(milliseconds: 650);

  // M3 "emphasized" 的工程近似（文档推荐的稳健选择之一）。
  static const Curve _morphCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  late final AnimationController _rotationController;
  late final AnimationController _morphController;

  late final List<_M3EShapeSpec> _shapeSpecs;
  late List<Float32List> _shapeVertices; // each: [x0,y0,x1,y1,...] in unit space

  int _shapeIndex = 0;

  @override
  void initState() {
    super.initState();

    _shapeSpecs = const [
      // 形状序列（顺序不可变）：SoftBurst → Cookie9 → Pentagon → Pill → Sunny → Cookie4 → Oval
      _M3EShapeSpec.star(sides: 12, innerRadius: 0.70, roundness: 0.55, sharpness: 1.6), // SoftBurst
      _M3EShapeSpec.polygon(sides: 9, roundness: 0.15), // Cookie9Sided
      _M3EShapeSpec.polygon(sides: 5, roundness: 0.10), // Pentagon
      _M3EShapeSpec.pill(roundness: 0.85, aspectRatio: 1.85), // Pill (stadium-ish)
      _M3EShapeSpec.star(sides: 8, innerRadius: 0.50, roundness: 0.10, sharpness: 2.4), // Sunny
      _M3EShapeSpec.superellipse(roundness: 0.55, exponent: 4.0, aspectRatio: 1.0), // Cookie4Sided (squircle-ish)
      _M3EShapeSpec.oval(roundness: 1.0, aspectRatio: 1.0), // Oval
    ];

    _shapeVertices = List<Float32List>.generate(
      _shapeSpecs.length,
      (i) => _generateVertices(_shapeSpecs[i], widget.sampleCount),
      growable: false,
    );

    _rotationController = AnimationController(vsync: this, duration: _rotationDuration)
      ..repeat();

    _morphController = AnimationController(vsync: this, duration: _morphDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _shapeIndex = (_shapeIndex + 1) % _shapeVertices.length);
          _morphController
            ..reset()
            ..forward();
        }
      })
      ..forward();
  }

  @override
  void didUpdateWidget(covariant M3ELoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 若采样点数变化，需要重新预计算。
    if (oldWidget.sampleCount != widget.sampleCount) {
      _shapeVertices = List<Float32List>.generate(
        _shapeSpecs.length,
        (i) => _generateVertices(_shapeSpecs[i], widget.sampleCount),
        growable: false,
      );
      // 避免索引越界（虽然长度不变，但做一次防御性归一化）。
      _shapeIndex = _shapeIndex % _shapeVertices.length;
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // M3E 规范中容器标准尺寸为 48dp；默认采用 48，使视觉更“有存在感”。
    final size = widget.size ?? 48.0;
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    final semanticsLabel = widget.semanticsLabel ?? 'Loading';

    return Semantics(
      label: semanticsLabel,
      // Loading 指示器是纯视觉反馈，保持简单语义即可。
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_rotationController, _morphController]),
            builder: (context, _) {
              final rotation = _rotationController.value * 2 * math.pi;
              final t = _morphCurve.transform(_morphController.value);

              final start = _shapeVertices[_shapeIndex];
              final end = _shapeVertices[(_shapeIndex + 1) % _shapeVertices.length];

              return CustomPaint(
                painter: _M3ELoadingPainter(
                  start: start,
                  end: end,
                  t: t,
                  rotation: rotation,
                  color: color,
                  style: widget.style,
                  strokeWidth: widget.strokeWidth,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

@immutable
class _M3EShapeSpec {
  const _M3EShapeSpec._({
    required this.kind,
    this.sides,
    this.innerRadius,
    required this.roundness,
    this.exponent,
    this.aspectRatio,
    this.sharpness,
  });

  final _M3EShapeKind kind;

  // polygon/star
  final int? sides;

  // star
  final double? innerRadius;

  /// 0..1：越大越趋近于圆/椭圆（用于近似“圆角/柔化”）。
  final double roundness;

  // superellipse/pill
  final double? exponent;

  /// 宽高比（>1 更扁的横向 pill/oval）。
  final double? aspectRatio;

  /// star：形状尖锐程度（越大越尖）。
  final double? sharpness;

  const _M3EShapeSpec.polygon({required int sides, required double roundness})
      : this._(
          kind: _M3EShapeKind.polygon,
          sides: sides,
          roundness: roundness,
        );

  const _M3EShapeSpec.star({
    required int sides,
    required double innerRadius,
    required double roundness,
    required double sharpness,
  }) : this._(
          kind: _M3EShapeKind.star,
          sides: sides,
          innerRadius: innerRadius,
          roundness: roundness,
          sharpness: sharpness,
        );

  const _M3EShapeSpec.oval({required double roundness, required double aspectRatio})
      : this._(
          kind: _M3EShapeKind.oval,
          roundness: roundness,
          aspectRatio: aspectRatio,
        );

  const _M3EShapeSpec.superellipse({
    required double roundness,
    required double exponent,
    required double aspectRatio,
  }) : this._(
          kind: _M3EShapeKind.superellipse,
          roundness: roundness,
          exponent: exponent,
          aspectRatio: aspectRatio,
        );

  const _M3EShapeSpec.pill({
    required double roundness,
    required double aspectRatio,
  }) : this._(
          kind: _M3EShapeKind.pill,
          roundness: roundness,
          aspectRatio: aspectRatio,
          exponent: 8.0,
        );
}

enum _M3EShapeKind {
  polygon,
  star,
  oval,
  superellipse,
  pill,
}

class _M3ELoadingPainter extends CustomPainter {
  _M3ELoadingPainter({
    required this.start,
    required this.end,
    required this.t,
    required this.rotation,
    required this.color,
    required this.style,
    required this.strokeWidth,
  }) : assert(start.length == end.length);

  final Float32List start;
  final Float32List end;
  final double t;
  final double rotation;
  final Color color;
  final M3ELoadingIndicatorStyle style;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = style == M3ELoadingIndicatorStyle.stroke
          ? PaintingStyle.stroke
          : PaintingStyle.fill;

    if (style == M3ELoadingIndicatorStyle.stroke) {
      paint
        ..strokeWidth = (strokeWidth ?? 3.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
    }

    final path = Path();

    // 让指示器尽可能“撑满”其布局盒子；描边时预留 strokeWidth/2 以避免被裁剪。
    final baseRadius = math.min(size.width, size.height) * 0.5;
    final inset = style == M3ELoadingIndicatorStyle.stroke
        ? (paint.strokeWidth / 2)
        : 0.0;
    final r = math.max(0.0, baseRadius - inset - 0.5);

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.rotate(rotation);

    // 顶点按 unit-space（[-1,1]）存储；此处缩放到像素空间。
    // 形变插值在 paint 内进行，避免 build 阶段分配新列表。
    final n = start.length;
    for (int i = 0; i < n; i += 2) {
      final x = _lerp(start[i], end[i], t) * r;
      final y = _lerp(start[i + 1], end[i + 1], t) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _M3ELoadingPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.t != t ||
        oldDelegate.rotation != rotation ||
        oldDelegate.color != color ||
        oldDelegate.style != style ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

Float32List _generateVertices(_M3EShapeSpec spec, int sampleCount) {
  // unit space: 最大半径归一化到 1.0
  final out = Float32List(sampleCount * 2);

  // 采样从 12 点方向开始（-pi/2），满足“特征对齐”。
  final startAngle = -math.pi / 2;
  final step = 2 * math.pi / sampleCount;

  for (int i = 0; i < sampleCount; i++) {
    final theta = startAngle + step * i;
    final r = _radiusAt(spec, theta);

    out[i * 2] = (r * math.cos(theta)).toDouble();
    out[i * 2 + 1] = (r * math.sin(theta)).toDouble();
  }

  // 归一化：确保不同 shape（尤其是 pill/oval 这类带 aspectRatio 的）不会超过单位圆，
  // 同时让其在绘制时尽量填满可用空间。
  double maxR2 = 0.0;
  for (int i = 0; i < out.length; i += 2) {
    final x = out[i];
    final y = out[i + 1];
    final r2 = x * x + y * y;
    if (r2 > maxR2) maxR2 = r2;
  }
  if (maxR2 > 0) {
    final inv = 1.0 / math.sqrt(maxR2);
    for (int i = 0; i < out.length; i++) {
      out[i] = (out[i] * inv).toDouble();
    }
  }

  return out;
}

double _radiusAt(_M3EShapeSpec spec, double theta) {
  // 基础半径（未 roundness）。
  double base;

  switch (spec.kind) {
    case _M3EShapeKind.polygon:
      base = _regularPolygonRadius(theta, spec.sides!);
      break;
    case _M3EShapeKind.star:
      base = _softStarRadius(theta, spec.sides!, spec.innerRadius!, spec.sharpness!);
      break;
    case _M3EShapeKind.oval:
      base = _ellipseRadius(theta, spec.aspectRatio!);
      break;
    case _M3EShapeKind.superellipse:
      base = _superellipseRadius(theta, spec.exponent!, spec.aspectRatio!);
      break;
    case _M3EShapeKind.pill:
      // pill 用更“硬”的 superellipse + 更强 roundness，近似 stadium。
      base = _superellipseRadius(theta, spec.exponent ?? 8.0, spec.aspectRatio!);
      break;
  }

  // roundness：向圆形（r=1）做插值，近似“圆角/柔化”。
  // 为避免过度收缩，做轻微缓和。
  final rr = spec.roundness.clamp(0.0, 1.0);
  final eased = rr * rr; // 让 0..0.3 更克制，1 更明显
  return _lerp(base, 1.0, eased);
}

/// 正多边形在方向 theta 上的边界半径（circumradius=1）。
///
/// 公式：r = cos(pi/n) / cos(delta)
/// 其中 delta 是 theta 在单个扇区内相对边法线的偏移（范围 [-pi/n, pi/n]）。
double _regularPolygonRadius(double theta, int sides) {
  final n = sides;
  final sector = 2 * math.pi / n;

  // 将 theta 归一到 [0, sector)，然后平移到 [-sector/2, sector/2]。
  final a = _positiveMod(theta, sector);
  final delta = a - sector * 0.5;

  final inRadius = math.cos(math.pi / n);
  final denom = math.cos(delta).abs();
  // denom 理论上不会为 0（delta ∈ (-pi/2, pi/2)），但做保护。
  return denom < 1e-6 ? 1.0 : (inRadius / denom);
}

/// “柔和星形”的半径函数：使用 cos 波形在 inner/out 之间平滑切换。
///
/// - sharpness 越大，尖角越明显。
/// - 该函数是工程近似（非严格几何 star polygon），但能稳定 morph 且性能友好。
double _softStarRadius(double theta, int sides, double innerRadius, double sharpness) {
  final n = sides;
  final phase = (math.cos(n * theta) + 1.0) * 0.5; // 0..1
  final shaped = math.pow(phase, sharpness).toDouble();
  return innerRadius + (1.0 - innerRadius) * shaped;
}

/// 椭圆（横向拉伸）在方向 theta 上的半径。
///
/// aspectRatio > 1 表示更扁的“横向椭圆”。
double _ellipseRadius(double theta, double aspectRatio) {
  final a = aspectRatio; // x 半轴
  final b = 1.0; // y 半轴

  final c = math.cos(theta);
  final s = math.sin(theta);
  final denom = math.sqrt((c * c) / (a * a) + (s * s) / (b * b));
  return denom < 1e-6 ? 1.0 : (1.0 / denom);
}

/// 超椭圆（superellipse）在方向 theta 上的半径。
///
/// 方程：(|x/a|^p + |y/b|^p)^(1/p) = 1
/// => r = 1 / ( (|cosθ|^p / a^p + |sinθ|^p / b^p)^(1/p) )
double _superellipseRadius(double theta, double exponent, double aspectRatio) {
  final p = exponent;
  final a = aspectRatio;
  final b = 1.0;

  final c = math.cos(theta).abs();
  final s = math.sin(theta).abs();

  final ap = math.pow(a, p).toDouble();
  final bp = math.pow(b, p).toDouble();

  final term = math.pow(c, p).toDouble() / ap + math.pow(s, p).toDouble() / bp;
  final denom = math.pow(term, 1.0 / p).toDouble();
  return denom < 1e-6 ? 1.0 : (1.0 / denom);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _positiveMod(double x, double m) {
  final r = x % m;
  return r < 0 ? r + m : r;
}
