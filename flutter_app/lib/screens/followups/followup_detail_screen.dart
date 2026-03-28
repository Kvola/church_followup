import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/followup_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class FollowupDetailScreen extends StatefulWidget {
  final int followupId;
  const FollowupDetailScreen({super.key, required this.followupId});

  @override
  State<FollowupDetailScreen> createState() => _FollowupDetailScreenState();
}

class _FollowupDetailScreenState extends State<FollowupDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FollowupProvider>().loadDetail(widget.followupId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FollowupProvider>();
    final data = provider.currentDetail;

    return Scaffold(
      appBar: AppBar(
        title: Text(data?['member_name'] ?? 'Détail du suivi'),
        actions: [
          if (data != null && data['state'] == 'in_progress')
            PopupMenuButton<String>(
              onSelected: (action) => _handleAction(action, data),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'integrate', child: _ActionRow(Icons.check_circle, 'Intégrer', AppColors.integrated)),
                const PopupMenuItem(value: 'extend', child: _ActionRow(Icons.update, 'Prolonger (+4 sem.)', AppColors.extended)),
                const PopupMenuItem(value: 'transfer', child: _ActionRow(Icons.swap_horiz, 'Transférer', AppColors.transferred)),
                const PopupMenuItem(value: 'abandon', child: _ActionRow(Icons.cancel, 'Abandonner', AppColors.abandoned)),
              ],
            ),
        ],
      ),
      body: provider.isLoading && data == null
          ? const ShimmerList(itemCount: 3)
          : provider.error != null && data == null
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadDetail(widget.followupId))
              : data == null
                  ? const EmptyState(icon: Icons.assignment_outlined, title: 'Suivi introuvable')
                  : RefreshIndicator(
                      onRefresh: () => provider.loadDetail(widget.followupId),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Header card
                          _HeaderCard(data: data),
                          const SizedBox(height: 16),

                          // Progress
                          _ProgressCard(data: data),
                          const SizedBox(height: 16),

                          // Weekly reports
                          _WeeklyReportsSection(
                            data: data,
                            onAddWeek: data['state'] == 'in_progress' ? () => _showWeekForm(data) : null,
                          ),
                        ],
                      ),
                    ),
    );
  }

  void _handleAction(String action, Map<String, dynamic> data) async {
    final provider = context.read<FollowupProvider>();

    switch (action) {
      case 'integrate':
        await _showIntegrateDialog(data);
        break;
      case 'extend':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Prolonger le suivi',
          message: 'Ajouter 4 semaines de suivi supplémentaires ?',
          confirmLabel: 'Prolonger',
          confirmColor: AppColors.extended,
        );
        if (confirmed) {
          final result = await provider.performAction(data['id'], 'extend');
          if (mounted) {
            if (result['status'] == 'success') {
              showSuccessSnackbar(context, 'Suivi prolongé');
              provider.loadDetail(widget.followupId);
            } else {
              showErrorSnackbar(context, result['message'] ?? 'Erreur');
            }
          }
        }
        break;
      case 'transfer':
        await _showTransferDialog(data);
        break;
      case 'abandon':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Abandonner le suivi',
          message: 'Êtes-vous sûr de vouloir abandonner ce suivi ?',
          confirmLabel: 'Abandonner',
          confirmColor: AppColors.abandoned,
        );
        if (confirmed) {
          final result = await provider.performAction(data['id'], 'abandon');
          if (mounted) {
            if (result['status'] == 'success') {
              showSuccessSnackbar(context, 'Suivi abandonné');
              Navigator.pop(context);
            } else {
              showErrorSnackbar(context, result['message'] ?? 'Erreur');
            }
          }
        }
        break;
    }
  }

  Future<void> _showIntegrateDialog(Map<String, dynamic> data) async {
    final orgProvider = context.read<OrganizationProvider>();
    await orgProvider.loadCells();
    await orgProvider.loadAgeGroups();

    if (!mounted) return;

    int? selectedCellId;
    int? selectedGroupId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Intégrer le membre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Cellule de prière'),
                items: orgProvider.cells
                    .where((c) => c['id'] is int)
                    .map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(AppConstants.safeStr(c['name'], '—'))))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedCellId = v),
                value: selectedCellId,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Groupe d\'âge'),
                items: orgProvider.ageGroups
                    .where((g) => g['id'] is int)
                    .map((g) => DropdownMenuItem(value: g['id'] as int, child: Text(AppConstants.safeStr(g['name'], '—'))))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedGroupId = v),
                value: selectedGroupId,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: selectedCellId != null && selectedGroupId != null ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.integrated),
              child: const Text('Intégrer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedCellId != null && selectedGroupId != null) {
      final result = await context.read<FollowupProvider>().performAction(
            data['id'],
            'integrate',
            cellId: selectedCellId,
            groupId: selectedGroupId,
          );
      if (mounted) {
        if (result['status'] == 'success') {
          showSuccessSnackbar(context, 'Membre intégré avec succès');
          Navigator.pop(context);
        } else {
          showErrorSnackbar(context, result['message'] ?? 'Erreur');
        }
      }
    }
  }

  Future<void> _showTransferDialog(Map<String, dynamic> data) async {
    final provider = context.read<FollowupProvider>();
    await provider.loadEvangelists();

    if (!mounted) return;

    int? selectedEvId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Transférer le suivi'),
          content: DropdownButtonFormField<int>(
            decoration: const InputDecoration(labelText: 'Nouvel évangéliste'),
            items: provider.evangelists
                .where((e) => e['id'] is int)
                .map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(AppConstants.safeStr(e['name'], '—'))))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedEvId = v),
            value: selectedEvId,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: selectedEvId != null ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.transferred),
              child: const Text('Transférer'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selectedEvId != null) {
      final result = await provider.performAction(data['id'], 'transfer', evangelistId: selectedEvId);
      if (mounted) {
        if (result['status'] == 'success') {
          showSuccessSnackbar(context, 'Suivi transféré');
          Navigator.pop(context);
        } else {
          showErrorSnackbar(context, result['message'] ?? 'Erreur');
        }
      }
    }
  }

  void _showWeekForm(Map<String, dynamic> data, {Map<String, dynamic>? existingWeek}) {
    final provider = context.read<FollowupProvider>();
    final isEdit = existingWeek != null;

    bool sundayAttendance = existingWeek?['sunday_attendance'] ?? false;
    bool callMade = existingWeek?['call_made'] ?? false;
    bool visitMade = existingWeek?['visit_made'] ?? false;
    String spiritualState = existingWeek?['spiritual_state'] ?? 'average';
    final noteCtrl = TextEditingController(text: existingWeek?['note'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Modifier semaine ${existingWeek['week_number']}' : 'Rapport de semaine',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Présence dimanche'),
                value: sundayAttendance,
                onChanged: (v) => setSheetState(() => sundayAttendance = v),
                secondary: Icon(Icons.church, color: sundayAttendance ? AppColors.integrated : null),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Appel effectué'),
                value: callMade,
                onChanged: (v) => setSheetState(() => callMade = v),
                secondary: Icon(Icons.phone, color: callMade ? AppColors.integrated : null),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Visite effectuée'),
                value: visitMade,
                onChanged: (v) => setSheetState(() => visitMade = v),
                secondary: Icon(Icons.home_outlined, color: visitMade ? AppColors.integrated : null),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'État spirituel'),
                value: spiritualState,
                items: AppConstants.spiritualLabels.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: AppColors.spiritualColor(e.key), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Text(e.value),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setSheetState(() => spiritualState = v ?? 'average'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optionnel)'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final weekData = <String, dynamic>{
                      'followup_id': data['id'],
                      'sunday_attendance': sundayAttendance,
                      'call_made': callMade,
                      'visit_made': visitMade,
                      'spiritual_state': spiritualState,
                      'note': noteCtrl.text,
                    };
                    if (isEdit) weekData['week_id'] = existingWeek['id'];

                    final result = await provider.saveWeek(weekData);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      if (result['status'] == 'success') {
                        showSuccessSnackbar(context, isEdit ? 'Semaine mise à jour' : 'Rapport ajouté');
                      } else {
                        showErrorSnackbar(context, result['message'] ?? 'Erreur');
                      }
                    }
                  },
                  child: Text(isEdit ? 'Mettre à jour' : 'Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ActionRow(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HeaderCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = data['state'] ?? '';
    final stateColor = AppColors.stateColor(state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: stateColor.withValues(alpha: 0.12),
                  child: Text(
                    AppConstants.initial(data['member_name']),
                    style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['member_name'] ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Évangéliste: ${data['evangelist_name'] ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                StateBadge(state: state),
              ],
            ),
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _infoCol('Durée', '${data['duration_weeks'] ?? 0} sem.', Icons.timer_outlined),
                _infoCol('Complétées', '${data['weeks_completed'] ?? 0}', Icons.check_circle_outline),
                _infoCol('Score moy.', '${(data['average_score'] ?? 0).toStringAsFixed(1)}/13', Icons.star_outline),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCol(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProgressCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final completed = (data['weeks_completed'] ?? 0) as int;
    final total = (data['duration_weeks'] ?? 1) as int;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Progression', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${(progress * 100).toInt()}%', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyReportsSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onAddWeek;

  const _WeeklyReportsSection({required this.data, this.onAddWeek});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = (data['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Rapports hebdomadaires', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (onAddWeek != null)
              FilledButton.tonalIcon(
                onPressed: onAddWeek,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 36),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (weeks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Aucun rapport de semaine',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          ...weeks.map((week) => _WeekCard(week: week)),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  final Map<String, dynamic> week;
  const _WeekCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = (week['score'] ?? 0).toDouble();
    final spiritual = week['spiritual_state'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ScoreIndicator(score: score, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semaine ${week['week_number']}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (week['sunday_attendance'] == true)
                        _miniChip('Culte', AppColors.integrated),
                      if (week['call_made'] == true)
                        _miniChip('Appel', AppColors.inProgress),
                      if (week['visit_made'] == true)
                        _miniChip('Visite', AppColors.extended),
                      _miniChip(
                        AppConstants.spiritualLabels[spiritual] ?? spiritual,
                        AppColors.spiritualColor(spiritual),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
