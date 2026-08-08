import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme_colors.dart';

class GoogleMapEmbed extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double radius;

  const GoogleMapEmbed({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  Uri get _mapUri => Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: colors.background,
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () =>
              launchUrl(_mapUri, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Open Google Map'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.primary,
            side: BorderSide(color: colors.primary),
          ),
        ),
      ),
    );
  }
}
