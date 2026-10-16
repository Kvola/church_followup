import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

const _milestoneLabels = {'3m': 'à 3 mois', '6m': 'à 6 mois'};

/// Points de contrôle après l'intégration : la personne est-elle restée ?
/// Deux contrôles favorables (3 et 6 mois) en font un « Fidèle affermi ».
class CheckpointListScreen extends StatefulWidget {
  const CheckpointListScreen({super.key});

  @override
  State<CheckpointListScreen> createState() => _CheckpointListScreenState();
}

class _CheckpointListScreenState extends State<CheckpointListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<AuthProvider>().api.getCheckpoints();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Points de contrôle')),
      body: _loading && _items.isEmpty
          ? const ShimmerList(itemCount: 4)
          : _error != null && _items.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.verified_outlined,
                      title: 'Aucun contrôle prévu',
                      subtitle: 'Chaque intégration planifie deux contrôles, à 3 et 6 mois.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _items.map((c) {
                          final due = DateTime.tryParse(AppConstants.safeStr(c['due_date']));
                          final overdue = due != null && !due.isAfter(today);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (overdue ? AppColors.extended : AppColors.inProgress).withValues(alpha: 0.12),
                                child: Icon(Icons.fact_check_outlined, color: overdue ? AppColors.extended : AppColors.inProgress),
                              ),
                              title: Text(AppConstants.safeStr(c['member_name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                'Contrôle ${_milestoneLabels[c['milestone']] ?? ''}'
                                '${c['is_catchup'] == true ? ' (rattrapage)' : ''} — '
                                '${overdue ? 'à faire' : 'prévu le ${AppConstants.frDate(c['due_date'])}'}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                final saved = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(builder: (_) => CheckpointScreen(checkpoint: c)),
                                );
                                if (saved == true) _load();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
    );
  }
}

/// Enregistrer le résultat d'un contrôle.
class CheckpointScreen extends StatefulWidget {
  final Map<String, dynamic> checkpoint;
  const CheckpointScreen({super.key, required this.checkpoint});

  @override
  State<CheckpointScreen> createState() => _CheckpointScreenState();
}

class _CheckpointScreenState extends State<CheckpointScreen> {
  final _notesCtrl = TextEditingController();
  String? _result;
  DateTime? _baptismDate;
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_result == null) return;
    setState(() => _saving = true);
    final c = widget.checkpoint;
    Map<String, dynamic> result;
    try {
      result = await context.read<AuthProvider>().api.saveCheckpoint({
        'checkpoint_id': c['id'],
        'result': _result,
        'notes': _notesCtrl.text.trim(),
        if (_baptismDate != null) 'baptism_date': _baptismDate!.toIso8601String().split('T')[0],
      });
    } catch (e) {
      result = {'status': 'error', 'message': '$e'};
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['status'] != 'success') {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
      return;
    }
    final established = result['member_type'] == 'established';
    showSuccessSnackbar(
      context,
      established
          ? '${c['member_name']} est désormais Fidèle affermi(e)'
          : _result == 'favorable'
              ? 'Contrôle favorable enregistré'
              : 'Contrôle défavorable : rattrapage prévu dans un mois',
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.checkpoint;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(AppConstants.safeStr(c['member_name'], 'Contrôle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contrôle ${_milestoneLabels[c['milestone']] ?? ''}${c['is_catchup'] == true ? ' (rattrapage)' : ''}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (AppConstants.safeStr(c['prayer_cell_name']).isNotEmpty)
                    Text('Cellule : ${c['prayer_cell_name']}'),
                  const Divider(height: 24),
                  Text('Sur les 90 derniers jours', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('${c['service_count'] ?? 0}', 'cultes', Icons.church),
                      _stat('${c['cell_count'] ?? 0}', 'cellules', Icons.groups),
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(c['baptized'] == true ? Icons.check : Icons.close, size: 16),
                        label: Text(c['baptized'] == true ? 'Baptisé(e)' : 'Pas encore baptisé(e)'),
                      ),
                      Chip(
                        avatar: Icon(c['has_mentor'] == true ? Icons.check : Icons.close, size: 16),
                        label: Text(c['has_mentor'] == true ? 'A un mentor' : 'Sans mentor'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('La personne vient-elle toujours ?', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'favorable', label: Text('Oui, elle tient'), icon: Icon(Icons.thumb_up_outlined)),
              ButtonSegment(value: 'unfavorable', label: Text('Elle ne vient plus'), icon: Icon(Icons.thumb_down_outlined)),
            ],
            emptySelectionAllowed: true,
            selected: {if (_result != null) _result!},
            onSelectionChanged: (s) => setState(() => _result = s.isEmpty ? null : s.first),
          ),
          if (_result == 'unfavorable')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Le responsable sera alerté et un rattrapage planifié dans un mois.',
                  style: TextStyle(color: AppColors.extended, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Observations (facultatives)'),
          ),
          if (c['baptized'] != true) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(_baptismDate == null
                  ? 'Noter un baptême (facultatif)'
                  : 'Baptême le ${_baptismDate!.toIso8601String().split('T')[0]}'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _baptismDate = picked);
              },
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _result == null || _saving ? null : _save,
              child: const Text('Enregistrer le contrôle'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, IconData icon) => Column(
        children: [
          Icon(icon, color: AppColors.primary),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
}
