import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ChurchService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.person, size: 40, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(service.userName ?? 'Utilisateur', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(_roleLabel(service.userRole), style: const TextStyle(fontSize: 13)),
                  ),
                  if (service.churchName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.church, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(service.churchName, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text("À propos"),
                  subtitle: const Text('Suivi Évangélisation v1.0'),
                  dense: true,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Serveur'),
                  subtitle: Text(service.baseUrl),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Déconnexion'),
                  content: const Text('Voulez-vous vraiment vous déconnecter ?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmer')),
                  ],
                ),
              );
              if (ok == true) {
                await service.logout();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'manager': return 'Manager';
      case 'evangelist': return 'Évangéliste';
      case 'cell_leader': return 'Leader de Cellule';
      case 'group_leader': return "Leader de Groupe";
      default: return role ?? '';
    }
  }
}
