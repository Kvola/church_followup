import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
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
    final auth = context.watch<AuthProvider>();

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
                        isSuperAdmin: auth.isSuperAdmin,
                        onEditRole: auth.isSuperAdmin ? () => _showEditRoleDialog(user) : null,
                        onResetPin: auth.isSuperAdmin ? () => _resetPin(user) : null,
                        onToggleActive: auth.isSuperAdmin ? () => _toggleActive(user) : null,
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (auth.isSuperAdmin) ...[
            FloatingActionButton.small(
              heroTag: 'create_user',
              onPressed: () => _showCreateUserDialog(),
              tooltip: 'Créer un utilisateur',
              child: const Icon(Icons.person_add_alt),
            ),
            const SizedBox(height: 8),
          ],
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

    final result = await context.read<OrganizationProvider>().shareCredentials(userId);
    if (!mounted) return;

    if (result['status'] != 'success') {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
      return;
    }

    final message = result['message'] ?? '';
    final phone = AppConstants.safeStr(user['phone']);
    _showShareBottomSheet(message, phone, user['name'] ?? 'Utilisateur');
  }

  void _showShareBottomSheet(String message, String phone, String userName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Partager les identifiants de $userName',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(message, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _ShareOption(
                    icon: Icons.message,
                    color: Colors.blue,
                    label: 'WhatsApp',
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchWhatsApp(phone, message);
                    },
                  ),
                  const SizedBox(width: 12),
                  _ShareOption(
                    icon: Icons.sms_outlined,
                    color: Colors.orange,
                    label: 'SMS',
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchSms(phone, message);
                    },
                  ),
                  const SizedBox(width: 12),
                  _ShareOption(
                    icon: Icons.copy,
                    color: Colors.teal,
                    label: 'Copier',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message));
                      Navigator.pop(ctx);
                      showSuccessSnackbar(context, 'Message copié dans le presse-papiers');
                    },
                  ),
                  const SizedBox(width: 12),
                  _ShareOption(
                    icon: Icons.share,
                    color: AppColors.primary,
                    label: 'Autre',
                    onTap: () {
                      Navigator.pop(ctx);
                      Share.share(message, subject: 'Identifiants ${AppConstants.appName}');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp(String phone, String message) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '').replaceFirst('+', '');
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) showErrorSnackbar(context, 'Impossible d\'ouvrir WhatsApp');
    }
  }

  Future<void> _launchSms(String phone, String message) async {
    final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': message});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) showErrorSnackbar(context, 'Impossible d\'ouvrir les SMS');
    }
  }

  void _showPinWithShareOptions(String pin, String userName, String phone) {
    final message = '🔐 ${AppConstants.appName}\n'
        'Bonjour $userName,\n'
        'Votre nouveau PIN : $pin\n'
        'Serveur : ${AppConstants.defaultUrl}\n'
        'Base de données : ${AppConstants.defaultDatabase}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Le nouveau PIN de $userName est :'),
            const SizedBox(height: 12),
            SelectableText(pin, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MiniShareButton(
                  icon: Icons.message,
                  color: Colors.blue,
                  label: 'WhatsApp',
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchWhatsApp(phone, message);
                  },
                ),
                _MiniShareButton(
                  icon: Icons.sms_outlined,
                  color: Colors.orange,
                  label: 'SMS',
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchSms(phone, message);
                  },
                ),
                _MiniShareButton(
                  icon: Icons.copy,
                  color: Colors.teal,
                  label: 'Copier',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message));
                    showSuccessSnackbar(ctx, 'Copié');
                  },
                ),
                _MiniShareButton(
                  icon: Icons.share,
                  color: AppColors.primary,
                  label: 'Partager',
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(message, subject: 'PIN ${AppConstants.appName}');
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _resetPin(Map<String, dynamic> user) async {
    final userId = user['id'];
    if (userId == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Régénérer le PIN',
      message: 'Régénérer le PIN de ${user['name'] ?? 'cet utilisateur'} ? L\'ancien PIN sera invalidé.',
    );
    if (!confirmed) return;

    final result = await context.read<OrganizationProvider>().adminResetPin(userId);
    if (mounted) {
      if (result['status'] == 'success') {
        final pin = result['pin'] ?? '';
        _showPinWithShareOptions(pin, user['name'] ?? 'Utilisateur', AppConstants.safeStr(user['phone']));
      } else {
        showErrorSnackbar(context, result['message'] ?? 'Erreur');
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final userId = user['id'];
    if (userId == null) return;
    final isActive = user['active'] ?? true;
    final action = isActive ? 'désactiver' : 'activer';

    final confirmed = await showConfirmDialog(
      context,
      title: '${isActive ? "Désactiver" : "Activer"} l\'utilisateur',
      message: 'Voulez-vous $action ${user['name'] ?? 'cet utilisateur'} ?',
    );
    if (!confirmed) return;

    final result = await context.read<OrganizationProvider>().adminUpdateUser(userId, {'active': !isActive});
    if (mounted) {
      if (result['status'] == 'success') {
        showSuccessSnackbar(context, 'Utilisateur ${isActive ? "désactivé" : "activé"}');
      } else {
        showErrorSnackbar(context, result['message'] ?? 'Erreur');
      }
    }
  }

  void _showEditRoleDialog(Map<String, dynamic> user) {
    final userId = user['id'];
    if (userId == null) return;
    String? selectedRole = user['role'];
    final roles = AppConstants.roleLabels.entries
        .where((e) => e.key != 'super_admin')
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Modifier le rôle de ${user['name'] ?? ''}'),
          content: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Nouveau rôle'),
            value: roles.any((e) => e.key == selectedRole) ? selectedRole : null,
            items: roles.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setDialogState(() => selectedRole = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (selectedRole == null) return;
                Navigator.pop(ctx);
                final result = await context.read<OrganizationProvider>().adminUpdateUser(userId, {'role': selectedRole});
                if (mounted) {
                  if (result['status'] == 'success') {
                    showSuccessSnackbar(context, 'Rôle mis à jour');
                  } else {
                    showErrorSnackbar(context, result['message'] ?? 'Erreur');
                  }
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateUserDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? selectedRole;
    final roles = AppConstants.roleLabels.entries
        .where((e) => e.key != 'super_admin')
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nouvel utilisateur'),
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
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Rôle', prefixIcon: Icon(Icons.admin_panel_settings_outlined)),
                items: roles.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setDialogState(() => selectedRole = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty || selectedRole == null) return;
                Navigator.pop(ctx);

                final result = await context.read<OrganizationProvider>().adminCreateUser({
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'role': selectedRole,
                });

                if (mounted) {
                  if (result['status'] == 'success') {
                    final pin = result['user']?['pin'] ?? '';
                    _showPinWithShareOptions(pin, nameCtrl.text.trim(), phoneCtrl.text.trim());
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
  final bool isSuperAdmin;
  final VoidCallback? onEditRole;
  final VoidCallback? onResetPin;
  final VoidCallback? onToggleActive;
  const _UserCard({
    required this.data,
    required this.onShare,
    this.isSuperAdmin = false,
    this.onEditRole,
    this.onResetPin,
    this.onToggleActive,
  });

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
        title: Row(
          children: [
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Inactif', style: TextStyle(fontSize: 10, color: Colors.red)),
              ),
          ],
        ),
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
        trailing: isSuperAdmin
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      onShare();
                      break;
                    case 'edit_role':
                      onEditRole?.call();
                      break;
                    case 'reset_pin':
                      onResetPin?.call();
                      break;
                    case 'toggle_active':
                      onToggleActive?.call();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Partager identifiants'))),
                  const PopupMenuItem(value: 'edit_role', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier le rôle'))),
                  const PopupMenuItem(value: 'reset_pin', child: ListTile(leading: Icon(Icons.refresh), title: Text('Régénérer PIN'))),
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: ListTile(
                      leading: Icon(isActive ? Icons.block : Icons.check_circle_outline),
                      title: Text(isActive ? 'Désactiver' : 'Activer'),
                    ),
                  ),
                ],
              )
            : IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Partager les identifiants',
                onPressed: onShare,
              ),
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'super_admin':
        return Icons.shield;
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

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ShareOption({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniShareButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _MiniShareButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
