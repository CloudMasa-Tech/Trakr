import 'package:flutter/material.dart';
import '../../theme/app_theme_colors.dart';
import '../dashboard/attendance_dashboard_screen.dart';
import '../manager/manager_dashboard_screen.dart';
import '../admin/team_directory_screen.dart';

const Color _mmvWhite = Color(0xFFFFFFFF);

class MultiModelViewScreen extends StatefulWidget {
  final List<String> models;

  const MultiModelViewScreen({
    super.key,
    this.models = const ['dashboard', 'manager', 'directory'],
  });

  @override
  State<MultiModelViewScreen> createState() => _MultiModelViewScreenState();
}

class _MultiModelViewScreenState extends State<MultiModelViewScreen> {
  late List<bool> _selectedModels;

  @override
  void initState() {
    super.initState();
    _selectedModels = List.generate(
      widget.models.length,
      (i) => true,
    );
  }

  Widget _buildModelPanel(String model) {
    switch (model.toLowerCase()) {
      case 'dashboard':
      case 'admin':
        return const AttendanceDashboardScreen();
      case 'manager':
        return ManagerDashboardScreen(onLogout: () async {});
      case 'directory':
      case 'staff':
      case 'engineer':
        return const TeamDirectoryScreen();
      default:
        return Center(
          child: Text('Unknown model: $model'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleModels = widget.models
        .asMap()
        .entries
        .where((e) => _selectedModels[e.key])
        .map((e) => e.value)
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppThemeColors.darkCanvas,
        elevation: 0,
        title: const Text('Multi-Model View'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.models.length, (i) {
                  final model = widget.models[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(
                        model[0].toUpperCase() + model.substring(1),
                      ),
                      selected: _selectedModels[i],
                      onSelected: (selected) {
                        setState(() => _selectedModels[i] = selected);
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
      body: AppBackground(
        forceDark: true,
        child: visibleModels.isEmpty
            ? const Center(
                child: Text(
                  'Select at least one model to view',
                  style: TextStyle(color: AppThemeColors.darkMuted),
                ),
              )
            : Row(
                children: List.generate(
                  visibleModels.length,
                  (i) => Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: i < visibleModels.length - 1
                            ? Border(
                                right: BorderSide(
                                  color: _mmvWhite.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                              )
                            : null,
                      ),
                      child: _buildModelPanel(visibleModels[i]),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
