import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';
import 'member_form_screen.dart';

class MemberListScreen extends StatefulWidget {
  const MemberListScreen({super.key});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  List<dynamic> _members = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getMembers();
    if (mounted) setState(() { _members = data; _loading = false; });
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _members;
    final q = _search.toLowerCase();
    return _members.where((m) {
      final name = (m['name'] ?? '').toString().toLowerCase();
      final phone = (m['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'new': return Colors.blue;
      case 'in_followup': return Colors.orange;
      case 'integrated': return Colors.green;
      case 'old_member': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'new': return 'Nouveau';
      case 'in_followup': return 'En suivi';
      case 'integrated': return 'Intégré';
      case 'old_member': return 'Ancien';
      default: return type ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un membre...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(child: Text('Aucun membre trouvé'))
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _buildItem(_filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const MemberFormScreen()),
          );
          if (created == true) _load();
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> m) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _typeColor(m['member_type']).withValues(alpha: 0.2),
          child: Text(
            (m['name'] ?? '?')[0].toUpperCase(),
            style: TextStyle(color: _typeColor(m['member_type']), fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(m['name'] ?? ''),
        subtitle: Text(m['phone'] ?? ''),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _typeColor(m['member_type']).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _typeLabel(m['member_type']),
            style: TextStyle(fontSize: 11, color: _typeColor(m['member_type']), fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () async {
          final updated = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => MemberFormScreen(memberId: m['id'])),
          );
          if (updated == true) _load();
        },
      ),
    );
  }
}
