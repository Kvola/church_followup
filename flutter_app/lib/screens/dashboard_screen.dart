import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final service = context.read<ChurchService>();
    try {
      final data = await service.getDashboard();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _data == null || _data!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? 'Impossible de charger le tableau de bord', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      );
    }

    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tableau de Bord', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          if (d['church_name'] != null) Text(d['church_name'], style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          _statGrid(d),
          const SizedBox(height: 16),
          _followupStats(d),
          const SizedBox(height: 16),
          _evangelistPerformance(d),
        ],
      ),
    );
  }

  Widget _statGrid(Map<String, dynamic> d) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        _statCard('Membres Totaux', '${d['total_members'] ?? 0}', Icons.people, Colors.blue),
        _statCard('Évangélistes', '${d['total_evangelists'] ?? 0}', Icons.person_pin, Colors.purple),
        _statCard('Cellules', '${d['total_cells'] ?? 0}', Icons.home_work, Colors.teal),
        _statCard("Groupes d'Âge", '${d['total_groups'] ?? 0}', Icons.groups, Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _followupStats(Map<String, dynamic> d) {
    final active = d['active_followups'] ?? 0;
    final integrated = d['integrated_count'] ?? 0;
    final abandoned = d['abandoned_count'] ?? 0;
    final rate = d['integration_rate'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Suivi Évangélisation', style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            _statsRow('Suivis actifs', '$active', Colors.blue),
            _statsRow('Intégrés', '$integrated', Colors.green),
            _statsRow('Abandonnés', '$abandoned', Colors.red),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Taux d'intégration", style: TextStyle(fontWeight: FontWeight.bold)),
                Text('$rate%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (rate as num).toDouble() / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: rate > 70 ? Colors.green : rate > 40 ? Colors.orange : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _evangelistPerformance(Map<String, dynamic> d) {
    final evangelists = d['evangelists'] as List? ?? [];
    if (evangelists.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance Évangélistes', style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            ...evangelists.map<Widget>((e) {
              final rate = (e['integration_rate'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(e['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500))),
                        Text('${e['active_count'] ?? 0} actifs', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Text('${rate.toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: rate / 100,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
