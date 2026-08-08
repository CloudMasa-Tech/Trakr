import 'package:flutter/material.dart';

import '../../control_plane/models/workspace.dart';
import '../../control_plane/services/workspace_registry_service.dart';

import 'client_onboarding_add_screen.dart';
import 'portal_widgets.dart';

class ClientOnboardingModule extends StatefulWidget {
  const ClientOnboardingModule({super.key});

  @override
  State<ClientOnboardingModule> createState() => _ClientOnboardingModuleState();
}

class _ClientOnboardingModuleState extends State<ClientOnboardingModule> {
  final _registry = WorkspaceRegistryService();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openAddCompany() async {
    final created = await ClientOnboardingAddScreen.show(context);
    if (created && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 40 : 16,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: StreamBuilder<List<Workspace>>(
            stream: _registry.streamWorkspaces(),
            builder: (context, snapshot) {
              final workspaces = snapshot.data ?? const <Workspace>[];
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(workspaces, loading),
                  const SizedBox(height: 20),
                  _buildTable(workspaces, loading),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<Workspace> companies, bool loading) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Client onboarding',
                style: TextStyle(
                  color: kCoLabel,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Create companies with their first Company Admin, and manage '
                'their workspace lifecycle.',
                style: TextStyle(color: kCoSubtle, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _openAddCompany,
          style: FilledButton.styleFrom(
            backgroundColor: kCoAccent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add_business_rounded, size: 18),
          label: const Text('Add Company'),
        ),
      ],
    );
  }

  Widget _buildTable(List<Workspace> workspaces, bool loading) {
    // Omitting table here as it's fully managed in Workspaces tab now.
    return const SizedBox();
  }
}
