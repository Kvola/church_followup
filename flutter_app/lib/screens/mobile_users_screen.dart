import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class MobileUsersScreen extends StatefulWidget {
  const MobileUsersScreen({super.key});

  @override
  State<MobileUsersScreen> createState() => _MobileUsersScreenState();
}

class _MobileUsersScreenState extends State<MobileUsersScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final data = await service.getMobileUsers();
    if (mounted) setState(() { _users = data; _loading = false; });
  }

  Future<void> _shareCredentials(int userId) async {
    final service = context.read<ChurchService>();
    final result = await service.shareCredentials(userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success'] == true ? 'Identifiants partagés' : (result['message'] ?? 'Erreur')),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'manager': return 'Manager';
      case 'evangelist': return 'Évangéliste';
      case 'cell_leader': return 'Leader Cellule';
      case 'group_leader': return 'Leader Groupe';
      default: return role ?? '';
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'manager': return Colors.purple;
      case 'evangelist': return Colors.blue;
      case 'cell_leader': return Colors.teal;
      case 'group_leader': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs Mobile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _users.isEmpty
                  ? const Center(child: Text('Aucun utilisateur'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _roleColor(u['role']).withValues(alpha: 0.2),
                              child: Icon(Icons.person, color: _roleColor(u['role'])),
                            ),
                            title: Text(u['name'] ?? ''),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['phone'] ?? ''),
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _roleColor(u['role']).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(_roleLabel(u['role']), style: TextStyle(fontSize: 11, color: _roleColor(u['role']))),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.share),
                              tooltip: 'Partager identifiants',
                              onPressed: () => _shareCredentials(u['id'] as int),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
