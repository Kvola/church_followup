import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class FollowupDetailScreen extends StatefulWidget {
  final int followupId;
  const FollowupDetailScreen({super.key, required this.followupId});

  @override
  State<FollowupDetailScreen> createState() => _FollowupDetailScreenState();
}

class _FollowupDetailScreenState extends State<FollowupDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getFollowupDetail(widget.followupId);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  Future<void> _doAction(String action) async {
    final service = context.read<ChurchService>();
    final result = await service.followupAction(widget.followupId, action);
    if (result['success'] == true) {
      _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Erreur'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_data?['reference'] ?? 'Suivi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('Suivi non trouvé'))
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final d = _data!;
    final state = d['state'] as String? ?? '';
    final weeks = d['weeks'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoCard(d),
        const SizedBox(height: 16),
        if (state == 'in_progress' || state == 'extended') _actionButtons(),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Rapports Hebdomadaires', style: Theme.of(context).textTheme.titleMedium),
            if (state == 'in_progress' || state == 'extended')
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () => _showWeekForm(null),
              ),
          ],
        ),
        if (weeks.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucun rapport')),
        ...weeks.map<Widget>((w) => _weekCard(w)),
      ],
    );
  }

  Widget _infoCard(Map<String, dynamic> d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text((d['member_name'] ?? '?')[0], style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['member_name'] ?? '', style: Theme.of(context).textTheme.titleLarge),
                      if (d['member_phone'] != null) Text(d['member_phone'], style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _row('Évangéliste', d['evangelist_name']),
            _row('Début', d['start_date']),
            _row('Fin prévue', d['planned_end_date']),
            _row('Semaine', '${d['current_week'] ?? 0}/${d['total_weeks'] ?? 4}'),
            _row('Score moyen', '${d['average_score'] ?? 0}/10'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: ((d['progress'] as num?)?.toDouble() ?? 0) / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${(d['progress'] as num?)?.toInt() ?? 0}%', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          Expanded(child: Text('${value ?? '-'}')),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _confirmAction('integrate', 'Confirmer l\'intégration ?'),
          icon: const Icon(Icons.check_circle),
          label: const Text('Intégrer'),
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmAction('extend', 'Prolonger de 2 semaines ?'),
          icon: const Icon(Icons.schedule),
          label: const Text('Prolonger'),
        ),
        OutlinedButton.icon(
          onPressed: () => _showTransferDialog(),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Transférer'),
        ),
        OutlinedButton.icon(
          onPressed: () => _confirmAction('abandon', 'Marquer comme abandonné ?'),
          icon: const Icon(Icons.close),
          label: const Text('Abandonner'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Future<void> _confirmAction(String action, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmation'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok == true) _doAction(action);
  }

  Future<void> _showTransferDialog() async {
    final service = context.read<ChurchService>();
    final evangelists = await service.getEvangelists();
    if (!mounted) return;

    final selected = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Transférer à'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: evangelists.length,
            itemBuilder: (_, i) {
              final e = evangelists[i];
              return ListTile(
                title: Text(e['name'] ?? ''),
                onTap: () => Navigator.pop(context, e['id']),
              );
            },
          ),
        ),
      ),
    );
    if (selected != null) {
      final result = await service.followupAction(widget.followupId, 'transfer', evangelistId: selected);
      if (result['success'] == true) {
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Erreur'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _weekCard(Map<String, dynamic> w) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showWeekForm(w),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Semaine ${w['week_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${w['score'] ?? 0}/10', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _weekBadge(Icons.church, 'Dimanche', w['sunday_attendance'] == true),
                  const SizedBox(width: 12),
                  _weekBadge(Icons.call, 'Appel', w['call_made'] == true),
                  const SizedBox(width: 12),
                  _weekBadge(Icons.home, 'Visite', w['visit_made'] == true),
                ],
              ),
              if (w['spiritual_state'] != null) ...[
                const SizedBox(height: 8),
                Text('État: ${_spiritualLabel(w['spiritual_state'])}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
              if (w['notes'] != null && w['notes'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(w['notes'], style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekBadge(IconData icon, String label, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: done ? Colors.green : Colors.grey.shade400),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: done ? Colors.green : Colors.grey.shade400)),
      ],
    );
  }

  String _spiritualLabel(String? s) {
    const map = {
      'cold': 'Froid',
      'lukewarm': 'Tiède',
      'warm': 'Chaud',
      'on_fire': 'En feu',
    };
    return map[s] ?? s ?? '';
  }

  Future<void> _showWeekForm(Map<String, dynamic>? existing) async {
    final isNew = existing == null;
    bool sundayAttendance = existing?['sunday_attendance'] ?? false;
    bool callMade = existing?['call_made'] ?? false;
    bool visitMade = existing?['visit_made'] ?? false;
    String? spiritualState = existing?['spiritual_state'];
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');
    final weekCtrl = TextEditingController(text: isNew ? '' : '${existing!['week_number']}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isNew ? 'Nouveau Rapport' : 'Modifier Semaine ${existing!['week_number']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNew)
                  TextField(
                    controller: weekCtrl,
                    decoration: const InputDecoration(labelText: 'N° Semaine'),
                    keyboardType: TextInputType.number,
                  ),
                CheckboxListTile(
                  title: const Text('Présent dimanche'),
                  value: sundayAttendance,
                  onChanged: (v) => setDialogState(() => sundayAttendance = v!),
                ),
                CheckboxListTile(
                  title: const Text('Appel effectué'),
                  value: callMade,
                  onChanged: (v) => setDialogState(() => callMade = v!),
                ),
                CheckboxListTile(
                  title: const Text('Visite effectuée'),
                  value: visitMade,
                  onChanged: (v) => setDialogState(() => visitMade = v!),
                ),
                DropdownButtonFormField<String>(
                  value: spiritualState,
                  decoration: const InputDecoration(labelText: 'État spirituel'),
                  items: const [
                    DropdownMenuItem(value: 'cold', child: Text('Froid')),
                    DropdownMenuItem(value: 'lukewarm', child: Text('Tiède')),
                    DropdownMenuItem(value: 'warm', child: Text('Chaud')),
                    DropdownMenuItem(value: 'on_fire', child: Text('En feu')),
                  ],
                  onChanged: (v) => spiritualState = v,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );

    if (saved == true) {
      final service = context.read<ChurchService>();
      final vals = {
        'sunday_attendance': sundayAttendance,
        'call_made': callMade,
        'visit_made': visitMade,
        'spiritual_state': spiritualState,
        'notes': notesCtrl.text,
      };
      if (isNew) {
        vals['week_number'] = int.tryParse(weekCtrl.text) ?? 1;
        await service.createFollowupWeek(widget.followupId, vals);
      } else {
        await service.updateFollowupWeek(existing!['id'], vals);
      }
      _load();
    }
  }
}
