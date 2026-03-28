import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class EvangelistListScreen extends StatefulWidget {
  const EvangelistListScreen({super.key});

  @override
  State<EvangelistListScreen> createState() => _EvangelistListScreenState();
}

class _EvangelistListScreenState extends State<EvangelistListScreen> {
  List<dynamic> _evangelists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getEvangelists();
    if (mounted) setState(() { _evangelists = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Évangélistes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _evangelists.isEmpty
                  ? const Center(child: Text('Aucun évangéliste'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _evangelists.length,
                      itemBuilder: (_, i) => _buildCard(_evangelists[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> e) {
    final rate = (e['integration_rate'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text((e['name'] ?? '?')[0]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (e['phone'] != null) Text(e['phone'], style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniStat('Actifs', '${e['active_count'] ?? 0}', Colors.blue),
                _miniStat('Intégrés', '${e['integrated_count'] ?? 0}', Colors.green),
                _miniStat('Taux', '${rate.toInt()}%', rate > 70 ? Colors.green : rate > 40 ? Colors.orange : Colors.red),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: rate / 100, minHeight: 5, backgroundColor: Colors.grey.shade200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
