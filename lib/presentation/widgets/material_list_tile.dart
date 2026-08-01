import 'package:flutter/material.dart';

/// A ListTile wrapper that always provides its own Material ancestor so
/// ripple/ink effects remain visible even when placed inside a decorated
/// container or other visual surface.
class MaterialListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;
  final BorderRadiusGeometry? borderRadius;
  final ShapeBorder? shape;
  final Color? tileColor;
  final bool enabled;
  final Clip clipBehavior;

  const MaterialListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.onTap,
    this.borderRadius,
    this.shape,
    this.tileColor,
    this.enabled = true,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tileColor ?? Colors.transparent,
      shape: shape ??
          RoundedRectangleBorder(
            borderRadius: borderRadius ?? BorderRadius.circular(16),
          ),
      clipBehavior: clipBehavior,
      child: ListTile(
        enabled: enabled,
        contentPadding: contentPadding,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
