import 'package:flutter/material.dart';

/// A CircleAvatar that loads an image from a network URL and falls back to a
/// placeholder widget if the image fails to load.
class SafeCircleAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color backgroundColor;
  final Widget? fallback;

  const SafeCircleAvatar({
    super.key,
    this.url,
    required this.radius,
    required this.backgroundColor,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: fallback,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: Image.network(
          url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback ?? const Icon(Icons.person),
        ),
      ),
    );
  }
}
