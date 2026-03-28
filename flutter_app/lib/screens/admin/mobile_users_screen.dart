import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class MobileUsersScreen extends StatefulWidget {
  const MobileUsersScreen({super.key});

  @override
  State<MobileUsersScreen> createState() => _MobileUsersScreenState();
}

class _MobileUsersScreenState extends State<MobileUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadMobileUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs mobiles'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadMobileUsers()),
        ],
      ),
      body: provider.mobileUsers.isEmpty && provider.isLoading
          ? const ShimmerList()
          : provider.mobileUsers.isEmpty
              ? const EmptyState(icon: Icons.phone_android_outlined, title: 'Aucun utilisateur mobile')
              : RefreshIndicator(
                  onRefresh: () => provider.loadMobileUsers(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: provider.mobileUsers.length,
                    itemBuilder: (_, index) {
                      final user = provider.mobileUsers[index];
                      return _UserCard(
                        data: user,
                        onShare: () => _shareCredentials(user),
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'cell_leader',
            onPressed: () => _showCreateLeaderDialog('cell'),
            tooltip: 'Nouveau chef de cellule',
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'group_leader',
            onPressed: () => _showCreateLeaderDialog('group'),
            icon: const Icon(Icons.person_add),
            label: const Text('Chef de groupe'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCredentials(Map<String, dynamic> user) async {
    final userId = user['id'];
    if (userId == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Partager les identifiants',
      message: 'Envoyer les identifiants à ${user['name'] ?? 'cet utilisateur'} ?',
    );
    if (!confirmed) return;

    final result = await context.read<OrganizationProvider>().shareCredentials(userId);
    if (mounted) {
      if (result['status'] == 'success') {
        showSuccessSnackbar(context, result['message'] ?? 'Identifiants partagés');
      } else {
        showErrorSnackbar(context, result['message'] ?? 'Erreur');
      }
    }
  }

  void _showCreateLeaderDialog(String type) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final title = type == 'cell' ? 'Chef de cellule' : "Chef de groupe d'âge";
    int? selectedId;
    final provider = context.read<OrganizationProvider>();
    final items = type == 'cell' ? provider.cells : provider.ageGroups;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Nouveau $title'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom complet', prefixIcon: Icon(Icons.person_outline)),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: InputDecoration(
                  labelText: type == 'cell' ? 'Cellule' : "Groupe d'âge",
                  prefixIcon: Icon(type == 'cell' ? Icons.group_outlined : Icons.diversity_3_outlined),
                ),
                items: items
                    .where((item) => item['id'] is int)
                    .map((item) => DropdownMenuItem<int>(
                          value: item['id'] as int,
                          child: Text(item['name'] ?? ''),
                        ))
                    .toList(),
                onChanged: (val) => setDialogState(() => selectedId = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty || selectedId == null) return;
                Navigator.pop(ctx);

                Map<String, dynamic> result;
                if (type == 'cell') {
                  result = await provider.createCellLeader(
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    selectedId!,
                  );
                } else {
                  result = await provider.createGroupLeader(
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    selectedId!,
                  );
                }

                if (mounted) {
                  if (result['status'] == 'success') {
                    showSuccessSnackbar(context, '$title créé');
                    provider.loadMobileUsers();
                  } else {
                    showErrorSnackbar(context, result['message'] ?? 'Erreur');
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onShare;
  const _UserCard({required this.data, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final phone = data['phone'] ?? '';
    final role = data['role'] ?? '';
    final lastLogin = data['last_login'] ?? '';
    final isActive = data['active'] ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isActive
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.12),
          child: Icon(
            _roleIcon(role),
            color: isActive ? AppColors.primary : Colors.grey,
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (phone.isNotEmpty) Text(phone),
            Row(
              children: [
                StateBadge(state: role),
                if (lastLogin.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('Dernier: $lastLogin', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Partager les identifiants',
          onPressed: onShare,
        ),
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'manager':
        return Icons.admin_panel_settings;
      case 'evangelist':
        return Icons.volunteer_activism;
      case 'cell_leader':
        return Icons.group;
      case 'group_leader':
        return Icons.groups;
      default:
        return Icons.person;
    }
  }

}
