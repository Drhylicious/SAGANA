import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebSafeBlurContainer extends StatelessWidget {
  const WebSafeBlurContainer({
    super.key,
    required this.child,
    this.padding,
    this.decoration,
    this.blurSigma = 20,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;
  final double blurSigma;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (kIsWeb) {
      return ClipRect(clipBehavior: clipBehavior, child: body);
    }

    return ClipRect(
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: body,
      ),
    );
  }
}
