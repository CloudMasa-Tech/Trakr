import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../services/geo_fence_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/responsive.dart';

// Fixed-brand palette for the geo-tag screen (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _geoGreen = Color(0xFF00C896);
const Color _geoPrimary = Color(0xFF0F766E);
const Color _geoAmber = Color(0xFFFFA400);
const Color _geoSlate = Color(0xFF4B587C);
const Color _geoTurquoise = Color(0xFF4ECDC4);
const Color _geoRed = Color(0xFFE53935);
const Color _geoRed600 = Color(0xFFE53935);
const Color _geoActionMiddle = Color(0xFF155E75);
const Color _geoSuccess = Color(0xFF00A96B);
const Color _geoWhite = Color(0xFFFFFFFF);

class GeoTagScreen extends StatefulWidget {
  const GeoTagScreen({super.key});

  @override
  State<GeoTagScreen> createState() => _GeoTagScreenState();
}

class _GeoTagScreenState extends State<GeoTagScreen> {
  static const double _defaultOfficeRadius = 140;

  final _db = FirebaseContextProvider.current.firestore;
  final _geoFenceService = GeoFenceService();
  final _mapController = MapController();

  final _locationSearchCtrl = TextEditingController();
  final _latCtrl = TextEditingController(text: '13.0827');
  final _lngCtrl = TextEditingController(text: '80.2707');
  final _radCtrl =
      TextEditingController(text: _defaultOfficeRadius.toStringAsFixed(0));
  final _checkInStartCtrl = TextEditingController(text: '08:30 AM');
  final _checkInEndCtrl = TextEditingController(text: '10:30 AM');
  final _checkOutStartCtrl = TextEditingController(text: '05:00 PM');
  final _checkOutEndCtrl = TextEditingController(text: '07:30 PM');
  double _lat = 13.0827, _lng = 80.2707, _radius = _defaultOfficeRadius;
  int _verifiedCount = 0;
  StreamSubscription? _sub;
  bool _isChangingLocation = false;
  bool _syncingLocationFields = false;
  bool _isSearchingLocation = false;
  double? _suggestedRadius;
  String? _selectedLocationName;

  @override
  void initState() {
    super.initState();
    _latCtrl.addListener(_applyLocationFromFields);
    _lngCtrl.addListener(_applyLocationFromFields);
    _radCtrl.addListener(_applyRadiusFromField);
    _loadConfig();
    _listenVerified();
  }

  Future<void> _loadConfig() async {
    final doc = await _db.collection('geo_config').doc('default').get();
    if (doc.exists) {
      final d = doc.data()!;
      setState(() {
        _lat = (d['latitude'] as num?)?.toDouble() ?? 13.0827;
        _lng = (d['longitude'] as num?)?.toDouble() ?? 80.2707;
        _radius = (d['radius'] as num?)?.toDouble() ?? _defaultOfficeRadius;
        _latCtrl.text = _lat.toString();
        _lngCtrl.text = _lng.toString();
        _radCtrl.text = _radius.toStringAsFixed(0);
        _checkInStartCtrl.text =
            _normalizeTimeText(d['checkInStart']?.toString(), '08:30 AM');
        _checkInEndCtrl.text =
            _normalizeTimeText(d['checkInEnd']?.toString(), '10:30 AM');
        _checkOutStartCtrl.text =
            _normalizeTimeText(d['checkOutStart']?.toString(), '05:00 PM');
        _checkOutEndCtrl.text =
            _normalizeTimeText(d['checkOutEnd']?.toString(), '07:30 PM');
      });
      _moveMapToOffice();
    }
  }

  LatLng get _officePoint => LatLng(_lat, _lng);

