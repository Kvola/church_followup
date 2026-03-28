import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class CookingRotationScreen extends StatefulWidget {
  const CookingRotationScreen({super.key});

  @override
  State<CookingRotationScreen> createState() => _CookingRotationScreenState();
}

class _CookingRotationScreenState extends State<CookingRotationScreen> {
  List<dynamic> _rotations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getCookingRotation();
    if (mounted) setState(() { _rotations = data; _loading = false; });
  }

  Color _stateColor(String? state) {
    switch (state) {
      case 'planned': return Colors.blue;
      case 'done': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _stateLabel(String? state) {
    switch (state) {
      case 'planned': return 'Planifié';
      case 'done': return 'Fait';
      case 'cancelled': return 'Annulé';
      default: return state ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rotation Cuisine')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rotations.isEmpty
                  ? const Center(child: Text('Aucune rotation planifiée'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rotations.length,
                      itemBuilder: (_, i) {
                        final r = _rotations[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _stateColor(r['state']).withValues(alpha: 0.2),
                              child: Icon(Icons.restaurant, color: _stateColor(r['state'])),
                            ),
                            title: Text(r['date'] ?? ''),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (r['group_name'] != null) Text('Groupe: ${r['group_name']}'),
                                if (r['responsible_name'] != null) Text('Responsable: ${r['responsible_name']}'),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _stateColor(r['state']).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _stateLabel(r['state']),
                                style: TextStyle(color: _stateColor(r['state']), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            isThreeLine: r['group_name'] != null && r['responsible_name'] != null,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
