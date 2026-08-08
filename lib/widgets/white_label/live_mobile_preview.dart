// lib/widgets/white_label/live_mobile_preview.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/white_label_model.dart';

/// Phone-mockup preview of the white-labelled app. The device chrome and the
/// previewed app screen are fixed brand visuals (a simulated phone), so their
/// colors are centralized constants rather than theme tokens.
const _phoneFrame = Color(0xFF1A2D5A);
const _phoneChrome = Color(0xFF0D1B3E);
const _phoneSurface = Color(0xFFFFFFFF);
const _phoneTextMuted = Color(0x8A000000);
const _phoneNavBg = Color(0xFFF5F5F5);
const _phoneNavInactive = Color(0xFF9E9E9E);
const _phoneShadow = Color(0x14000000);

class LiveMobilePreview extends StatelessWidget {
  final WhiteLabelModel model;
  final Uint8List? logoBytes;

  const LiveMobilePreview({
    super.key,
    required this.model,
    this.logoBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 220,
        height: 420,
        decoration: BoxDecoration(
          color: _phoneFrame,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: _phoneChrome, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: model.primaryColor.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 4),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Column(
            children: [
              // Status bar
              Container(
                color: _phoneChrome,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('9:41 AM',
                        style: TextStyle(color: _phoneSurface, fontSize: 11)),
                    Row(
                      children: [
                        Icon(Icons.signal_cellular_alt,
                            color: _phoneSurface, size: 12),
                        SizedBox(width: 4),
                        Icon(Icons.wifi, color: _phoneSurface, size: 12),
                        SizedBox(width: 4),
                        Icon(Icons.battery_full,
                            color: _phoneSurface, size: 12),
                      ],
                    ),
                  ],
                ),
              ),

              // App header
              Container(
                color: _phoneChrome,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Logo avatar
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: model.primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _buildLogoWidget(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        model.displayCompanyName,
                        style: const TextStyle(
                            color: _phoneSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: Container(
                  color: _phoneSurface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // QR Code area
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _phoneSurface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: _phoneShadow, blurRadius: 8),
                          ],
                        ),
                        child: QrImageView(
                          data: model.customDomain.isEmpty
                              ? 'https://attendance.app'
                              : 'https://${model.customDomain}',
                          version: QrVersions.auto,
                          size: 100,
                          eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square, color: _phoneChrome),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: _phoneChrome),
                          backgroundColor: _phoneSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Scan to check in',
                          style:
                              TextStyle(color: _phoneTextMuted, fontSize: 11)),
                      const SizedBox(height: 16),

                      // Check In Now button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: model.primaryColor,
                            disabledBackgroundColor: model.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Check In Now',
                              style: TextStyle(
                                  color: _phoneSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Mark Absent button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: model.primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text('Mark Absent',
                              style: TextStyle(
                                  color: model.primaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom navigation
              Container(
                color: _phoneNavBg,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navItem(Icons.home, 'Home', model.primaryColor, true),
                    _navItem(
                        Icons.history, 'History', _phoneNavInactive, false),
                    _navItem(
                        Icons.settings, 'Settings', _phoneNavInactive, false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoWidget() {
    if (logoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          logoBytes!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultLogo();
          },
        ),
      );
    }

    if ((model.logoUrl ?? '').isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _logoImage(model.logoUrl!),
      );
    }

    return _buildDefaultLogo();
  }

  Widget _logoImage(String url) {
    Widget fallback() => _buildDefaultLogo();
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return fallback();
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback(),
        );
      } catch (_) {
        return fallback();
      }
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback(),
    );
  }

  Widget _buildDefaultLogo() {
    return Center(
      child: Text(
        model.displayCompanyName[0].toUpperCase(),
        style: const TextStyle(
            color: _phoneSurface, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, Color color, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