  void _moveMapToOffice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(
          _officePoint,
          GeoFenceService.zoomForRadius(_radius),
        );
      } catch (_) {
        // The map may not be attached during the very first frame.
      }
    });
  }

  void _setLocationFromMapTap(LatLng point) {
    if (!_isChangingLocation) return;
    _syncingLocationFields = true;
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _suggestedRadius = _defaultOfficeRadius;
      _selectedLocationName = 'Map selected location';
      _latCtrl.text = _lat.toStringAsFixed(12);
      _lngCtrl.text = _lng.toStringAsFixed(12);
    });
    _syncingLocationFields = false;
    _moveMapToOffice();
  }

  void _applyLocationFromFields() {
    if (!_isChangingLocation) return;
    if (_syncingLocationFields) return;
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) return;
    if (!GeoFenceService.isValidLatitude(lat) ||
        !GeoFenceService.isValidLongitude(lng)) {
      return;
    }

    setState(() {
      _lat = lat;
      _lng = lng;
    });
    _moveMapToOffice();
  }

  void _applyRadiusFromField() {
    if (!_isChangingLocation) return;
    final radius = double.tryParse(_radCtrl.text.trim());
    if (radius == null || !GeoFenceService.isValidRadius(radius)) return;
    setState(() => _radius = radius);
  }

  Future<void> _searchOfficeLocation() async {
    final query = _locationSearchCtrl.text.trim();
    if (query.isEmpty) {
      _showError('Enter an office location to search.');
      return;
    }

    try {
      setState(() => _isSearchingLocation = true);
      final result = await _geoFenceService.searchLocation(query);
      if (!mounted) return;

      if (result == null) {
        _showError('No matching location found. Try a more specific address.');
        setState(() => _isSearchingLocation = false);
        return;
      }

      _syncingLocationFields = true;
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        _radius = result.suggestedRadiusMetres;
        _suggestedRadius = result.suggestedRadiusMetres;
        _selectedLocationName = result.displayName;
        _latCtrl.text = _lat.toStringAsFixed(12);
        _lngCtrl.text = _lng.toStringAsFixed(12);
        _radCtrl.text = result.suggestedRadiusMetres.toStringAsFixed(0);
        _locationSearchCtrl.text = result.displayName;
        _isChangingLocation = true;
        _isSearchingLocation = false;
      });
      _syncingLocationFields = false;
      _moveMapToOffice();
      _showSuccess(
        'Location found. Latitude, longitude, and suggested ${result.suggestedRadiusMetres.toStringAsFixed(0)}m radius set.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSearchingLocation = false);
      _showError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _listenVerified() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _sub = _db
        .collection('attendance')
        .where('dateKey', isEqualTo: today)
        .where('geoTagRequired', isEqualTo: true)
        .where('status', whereIn: ['present', 'late'])
        .snapshots()
        .listen((s) {
          if (mounted) setState(() => _verifiedCount = s.docs.length);
        });
  }

  /// Validate time format (HH:MM AM/PM)
  bool _isValidTimeFormat(String time) {
    final regex = RegExp(r'^\d{1,2}:\d{2}\s(?:AM|PM)$', caseSensitive: false);
    return regex.hasMatch(time.trim()) && _parseTimeOfDay(time) != null;
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(value.trim());
    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;

    final period = match.group(3)!.toUpperCase();
    final hour24 = period == 'AM'
        ? (hour == 12 ? 0 : hour)
        : (hour == 12 ? 12 : hour + 12);
    return TimeOfDay(hour: hour24, minute: minute);
  }

  String _formatIndianTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _normalizeTimeText(String? value, String fallback) {
    final parsed = _parseTimeOfDay(value) ?? _parseTimeOfDay(fallback)!;
    return _formatIndianTime(parsed);
  }

  bool _isBefore(TimeOfDay start, TimeOfDay end) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return startMinutes < endMinutes;
  }

  Future<void> _pickTime(
    TextEditingController controller,
    String fallback,
  ) async {
    final initial =
        _parseTimeOfDay(controller.text) ?? _parseTimeOfDay(fallback)!;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    setState(() => controller.text = _formatIndianTime(picked));
  }

  /// Show validation error
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: _geoRed600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Show success message
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: _geoGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _save() async {
    try {
      // Validate location inputs
      final lat = double.tryParse(_latCtrl.text);
      final lng = double.tryParse(_lngCtrl.text);
      final rad = double.tryParse(_radCtrl.text);

      if (lat == null || lng == null || rad == null) {
        _showError(
            'Please enter valid numbers for latitude, longitude, and radius');
        return;
      }

      if (!GeoFenceService.isValidLatitude(lat)) {
        _showError('Latitude must be between -90 and 90');
        return;
      }

      if (!GeoFenceService.isValidLongitude(lng)) {
        _showError('Longitude must be between -180 and 180');
        return;
      }

      if (!GeoFenceService.isValidRadius(rad)) {
        _showError('Radius must be between 10 and 10000 meters');
        return;
      }

      final checkInStart =
          _normalizeTimeText(_checkInStartCtrl.text, '08:30 AM');
      final checkInEnd = _normalizeTimeText(_checkInEndCtrl.text, '10:30 AM');
      final checkOutStart =
          _normalizeTimeText(_checkOutStartCtrl.text, '05:00 PM');
      final checkOutEnd = _normalizeTimeText(_checkOutEndCtrl.text, '07:30 PM');

      // Validate time formats
      if (!_isValidTimeFormat(checkInStart)) {
        _showError('Check-In Start time must be in format HH:MM AM/PM');
        return;
      }
      if (!_isValidTimeFormat(checkInEnd)) {
        _showError('Check-In End time must be in format HH:MM AM/PM');
        return;
      }
      if (!_isValidTimeFormat(checkOutStart)) {
        _showError('Check-Out Start time must be in format HH:MM AM/PM');
        return;
      }
      if (!_isValidTimeFormat(checkOutEnd)) {
        _showError('Check-Out End time must be in format HH:MM AM/PM');
        return;
      }

      final parsedCheckInStart = _parseTimeOfDay(checkInStart)!;
      final parsedCheckInEnd = _parseTimeOfDay(checkInEnd)!;
      final parsedCheckOutStart = _parseTimeOfDay(checkOutStart)!;
      final parsedCheckOutEnd = _parseTimeOfDay(checkOutEnd)!;

      if (!_isBefore(parsedCheckInStart, parsedCheckInEnd)) {
        _showError('Check-In Start time must be before Check-In End time.');
        return;
      }
      if (!_isBefore(parsedCheckOutStart, parsedCheckOutEnd)) {
        _showError('Check-Out Start time must be before Check-Out End time.');
        return;
      }

      // Save all configuration to Firestore. Keep the legacy offices document
      // mirrored so every scanner path validates against the same location.
      final configPayload = {
        'latitude': lat,
        'longitude': lng,
        'radius': rad,
        'geoFenceRadius': rad,
        'checkInStart': checkInStart,
        'checkInEnd': checkInEnd,
        'checkOutStart': checkOutStart,
        'checkOutEnd': checkOutEnd,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('geo_config').doc('default').set(configPayload);
      await _db.collection('offices').doc('default').set(
            configPayload,
            SetOptions(merge: true),
          );

      setState(() {
        _lat = lat;
        _lng = lng;
        _radius = rad;
        _checkInStartCtrl.text = checkInStart;
        _checkInEndCtrl.text = checkInEnd;
        _checkOutStartCtrl.text = checkOutStart;
        _checkOutEndCtrl.text = checkOutEnd;
        _isChangingLocation = false;
      });

      _showSuccess('Configuration and time settings saved successfully!');
    } catch (e) {
      _showError('Error saving configuration: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mapController.dispose();
    _locationSearchCtrl.dispose();
    _latCtrl.removeListener(_applyLocationFromFields);
    _lngCtrl.removeListener(_applyLocationFromFields);
    _radCtrl.removeListener(_applyRadiusFromField);
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radCtrl.dispose();
    _checkInStartCtrl.dispose();
    _checkInEndCtrl.dispose();
    _checkOutStartCtrl.dispose();
    _checkOutEndCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveBreakpoints.isMobile(context) ? 16.0 : 20.0;
    return AppBackground(
      forceDark: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Description box ─────────────────────────────────────────
            _descBox(),
            const SizedBox(height: 20),

            // ── Live map card ────────────────────────────────────────────
            _liveMapCard(),
            const SizedBox(height: 20),

            // ── Config + Time Settings ────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 900;
                if (stacked) {
                  return Column(
                    children: [
                      _configCard(),
                      const SizedBox(height: 16),
                      _timeSettingsCard(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _configCard()),
                    const SizedBox(width: 16),
                    Expanded(child: _timeSettingsCard()),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Description ─────────────────────────────────────────────────────────
  Widget _descBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: const Text(
        'Geo-fencing ensures employees are physically present at the office when '
        'scanning the QR code. The system validates GPS coordinates against the '
        'configured office radius. Absence marking bypasses geo-verification entirely.',
        style: TextStyle(
          color: AppThemeColors.darkMuted,
          fontSize: 13,
          height: 1.65,
        ),
      ),
    );
  }

  // ── Live map card ────────────────────────────────────────────────────────
  Widget _liveMapCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Office Geo-Fence — Live View',
                      style: TextStyle(
                        color: AppThemeColors.darkText,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _geoGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _geoGreen.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '$_verifiedCount verified',
                        style: const TextStyle(
                          color: _geoGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationSearchCtrl,
                  onSubmitted: (_) => _searchOfficeLocation(),
                  cursorColor: _geoGreen,
                  style: const TextStyle(
                    color: AppThemeColors.darkText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search office location...',
                    hintStyle: const TextStyle(
                      color: AppThemeColors.darkMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _geoGreen,
                    ),
                    suffixIcon: _isSearchingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _geoGreen,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Search location',
                            onPressed: _isSearchingLocation
                                ? null
                                : _searchOfficeLocation,
                            icon: const Icon(
                              Icons.my_location_rounded,
                              color: _geoGreen,
                            ),
                          ),
                    filled: true,
                    fillColor: AppThemeColors.darkCanvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppThemeColors.darkBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppThemeColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _geoGreen,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(0),
            ),
            child: SizedBox(
              height: 300,
              width: double.infinity,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _officePoint,
                  initialZoom: GeoFenceService.zoomForRadius(_radius),
                  minZoom: 3,
                  maxZoom: 19,
                  onTap: (_, point) => _setLocationFromMapTap(point),
                  interactionOptions: InteractionOptions(
                    flags: _isChangingLocation
                        ? InteractiveFlag.all
                        : InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.yourcompany.qrattendance',
                    retinaMode: RetinaMode.isHighDensity(context),
                    tileProvider: CancellableNetworkTileProvider(),
                  ),
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: _officePoint,
                        radius: _radius,
                        useRadiusInMeter: true,
                        color: _geoPrimary.withValues(alpha: 0.18),
                        borderColor: _geoPrimary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _officePoint,
                        width: 54,
                        height: 54,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_pin,
                          color: _geoRed,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!_isChangingLocation)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              color: AppThemeColors.darkCanvas,
              child: const Text(
                'Location is fixed. Use Change Location to edit the map and coordinates.',
                style: TextStyle(
                  color: AppThemeColors.darkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Footer label — matches "Office: 13.0827°N, 80.2707°E · Radius: 100m"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: AppThemeColors.backgroundDark,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: _geoGreen, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  'Office: ${_lat.toStringAsFixed(4)}°N, '
                  '${_lng.toStringAsFixed(4)}°E  ·  '
                  'Radius: ${_radius.toStringAsFixed(0)}m',
                  style: const TextStyle(
                    color: AppThemeColors.darkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Config card ──────────────────────────────────────────────────────────
  Widget _configCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Geo-Fence Configuration',
            style: TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _field('OFFICE LATITUDE', _latCtrl, readOnly: !_isChangingLocation),
          const SizedBox(height: 14),
          _field('OFFICE LONGITUDE', _lngCtrl, readOnly: !_isChangingLocation),
          const SizedBox(height: 14),
          _field('ALLOWED RADIUS (METERS)', _radCtrl,
              readOnly: !_isChangingLocation),
          if (_suggestedRadius != null) ...[
            const SizedBox(height: 12),
            _radiusSuggestionPanel(),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _geoActionMiddle,
                foregroundColor: _geoWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Save Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isChangingLocation
                  ? null
                  : () {
                      setState(() => _isChangingLocation = true);
                      _moveMapToOffice();
                    },
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
              label: Text(
                _isChangingLocation
                    ? 'Location Editing Enabled'
                    : 'Change Location',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _geoGreen,
                disabledForegroundColor: AppThemeColors.darkMuted,
                side: BorderSide(
                  color: _isChangingLocation
                      ? AppThemeColors.darkBorder
                      : _geoGreen,
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: _geoSlate,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            )),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(
            color: AppThemeColors.darkText,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppThemeColors.darkCanvas,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppThemeColors.darkBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppThemeColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _geoPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _radiusSuggestionPanel() {
    final suggested = _suggestedRadius ?? _defaultOfficeRadius;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _geoPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _geoPrimary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assistant_direction_rounded,
                color: _geoGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Suggested radius: ${suggested.toStringAsFixed(0)}m',
                  style: const TextStyle(
                    color: _geoGreen,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: !_isChangingLocation
                    ? null
                    : () {
                        setState(() {
                          _radius = suggested;
                          _radCtrl.text = suggested.toStringAsFixed(0);
                        });
                        _moveMapToOffice();
                      },
                child: const Text('Apply'),
              ),
            ],
          ),
          if (_selectedLocationName?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              _selectedLocationName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppThemeColors.darkMuted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'You can keep this suggestion or type your own radius manually.',
            style: TextStyle(
              color: AppThemeColors.darkMuted,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ── Check-In / Check-Out Time Settings card ─────────────────────────────
  Widget _timePickerField({
    required String label,
    required String fallback,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppThemeColors.darkMuted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pickTime(controller, fallback),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: AppThemeColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppThemeColors.darkBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  color: AppThemeColors.darkMuted,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _normalizeTimeText(controller.text, fallback),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppThemeColors.darkText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Check-In / Check-Out Time Settings',
            style: TextStyle(
                color: AppThemeColors.darkText,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Help Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _geoTurquoise.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _geoTurquoise.withValues(alpha: 0.2), width: 1),
            ),
            child: const Text(
              '💡 Tip: Configure the times when employees can check-in/out. '
              'Late arrivals after Check-In End time will be marked accordingly. '
              'These times are controlled by Admin and applied to all staff.',
              style: TextStyle(
                color: _geoSlate,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Check-In Time Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _geoGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _geoGreen.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.access_time, color: _geoGreen, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Check-In Time',
                      style: TextStyle(
                        color: _geoGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _timePickerField(
                        label: 'Start Time',
                        fallback: '08:30 AM',
                        controller: _checkInStartCtrl,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timePickerField(
                        label: 'End Time',
                        fallback: '10:30 AM',
                        controller: _checkInEndCtrl,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Check-Out Time Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _geoAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _geoAmber.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.exit_to_app, color: _geoAmber, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Check-Out Time',
                      style: TextStyle(
                        color: _geoAmber,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _timePickerField(
                        label: 'Start Time',
                        fallback: '05:00 PM',
                        controller: _checkOutStartCtrl,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timePickerField(
                        label: 'End Time',
                        fallback: '07:30 PM',
                        controller: _checkOutEndCtrl,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _geoSuccess,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Save All Settings',
                style: TextStyle(
                  color: _geoWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
