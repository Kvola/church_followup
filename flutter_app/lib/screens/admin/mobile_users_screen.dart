import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/invitation_dialog.dart';

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
      final org = context.read<OrganizationProvider>();
      org.loadMobileUsers();

      // Pre-load data for super_admin user creation dialogs
      final auth = context.read<AuthProvider>();
      if (auth.isSuperAdmin) {
        org.loadChurches();
      }
      org.loadCells();
      org.loadAgeGroups();
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
                        onShare: () => _shareInvitation(user),
                        isSuperAdmin: auth.isSuperAdmin,
                        onEditRole: auth.isSuperAdmin ? () => _showEditRoleDialog(user) : null,
                        onToggleActive: auth.isSuperAdmin ? () => _toggleActive(user) : null,
                      );
                    },
                  ),
                ),
      // Un seul bouton, qui dit ce qu'il fait ; le choix du compte vient après.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _chooseAccountKind(auth.isSuperAdmin),
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter un compte'),
      ),
    );
  }

  void _chooseAccountKind(bool isSuperAdmin) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Responsable de cellule'),
              subtitle: const Text('Pointe sa cellule et fait les contrôles à 3 et 6 mois'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateLeaderDialog('cell');
              },
            ),
            ListTile(
              leading: const Icon(Icons.diversity_3_outlined),
              title: const Text('Responsable de groupe d\'âge'),
              subtitle: const Text('Pointe la présence de son groupe au culte'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateLeaderDialog('group');
              },
            ),
            if (isSuperAdmin)
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Autre compte'),
                subtitle: const Text('Évangéliste, responsable, avec son rôle et son église'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateUserDialog();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// L'invitation à installer l'app et à s'y connecter. Sans secret : on peut
  /// la renvoyer autant de fois qu'il faut, rien n'est invalidé.
  Future<void> _shareInvitation(Map<String, dynamic> user) async {
    final userId = user['id'];
    if (userId == null) return;

    final result = await context.read<OrganizationProvider>().shareInvitation(userId);
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
              // La poignée vient du thème (showDragHandle) : pas de seconde.
              Text(
                'Inviter $userName',
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
                      launchWhatsApp(context, phone, message);
                    },
                  ),
                  const SizedBox(width: 12),
                  _ShareOption(
                    icon: Icons.sms_outlined,
                    color: Colors.orange,
                    label: 'SMS',
                    onTap: () {
                      Navigator.pop(ctx);
                      launchSms(context, phone, message);
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
                      Share.share(message, subject: AppConstants.appName);
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
    if (!confirmed || !mounted) return;

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
    int? selectedUnitId;
    final roles = AppConstants.roleLabels.entries
        .where((e) => e.key != 'super_admin')
        .toList();
    _RoleUnitPicker.ensureLoaded(context, selectedRole);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Modifier le rôle de ${user['name'] ?? ''}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Nouveau rôle'),
                initialValue: roles.any((e) => e.key == selectedRole) ? selectedRole : null,
                items: roles.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) {
                  _RoleUnitPicker.ensureLoaded(context, v);
                  setDialogState(() {
                    selectedRole = v;
                    selectedUnitId = null;
                  });
                },
              ),
              _RoleUnitPicker(
                role: selectedRole,
                value: selectedUnitId,
                onChanged: (v) => setDialogState(() => selectedUnitId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (selectedRole == null) return;
                if (_RoleUnitPicker.needsUnit(selectedRole) && selectedUnitId == null && selectedRole != user['role']) {
                  showErrorSnackbar(context, 'Choisissez la cellule ou le groupe de ce responsable');
                  return;
                }
                Navigator.pop(ctx);
                final result = await context.read<OrganizationProvider>().adminUpdateUser(
                    userId, {'role': selectedRole, ..._RoleUnitPicker.params(selectedRole, selectedUnitId)});
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
    int? selectedChurchId;
    int? selectedUnitId;
    final roles = AppConstants.roleLabels.entries
        .where((e) => e.key != 'super_admin')
        .toList();
    final auth = context.read<AuthProvider>();
    final org = context.read<OrganizationProvider>();

    // Load churches for super_admin
    if (auth.isSuperAdmin && org.churches.isEmpty) {
      org.loadChurches();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final churches = context.watch<OrganizationProvider>().churches;
          return AlertDialog(
            title: const Text('Nouvel utilisateur'),
            content: SingleChildScrollView(
              child: Column(
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
                    onChanged: (v) {
                      _RoleUnitPicker.ensureLoaded(context, v);
                      setDialogState(() {
                        selectedRole = v;
                        selectedUnitId = null;
                      });
                    },
                  ),
                  _RoleUnitPicker(
                    role: selectedRole,
                    value: selectedUnitId,
                    onChanged: (v) => setDialogState(() => selectedUnitId = v),
                  ),
                  if (auth.isSuperAdmin) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Église *', prefixIcon: Icon(Icons.church_outlined)),
                      items: churches
                          .where((c) => c['id'] is int)
                          .map((c) => DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'] ?? '')))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedChurchId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty || selectedRole == null) return;
                  if (auth.isSuperAdmin && selectedChurchId == null) return;
                  if (_RoleUnitPicker.needsUnit(selectedRole) && selectedUnitId == null) {
                    showErrorSnackbar(context, 'Choisissez la cellule ou le groupe de ce responsable');
                    return;
                  }
                  Navigator.pop(ctx);

                  final userData = <String, dynamic>{
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'role': selectedRole,
                    ..._RoleUnitPicker.params(selectedRole, selectedUnitId),
                  };
                  if (auth.isSuperAdmin && selectedChurchId != null) {
                    userData['church_id'] = selectedChurchId;
                  }

                  final result = await context.read<OrganizationProvider>().adminCreateUser(userData);

                  if (mounted) {
                    if (result['status'] == 'success') {
                      final invitation = AppConstants.safeStr(result['user']?['invitation']);
                      showInvitationDialog(context, invitation, nameCtrl.text.trim(), phoneCtrl.text.trim());
                    } else {
                      showErrorSnackbar(context, result['message'] ?? 'Erreur');
                    }
                  }
                },
                child: const Text('Créer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateLeaderDialog(String type) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final title = type == 'cell' ? 'Responsable de cellule' : "Responsable de groupe d'âge";
    int? selectedId;
    final provider = context.read<OrganizationProvider>();

    // Ensure cells/age groups are loaded
    if (type == 'cell' && provider.cells.isEmpty) {
      provider.loadCells();
    } else if (type != 'cell' && provider.ageGroups.isEmpty) {
      provider.loadAgeGroups();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final items = type == 'cell' ? provider.activeCells : provider.activeAgeGroups;
          return AlertDialog(
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
                    provider.loadMobileUsers();
                    final invitation = AppConstants.safeStr(result['invitation']);
                    if (invitation.isNotEmpty) {
                      showInvitationDialog(context, invitation, nameCtrl.text.trim(), phoneCtrl.text.trim());
                    } else {
                      showSuccessSnackbar(context, '$title créé');
                    }
                  } else {
                    showErrorSnackbar(context, result['message'] ?? 'Erreur');
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onShare;
  final bool isSuperAdmin;
  final VoidCallback? onEditRole;
  final VoidCallback? onToggleActive;
  const _UserCard({
    required this.data,
    required this.onShare,
    this.isSuperAdmin = false,
    this.onEditRole,
    this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final phone = data['phone'] ?? '';
    final role = data['role'] ?? '';
    final lastLogin = _shortDate(AppConstants.safeStr(data['last_login']));
    final neverLogged = lastLogin.isEmpty;
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
            const SizedBox(height: 4),
            // Wrap, pas Row : sur un téléphone étroit, la date passe à la ligne
            // au lieu de déborder.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StateBadge(state: role, small: true, label: data['role_label']?.toString()),
                if (neverLogged)
                  const StateBadge(state: 'never_logged', small: true),
                if (lastLogin.isNotEmpty)
                  Text('Vu le $lastLogin', style: theme.textTheme.bodySmall),
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
                    case 'toggle_active':
                      onToggleActive?.call();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Envoyer l\'invitation'))),
                  const PopupMenuItem(value: 'edit_role', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier le rôle'))),
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
                tooltip: 'Envoyer l\'invitation',
                onPressed: onShare,
              ),
      ),
    );
  }

  /// « 2026-10-15 19:40:00 » → « 15/10 à 19:40 ».
  static String _shortDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} à ${two(dt.hour)}:${two(dt.minute)}';
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

/// Un responsable de cellule ou de groupe n'existe que rattaché à son unité.
class _RoleUnitPicker extends StatelessWidget {
  final String? role;
  final int? value;
  final ValueChanged<int?> onChanged;
  const _RoleUnitPicker({required this.role, required this.value, required this.onChanged});

  static bool needsUnit(String? role) => role == 'cell_leader' || role == 'group_leader';

  @override
  Widget build(BuildContext context) {
    if (!needsUnit(role)) return const SizedBox.shrink();
    final org = context.watch<OrganizationProvider>();
    final isCell = role == 'cell_leader';
    final items = isCell ? org.activeCells : org.activeAgeGroups;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$role-${items.length}'),
        decoration: InputDecoration(
          labelText: isCell ? 'Cellule *' : "Groupe d'âge *",
          prefixIcon: Icon(isCell ? Icons.group_outlined : Icons.diversity_3_outlined),
        ),
        initialValue: items.any((i) => i['id'] == value) ? value : null,
        items: items
            .where((i) => i['id'] is int)
            .map((i) => DropdownMenuItem<int>(value: i['id'] as int, child: Text(AppConstants.safeStr(i['name']))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  /// Charge les unités dont le rôle a besoin.
  static void ensureLoaded(BuildContext context, String? role) {
    final org = context.read<OrganizationProvider>();
    if (role == 'cell_leader' && org.cells.isEmpty) org.loadCells();
    if (role == 'group_leader' && org.ageGroups.isEmpty) org.loadAgeGroups();
  }

  static Map<String, dynamic> params(String? role, int? unitId) => {
        if (role == 'cell_leader' && unitId != null) 'prayer_cell_id': unitId,
        if (role == 'group_leader' && unitId != null) 'age_group_id': unitId,
      };
}
