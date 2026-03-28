import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class AgeGroupListScreen extends StatefulWidget {
  const AgeGroupListScreen({super.key});

  @override
  State<AgeGroupListScreen> createState() => _AgeGroupListScreenState();
}

class _AgeGroupListScreenState extends State<AgeGroupListScreen> {
  List<dynamic> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getAgeGroups();
    if (mounted) setState(() { _groups = data; _loading = false; });
  }

  String _typeLabel(String? t) {
    const map = {
      'married': 'Mariés',
      'youth': 'Jeunesse',
      'college': 'Universitaire',
      'highschool': 'Secondaire',
      'children': 'Enfants',
    };
    return map[t] ?? t ?? '';
  }

  IconData _typeIcon(String? t) {
    switch (t) {
      case 'married': return Icons.favorite;
      case 'youth': return Icons.sports_basketball;
      case 'college': return Icons.school;
      case 'highschool': return Icons.menu_book;
      case 'children': return Icons.child_care;
      default: return Icons.groups;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Groupes d'Âge")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _groups.isEmpty
                  ? const Center(child: Text('Aucun groupe'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _groups.length,
                      itemBuilder: (_, i) => _buildCard(_groups[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> group) {
    final members = group['members'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(_typeIcon(group['group_type'])),
        ),
        title: Text(group['name'] ?? ''),
        subtitle: Text('${_typeLabel(group['group_type'])} · ${members.length} membre(s)'),
        trailing: group['leader_name'] != null
            ? Chip(label: Text(group['leader_name'], style: const TextStyle(fontSize: 11)), padding: EdgeInsets.zero)
            : null,
        children: [
          if (group['gender'] != null)
            ListTile(
              leading: const Icon(Icons.wc, size: 18),
              title: Text(group['gender'] == 'male' ? 'Hommes' : group['gender'] == 'female' ? 'Femmes' : 'Mixte'),
              dense: true,
            ),
          if (group['age_range_name'] != null)
            ListTile(
              leading: const Icon(Icons.calendar_month, size: 18),
              title: Text('Tranche: ${group['age_range_name']}'),
              dense: true,
            ),
          const Divider(),
          ...members.map<Widget>((m) => ListTile(
                leading: CircleAvatar(radius: 14, child: Text((m['name'] ?? '?')[0], style: const TextStyle(fontSize: 12))),
                title: Text(m['name'] ?? '', style: const TextStyle(fontSize: 14)),
                dense: true,
              )),
          if (members.isEmpty) const ListTile(title: Text('Aucun membre', style: TextStyle(color: Colors.grey)), dense: true),
        ],
      ),
    );
  }
}
