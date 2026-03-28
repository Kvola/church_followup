import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/followup_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int? _selectedEvangelistId;
  Map<String, dynamic>? _reportData;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FollowupProvider>().loadEvangelists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FollowupProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport de suivi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Evangelist selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Sélectionner un évangéliste'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline),
                      hintText: 'Choisir un évangéliste',
                    ),
                    items: provider.evangelists
                        .where((e) => e['id'] is int)
                        .map((e) {
                      return DropdownMenuItem<int>(
                        value: e['id'] as int,
                        child: Text(e['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedEvangelistId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedEvangelistId != null && !_loading ? _generateReport : null,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.analytics_outlined),
                      label: Text(_loading ? 'Chargement...' : 'Générer le rapport'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ErrorState(message: _error!, onRetry: _generateReport),
            ),

          if (_reportData != null) ...[
            const SizedBox(height: 24),
            _buildReportContent(theme),
          ],
        ],
      ),
    );
  }

  Future<void> _generateReport() async {
    if (_selectedEvangelistId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orgProvider = context.read<OrganizationProvider>();
      final result = await orgProvider.getFollowupReport(_selectedEvangelistId!);
      if (result.isEmpty || result.keys.every((k) => result[k] == 0 || result[k] == '' || result[k] == null)) {
        setState(() {
          _error = 'Aucune donnée disponible pour cet évangéliste';
          _reportData = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _reportData = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildReportContent(ThemeData theme) {
    final data = _reportData!;
    final evangelistName = data['evangelist_name'] ?? '';
    final totalFollowups = data['total_followups'] ?? 0;
    final activeFollowups = data['active_followups'] ?? 0;
    final integratedCount = data['integrated_count'] ?? 0;
    final abandonedCount = data['abandoned_count'] ?? 0;
    final extendedCount = data['extended_count'] ?? 0;
    final integrationRate = data['integration_rate'] ?? 0.0;
    final followups = data['followups'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Card(
          color: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rapport — $evangelistName',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('Total suivis: $totalFollowups', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Stats grid
        Row(
          children: [
            Expanded(child: _statTile('Actifs', '$activeFollowups', AppColors.inProgress)),
            const SizedBox(width: 10),
            Expanded(child: _statTile('Intégrés', '$integratedCount', AppColors.integrated)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statTile('Prolongés', '$extendedCount', AppColors.extended)),
            const SizedBox(width: 10),
            Expanded(child: _statTile('Abandonnés', '$abandonedCount', AppColors.abandoned)),
          ],
        ),
        const SizedBox(height: 10),

        // Integration rate
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Taux d'intégration", style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        '${(integrationRate is num ? integrationRate : 0.0).toStringAsFixed(1)}%',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: (integrationRate is num ? integrationRate / 100 : 0.0).clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Followups list
        if (followups.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(title: 'Détails des suivis (${followups.length})'),
          const SizedBox(height: 8),
          ...followups.map((f) {
            final memberName = f['member_name'] ?? '';
            final state = f['state'] ?? '';
            final weeksDone = f['weeks_done'] ?? 0;
            final weeksDuration = f['weeks_duration'] ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(memberName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Semaine $weeksDone / $weeksDuration'),
                trailing: StateBadge(state: state),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
