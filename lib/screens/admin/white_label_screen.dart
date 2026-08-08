// lib/screens/admin/white_label_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/white_label_model.dart';
import '../../providers/white_label_provider.dart';
import '../../services/white_label_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/white_label/live_mobile_preview.dart';

// Fixed-brand dark palette for the white-label (branding) editor screen.
// Intentional exception: file-scoped brand constants.
const Color _wlNavy = Color(0xFF243660);
const Color _wlIndigo = Color(0xFF6C63FF);
const Color _wlNavyDeep = Color(0xFF1A2D5A);
const Color _wlWhite = Color(0xFFFFFFFF);
const Color _wlWhite60 = Color(0x99FFFFFF);
const Color _wlWhite38 = Color(0x61FFFFFF);
const Color _wlWhite70 = Color(0xB3FFFFFF);
const Color _wlWhite24 = Color(0x3DFFFFFF);
const Color _wlWhite54 = Color(0x8AFFFFFF);

class WhiteLabelScreen extends StatefulWidget {
  const WhiteLabelScreen({super.key});

  @override
  State<WhiteLabelScreen> createState() => _WhiteLabelScreenState();
}

class _WhiteLabelScreenState extends State<WhiteLabelScreen> {
  final _companyNameCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _service = WhiteLabelService();

  String _selectedColorHex = '6C63FF';
  Uint8List? _logoBytes;
  bool _saving = false;

  final List<String> _presetColors = [
    '6C63FF',
    'E91E8C',
    'FFC107',
    '4CAF50',
    'F44336',
    '2196F3',
    '9C27B0',
    'FF9800',
  ];

  @override
  void initState() {
    super.initState();
    final config = context.read<WhiteLabelProvider>().config;
    _companyNameCtrl.text = config.companyName;
    _domainCtrl.text = config.customDomain;
    _emailCtrl.text = config.supportEmail;
    _selectedColorHex = config.primaryColorHex;
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _domainCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  WhiteLabelModel get _currentModel => WhiteLabelModel(
        companyName: _companyNameCtrl.text.trim().isEmpty
            ? 'QR Attendances'
            : _companyNameCtrl.text.trim(),
        primaryColorHex: _selectedColorHex,
        customDomain: _domainCtrl.text.trim(),
        supportEmail: _emailCtrl.text.trim(),
        logoUrl: context.read<WhiteLabelProvider>().config.logoUrl,
      );

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _logoBytes = bytes);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var uploadedUrl = context.read<WhiteLabelProvider>().config.logoUrl;
      if (_logoBytes != null) {
        uploadedUrl = await _service.uploadLogo(
          _logoBytes!,
        );
      }
      if (!mounted) return;
      final model = _currentModel.copyWith(logoUrl: uploadedUrl);
      await context.read<WhiteLabelProvider>().updateConfig(model);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('White label settings saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('White Label Setup',
                style: TextStyle(
                    color: _wlWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text('Customize branding for dedicated deployments',
                style: TextStyle(color: _wlWhite60, fontSize: 12)),
          ],
        ),
        actions: isMobile
            ? null
            : [
                IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: _wlWhite),
                    onPressed: () {}),
                IconButton(
                    icon: const Icon(Icons.settings_outlined, color: _wlWhite),
                    onPressed: () {}),
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: _wlIndigo,
                  child: Text('AD',
                      style: TextStyle(color: _wlWhite, fontSize: 12)),
                ),
                const SizedBox(width: 12),
              ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Full white-label customization for dedicated customer deployments. '
              'Each customer gets their own branding, domain, database instance, and mobile app theme.',
              style: TextStyle(color: _wlWhite70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildConfigCard()),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _buildPreviewSection(),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildConfigCard(),
                        const SizedBox(height: 24),
                        _buildPreviewSection(),
                      ],
                    );
            }),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentModel.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: _wlWhite, strokeWidth: 2),
                      )
                    : const Text('Save White Label Settings',
                        style: TextStyle(
                            color: _wlWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _wlNavyDeep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Brand Configuration',
              style: TextStyle(
                  color: _wlWhite, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildLabel('COMPANY NAME'),
          _buildTextField(_companyNameCtrl, 'Acme Corp'),
          const SizedBox(height: 16),
          _buildLabel('PRIMARY BRAND COLOR'),
          const SizedBox(height: 8),
          _buildColorPicker(),
          const SizedBox(height: 16),
          _buildLabel('CUSTOM DOMAIN'),
          _buildTextField(_domainCtrl, 'attendance.acmecorp.com'),
          const SizedBox(height: 16),
          _buildLabel('SUPPORT EMAIL'),
          _buildTextField(_emailCtrl, 'hr@acmecorp.com'),
          const SizedBox(height: 16),
          _buildLabel('LOGO UPLOAD'),
          _buildLogoUpload(),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              color: _wlWhite60, fontSize: 11, letterSpacing: 1)),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: _wlWhite),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _wlWhite38),
        filled: true,
        fillColor: _wlNavy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presetColors.map((hex) {
        final color = Color(int.parse('FF$hex', radix: 16));
        final selected = hex == _selectedColorHex;
        return GestureDetector(
          onTap: () => setState(() => _selectedColorHex = hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8),
              border: selected ? Border.all(color: _wlWhite, width: 2.5) : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.6), blurRadius: 8)
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLogoUpload() {
    return GestureDetector(
      onTap: _pickLogo,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _wlWhite24, style: BorderStyle.solid),
          color: _wlNavy,
        ),
        child: _logoBytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_logoBytes!, fit: BoxFit.contain))
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      color: _wlWhite38, size: 28),
                  SizedBox(height: 6),
                  Text('Drag & drop logo or click to upload',
                      style: TextStyle(color: _wlWhite54, fontSize: 12)),
                  Text('SVG, PNG · Max 2MB',
                      style: TextStyle(color: _wlWhite38, fontSize: 10)),
                ],
              ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      children: [
        const Text('LIVE MOBILE PREVIEW',
            style:
                TextStyle(color: _wlWhite60, fontSize: 12, letterSpacing: 2)),
        const SizedBox(height: 16),
        LiveMobilePreview(model: _currentModel, logoBytes: _logoBytes),
      ],
    );
  }
}
