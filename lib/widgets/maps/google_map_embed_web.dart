// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class GoogleMapEmbed extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double radius;

  const GoogleMapEmbed({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });

  @override
  State<GoogleMapEmbed> createState() => _GoogleMapEmbedState();
}

class _GoogleMapEmbedState extends State<GoogleMapEmbed> {
  late final String _viewType;
  late final web.HTMLIFrameElement _iframe;

  @override
  void initState() {
    super.initState();
    _viewType = 'google-map-embed-${DateTime.now().microsecondsSinceEpoch}';
    _iframe = web.HTMLIFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true
      ..referrerPolicy = 'no-referrer-when-downgrade';
    _updateSource();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _iframe);
  }

  @override
  void didUpdateWidget(covariant GoogleMapEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.radius != widget.radius) {
      _updateSource();
    }
  }

  void _updateSource() {
    final zoom = widget.radius <= 75
        ? 18
        : widget.radius <= 150
            ? 17
            : widget.radius <= 300
                ? 16
                : widget.radius <= 700
                    ? 15
                    : 14;
    _iframe.src =
        'https://maps.google.com/maps?q=${widget.latitude},${widget.longitude}&z=$zoom&output=embed';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
