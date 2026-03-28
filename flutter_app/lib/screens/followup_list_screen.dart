import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';
import 'followup_detail_screen.dart';
import 'followup_form_screen.dart';

class FollowupListScreen extends StatefulWidget {
  final bool myOnly;
  const FollowupListScreen({super.key, this.myOnly = false});

  @override
  State<FollowupListScreen> createState() => _FollowupListScreenState();
}

class _FollowupListScreenState extends State<FollowupListScreen> {
  List<dynamic> _followups = [];
  bool _loading = true;
  String _stateFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getFollowups(myOnly: widget.myOnly);
    if (mounted) {
      setState(() {
        _followups = data;
        _loading = false;
      });
    }
  }

  List<dynamic> get _filtered {
    if (_stateFilter == 'all') return _followups;
    return _followups.where((f) => f['state'] == _stateFilter).toList();
  }

  Color _stateColor(String? state) {
    switch (state) {
      case 'in_progress':
        return Colors.blue;
      case 'integrated':
        return Colors.green;
      case 'abandoned':
        return Colors.red;
      case 'extended':
        return Colors.orange;
      case 'transferred':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _stateLabel(String? state) {
    switch (state) {
      case 'in_progress':
        return 'En cours';
      case 'integrated':
        return 'Intégré';
      case 'abandoned':
        return 'Abandonné';
      case 'extended':
        return 'Prolongé';
      case 'transferred':
        return 'Transféré';
      default:
        return state ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('Tous', 'all'),
                const SizedBox(width: 8),
                _filterChip('En cours', 'in_progress'),
                const SizedBox(width: 8),
                _filterChip('Intégrés', 'integrated'),
                const SizedBox(width: 8),
                _filterChip('Abandonnés', 'abandoned'),
                const SizedBox(width: 8),
                _filterChip('Prolongés', 'extended'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('Aucun suivi trouvé'))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildCard(_filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const FollowupFormScreen()),
          );
          if (created == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _stateFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _stateFilter = value),
    );
  }

  Widget _buildCard(Map<String, dynamic> f) {
    final state = f['state'] as String?;
    final progress = (f['progress'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FollowupDetailScreen(followupId: f['id'])),
          );
          _load();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f['reference'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(f['member_name'] ?? '', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _stateColor(state).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _stateLabel(state),
                      style: TextStyle(color: _stateColor(state), fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (f['evangelist_name'] != null)
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(f['evangelist_name'], style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${progress.toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Semaine ${f['current_week'] ?? 0}/${f['total_weeks'] ?? 4}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Spacer(),
                  if (f['start_date'] != null) Text('Début: ${f['start_date']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
