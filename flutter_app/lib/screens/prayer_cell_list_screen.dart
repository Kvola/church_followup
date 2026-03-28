import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class PrayerCellListScreen extends StatefulWidget {
  const PrayerCellListScreen({super.key});

  @override
  State<PrayerCellListScreen> createState() => _PrayerCellListScreenState();
}

class _PrayerCellListScreenState extends State<PrayerCellListScreen> {
  List<dynamic> _cells = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getPrayerCells();
    if (mounted) setState(() { _cells = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cellules de Prière')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _cells.isEmpty
                  ? const Center(child: Text('Aucune cellule'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _cells.length,
                      itemBuilder: (_, i) => _buildCard(_cells[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> cell) {
    final members = cell['members'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.home_work),
        ),
        title: Text(cell['name'] ?? ''),
        subtitle: Text('${members.length} membre(s) · ${cell['leader_name'] ?? 'Pas de leader'}'),
        trailing: Text(cell['meeting_day'] ?? ''),
        children: [
          if (cell['address'] != null)
            ListTile(
              leading: const Icon(Icons.location_on, size: 18),
              title: Text(cell['address']),
              dense: true,
            ),
          if (cell['meeting_time'] != null)
            ListTile(
              leading: const Icon(Icons.schedule, size: 18),
              title: Text('${cell['meeting_day'] ?? ''} à ${cell['meeting_time']}'),
              dense: true,
            ),
          const Divider(),
          ...members.map<Widget>((m) => ListTile(
                leading: CircleAvatar(radius: 14, child: Text((m['name'] ?? '?')[0], style: const TextStyle(fontSize: 12))),
                title: Text(m['name'] ?? '', style: const TextStyle(fontSize: 14)),
                subtitle: Text(m['phone'] ?? '', style: const TextStyle(fontSize: 12)),
                dense: true,
              )),
          if (members.isEmpty) const ListTile(title: Text('Aucun membre', style: TextStyle(color: Colors.grey)), dense: true),
        ],
      ),
    );
  }
}
