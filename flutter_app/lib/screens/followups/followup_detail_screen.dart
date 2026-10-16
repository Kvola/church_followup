import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/followup_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

/// Un suivi prolongé reste actif : il garde ses actions et ses rapports.
bool _isActive(Map<String, dynamic> data) => const ['in_progress', 'extended'].contains(data['state']);

int _int(dynamic value, [int fallback = 0]) => value is int ? value : fallback;

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
    final active = data != null && _isActive(data);

    return Scaffold(
      appBar: AppBar(
        title: Text(data?['member_name'] ?? 'Détail du suivi'),
        actions: [
          if (active)
            PopupMenuButton<String>(
              onSelected: (action) => _handleAction(action, data),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'integrate', child: _ActionRow(Icons.check_circle, 'Intégrer', AppColors.integrated)),
                PopupMenuItem(value: 'extend', child: _ActionRow(Icons.update, 'Prolonger', AppColors.extended)),
                PopupMenuItem(value: 'transfer', child: _ActionRow(Icons.swap_horiz, 'Transférer', AppColors.transferred)),
                PopupMenuItem(value: 'abandon', child: _ActionRow(Icons.cancel, 'Interrompre', AppColors.abandoned)),
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
                          _HeaderCard(data: data),
                          const SizedBox(height: 16),
                          _ProgressCard(data: data),
                          const SizedBox(height: 16),
                          _WeeklyReportsSection(
                            data: data,
                            onAddWeek: active ? () => _showWeekForm(data) : null,
                            onEditWeek: active ? (week) => _showWeekForm(data, existingWeek: week) : null,
                          ),
                        ],
                      ),
                    ),
    );
  }

  Future<void> _report(Map<String, dynamic> result, String success, {bool close = false}) async {
    if (!mounted) return;
    if (result['status'] == 'success') {
      showSuccessSnackbar(context, success);
      if (close) {
        Navigator.pop(context);
      } else {
        context.read<FollowupProvider>().loadDetail(widget.followupId);
      }
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  void _handleAction(String action, Map<String, dynamic> data) async {
    switch (action) {
      case 'integrate':
        await _showIntegrateDialog(data);
      case 'extend':
        await _showExtendDialog(data);
      case 'transfer':
        await _showTransferDialog(data);
      case 'abandon':
        await _showAbandonDialog(data);
    }
  }

  // ─── Prolonger : nombre de semaines au choix ──────────────────────

  Future<void> _showExtendDialog(Map<String, dynamic> data) async {
    // Des semaines à AJOUTER : on part de 2, pas de la durée entière (6 + 6).
    int weeks = 2;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Prolonger le suivi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Durée actuelle : ${_int(data['total_weeks'])} semaines'),
              const SizedBox(height: 16),
              WeeksStepper(value: weeks, onChanged: (v) => setDialogState(() => weeks = v)),
              const SizedBox(height: 8),
              Text('Nouvelle durée : ${_int(data['total_weeks']) + weeks} semaines',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.extended),
              child: const Text('Prolonger'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await context.read<FollowupProvider>().performAction(data['id'], 'extend', weeks: weeks);
    await _report(result, 'Suivi prolongé de $weeks semaines');
  }

  // ─── Interrompre : motif obligatoire ──────────────────────────────

  Future<void> _showAbandonDialog(Map<String, dynamic> data) async {
    String? reason;
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final noteRequired = reason == 'other';
          final valid = reason != null && (!noteRequired || noteCtrl.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Interrompre le suivi'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('La personne passera en « Suivi interrompu ». Son suivi pourra être repris plus tard.'),
                  const SizedBox(height: 12),
                  RadioGroup<String>(
                    groupValue: reason,
                    onChanged: (v) => setDialogState(() => reason = v),
                    child: Column(
                      children: AppConstants.abandonReasons.entries
                          .map((e) => RadioListTile<String>(
                                value: e.key,
                                title: Text(e.value),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: noteRequired ? 'Précisions (obligatoires)' : 'Précisions (facultatives)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.abandoned),
                child: const Text('Interrompre'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || reason == null || !mounted) return;
    final result = await context.read<FollowupProvider>().performAction(
          data['id'],
          'abandon',
          reason: reason,
          note: noteCtrl.text.trim(),
        );
    await _report(result, 'Suivi interrompu', close: true);
  }

  // ─── Intégrer : présence au culte et justification sous le seuil ──

  Future<void> _showIntegrateDialog(Map<String, dynamic> data) async {
    final orgProvider = context.read<OrganizationProvider>();
    await orgProvider.loadCells();
    await orgProvider.loadAgeGroups();
    if (!mounted) return;

    int? selectedCellId;
    int? selectedGroupId;
    final belowThreshold = data['below_threshold'] == true;
    final justificationCtrl = TextEditingController(text: AppConstants.safeStr(data['integration_justification']));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final valid = selectedCellId != null &&
              selectedGroupId != null &&
              (!belowThreshold || justificationCtrl.text.trim().isNotEmpty);
          return AlertDialog(
            title: const Text('Intégrer la personne'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AttendanceSummary(data: data),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Cellule de prière'),
                    items: orgProvider.activeCells
                        .where((c) => c['id'] is int)
                        .map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(AppConstants.safeStr(c['name'], '—'))))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedCellId = v),
                    initialValue: selectedCellId,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Groupe d\'âge'),
                    items: orgProvider.activeAgeGroups
                        .where((g) => g['id'] is int)
                        .map((g) => DropdownMenuItem(value: g['id'] as int, child: Text(AppConstants.safeStr(g['name'], '—'))))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedGroupId = v),
                    initialValue: selectedGroupId,
                  ),
                  if (belowThreshold) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: justificationCtrl,
                      onChanged: (_) => setDialogState(() {}),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Justification (obligatoire)',
                        helperText: 'Présence sous le seuil : expliquez pourquoi intégrer quand même.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.integrated),
                child: const Text('Intégrer'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedCellId == null || selectedGroupId == null || !mounted) return;
    final result = await context.read<FollowupProvider>().performAction(
          data['id'],
          'integrate',
          cellId: selectedCellId,
          groupId: selectedGroupId,
          justification: belowThreshold ? justificationCtrl.text.trim() : null,
        );
    await _report(result, 'Personne intégrée', close: true);
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
                .where((e) => e['id'] is int && e['name'] != data['evangelist_name'])
                .map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(AppConstants.safeStr(e['name'], '—'))))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedEvId = v),
            initialValue: selectedEvId,
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
    if (confirmed != true || selectedEvId == null || !mounted) return;
    final result = await provider.performAction(data['id'], 'transfer', evangelistId: selectedEvId);
    await _report(result, 'Suivi transféré', close: true);
  }

  // ─── Rapport hebdomadaire ─────────────────────────────────────────

  void _showWeekForm(Map<String, dynamic> data, {Map<String, dynamic>? existingWeek}) {
    final provider = context.read<FollowupProvider>();
    final isEdit = existingWeek != null;
    final weeks = (data['weeks'] as List?)?.whereType<Map>().toList() ?? [];
    final reported = weeks.map((w) => w['week_number']).whereType<int>().toSet();
    final total = _int(data['total_weeks'], 1);

    // Par défaut, la première semaine sans rapport.
    int weekNumber = isEdit
        ? _int(existingWeek['week_number'], 1)
        : List.generate(total, (i) => i + 1).firstWhere((n) => !reported.contains(n), orElse: () => total);
    final rollCall = existingWeek?['roll_call_present'] == true;
    bool sundayAttendance = existingWeek?['sunday_attendance'] == true || rollCall;
    bool callMade = existingWeek?['call_made'] == true;
    bool visitMade = existingWeek?['visit_made'] == true;
    String spiritualState = AppConstants.spiritualLabels.containsKey(existingWeek?['spiritual_state'])
        ? existingWeek!['spiritual_state']
        : 'average';
    final noteCtrl = TextEditingController(text: AppConstants.safeStr(existingWeek?['notes']));
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Modifier la semaine $weekNumber' : 'Rapport de semaine',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (!isEdit)
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Semaine'),
                    initialValue: weekNumber,
                    items: List.generate(total, (i) => i + 1)
                        .map((n) => DropdownMenuItem(
                              value: n,
                              child: Text(reported.contains(n) ? 'Semaine $n (déjà rapportée)' : 'Semaine $n'),
                            ))
                        .toList(),
                    onChanged: (v) => setSheetState(() => weekNumber = v ?? weekNumber),
                  ),
                SwitchListTile(
                  title: const Text('Présence au culte'),
                  subtitle: Text(rollCall
                      ? 'Pointé(e) au culte : la présence est acquise.'
                      : 'Cochée d\'office si la personne est pointée au culte.'),
                  value: sundayAttendance,
                  onChanged: rollCall ? null : (v) => setSheetState(() => sundayAttendance = v),
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
                  initialValue: spiritualState,
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
                  decoration: const InputDecoration(labelText: 'Notes (facultatives)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            final result = await provider.saveWeek({
                              'followup_id': data['id'],
                              'week_number': weekNumber,
                              'sunday_attendance': sundayAttendance,
                              'call_made': callMade,
                              'visit_made': visitMade,
                              'spiritual_state': spiritualState,
                              'notes': noteCtrl.text.trim(),
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (!mounted) return;
                            if (result['status'] == 'success') {
                              showSuccessSnackbar(context, isEdit ? 'Semaine mise à jour' : 'Rapport enregistré');
                            } else {
                              showErrorSnackbar(context, result['message'] ?? 'Erreur');
                            }
                          },
                    child: Text(isEdit ? 'Mettre à jour' : 'Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sous-widgets ────────────────────────────────────────────────────

/// Sélecteur de nombre de semaines, de 1 à 26.
class WeeksStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const WeeksStepper({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: value > AppConstants.minFollowupWeeks ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 110,
          child: Text('$value semaine${value > 1 ? 's' : ''}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        IconButton.filledTonal(
          onPressed: value < AppConstants.maxFollowupWeeks ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AttendanceSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final below = data['below_threshold'] == true;
    final color = below ? AppColors.abandoned : AppColors.integrated;
    final threshold = _int(data['attendance_threshold']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Présence au culte : ${_int(data['attendance_weeks'])} semaine(s) sur ${_int(data['elapsed_weeks'])} '
            '(${_int(data['attendance_rate'])}\u00a0%)',
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
          if (threshold > 0)
            Text(below ? 'Sous le seuil de $threshold\u00a0% fixé par l\'église.' : 'Seuil de $threshold\u00a0% atteint.',
                style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

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
    final origin = AppConstants.durationOriginLabels[data['duration_origin']];
    final average = data['average_score'];

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
                        'Évangéliste : ${data['evangelist_name'] ?? ''}',
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
                _infoCol('Durée', '${_int(data['total_weeks'])} sem.', Icons.timer_outlined),
                _infoCol('Rapports', '${_int(data['current_week'])}', Icons.check_circle_outline),
                _infoCol('Score moy.', '${(average is num ? average : 0).toStringAsFixed(1)}/13', Icons.star_outline),
              ],
            ),
            if (origin != null) ...[
              const SizedBox(height: 8),
              Text('Durée : $origin',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
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
    final completed = _int(data['current_week']);
    final total = _int(data['total_weeks'], 1);
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Rapports rédigés', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('$completed / $total', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
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
            if (_int(data['elapsed_weeks']) > 0) ...[
              const SizedBox(height: 16),
              _AttendanceSummary(data: data),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeeklyReportsSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onAddWeek;
  final void Function(Map<String, dynamic> week)? onEditWeek;

  const _WeeklyReportsSection({required this.data, this.onAddWeek, this.onEditWeek});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = (data['weeks'] as List?)?.whereType<Map>().map((w) => Map<String, dynamic>.from(w)).toList() ?? [];

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
          ...weeks.map((week) => _WeekCard(
                week: week,
                onTap: onEditWeek == null ? null : () => onEditWeek!(week),
              )),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  final Map<String, dynamic> week;
  final VoidCallback? onTap;
  const _WeekCard({required this.week, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = (week['score'] is num ? week['score'] as num : 0).toDouble();
    final spiritual = AppConstants.safeStr(week['spiritual_state']);
    final notes = AppConstants.safeStr(week['notes']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                        if (week['roll_call_present'] == true)
                          _miniChip('Pointé(e) au culte', AppColors.integrated)
                        else if (week['sunday_attendance'] == true)
                          _miniChip('Culte', AppColors.integrated),
                        if (week['call_made'] == true) _miniChip('Appel', AppColors.inProgress),
                        if (week['visit_made'] == true) _miniChip('Visite', AppColors.extended),
                        if (spiritual.isNotEmpty)
                          _miniChip(AppConstants.spiritualLabels[spiritual] ?? spiritual, AppColors.spiritualColor(spiritual)),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(notes, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.edit_outlined, size: 18),
            ],
          ),
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
