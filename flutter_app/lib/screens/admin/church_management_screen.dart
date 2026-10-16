import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/organization_provider.dart';
import '../../core/constants.dart';
import '../../widgets/common.dart';
import '../../widgets/invitation_dialog.dart';

class ChurchManagementScreen extends StatefulWidget {
  const ChurchManagementScreen({super.key});

  @override
  State<ChurchManagementScreen> createState() => _ChurchManagementScreenState();
}

class _ChurchManagementScreenState extends State<ChurchManagementScreen> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadChurches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationProvider>();

    final filtered = org.churches.where((c) {
      if (_search.isEmpty) return true;
      final s = _search.toLowerCase();
      return (c['name'] ?? '').toString().toLowerCase().contains(s) ||
          (c['city'] ?? '').toString().toLowerCase().contains(s) ||
          (c['pastor_name'] ?? '').toString().toLowerCase().contains(s);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Églises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => org.loadChurches(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher une église...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _StatChip('${filtered.length}', 'Églises', AppColors.primary),
                const SizedBox(width: 8),
                _StatChip(
                  '${filtered.fold<int>(0, (s, c) => s + (c['member_count'] as int? ?? 0))}',
                  'Membres',
                  AppColors.secondary,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  '${filtered.fold<int>(0, (s, c) => s + (c['evangelist_count'] as int? ?? 0))}',
                  'Évangélistes',
                  AppColors.integrated,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: org.isLoading && org.churches.isEmpty
                ? const ShimmerList()
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.church_outlined,
                        title: 'Aucune église',
                        subtitle: 'Ajoutez une église de l\'annuaire du réseau',
                      )
                    : RefreshIndicator(
                        onRefresh: () => org.loadChurches(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _ChurchCard(
                            church: filtered[i],
                            onTap: () => _showChurchDetail(filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateChurchSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une église'),
      ),
    );
  }

  void _showCreateChurchSheet(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddChurchSheet(
        onCreated: () {
          context.read<OrganizationProvider>().loadChurches();
        },
      ),
    );
  }

  void _showChurchDetail(Map<String, dynamic> church) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChurchDetailScreen(churchId: church['id'] as int),
      ),
    );
  }
}

// ─── Ajouter une église : la chercher dans l'annuaire du réseau ──────

/// Les églises existent déjà dans l'annuaire du réseau, avec leurs pasteurs :
/// on en fait entrer une dans le suivi. On n'en crée une que si elle n'y est
/// pas — et une saisie qui la désigne sous une autre écriture la retrouve.
class _AddChurchSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _AddChurchSheet({required this.onCreated});

  @override
  State<_AddChurchSheet> createState() => _AddChurchSheetState();
}

class _AddChurchSheetState extends State<_AddChurchSheet> {
  final _queryC = TextEditingController();
  final _cityC = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _submitting = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryC.dispose();
    _cityC.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    final found = await context.read<OrganizationProvider>().searchDirectory(query);
    if (!mounted) return;
    setState(() {
      _results = found;
      _searching = false;
      _searched = query.isNotEmpty;
    });
  }

  Future<void> _add(Map<String, dynamic> data) async {
    setState(() => _submitting = true);
    final result = await context.read<OrganizationProvider>().createChurch(data);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['status'] == 'success') {
      widget.onCreated();
      Navigator.pop(context);
      showSuccessSnackbar(context, result['message'] ?? 'Église ajoutée');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _queryC.text.trim();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ajouter une église au suivi',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Cherchez-la dans l\'annuaire du réseau : ses pasteurs viennent avec elle.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: _queryC,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom, commune ou code',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _onQueryChanged,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: _searching
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _results)
                        ListTile(
                          leading: const Icon(Icons.church_outlined, color: AppColors.primary),
                          title: Text(c['name'] ?? ''),
                          subtitle: Text([
                            c['city'],
                            c['region'],
                            c['pastor_name'],
                          ].where((v) => (v ?? '').toString().isNotEmpty).join(' · ')),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: _submitting ? null : () => _add({'church_id': c['id']}),
                        ),
                      if (_results.isEmpty && _searched)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Aucune église de l\'annuaire ne correspond.'),
                        ),
                    ],
                  ),
          ),
          if (query.length >= 3) ...[
            const Divider(height: 24),
            Text('Elle n\'est pas dans l\'annuaire ?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _cityC,
              decoration: const InputDecoration(labelText: 'Commune', prefixIcon: Icon(Icons.location_city)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _submitting ? null : () => _add({'name': query, 'city': _cityC.text.trim()}),
              icon: const Icon(Icons.add),
              label: Text('Ajouter « $query »'),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Church Card ─────────────────────────────────────────────────────

class _ChurchCard extends StatelessWidget {
  final Map<String, dynamic> church;
  final VoidCallback onTap;

  const _ChurchCard({required this.church, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Les pasteurs titulaires de l'annuaire du réseau.
    final pastorLabel = (church['pastor_name'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.church, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(church['name'] ?? '',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if ((church['city'] ?? '').toString().isNotEmpty)
                      Text(church['city'],
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                    if (pastorLabel.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.person, size: 12, color: AppColors.extended),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(pastorLabel,
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MiniStat(Icons.people, '${church['member_count'] ?? 0}'),
                  const SizedBox(height: 2),
                  _MiniStat(Icons.person_outline, '${church['evangelist_count'] ?? 0}'),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  const _MiniStat(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 3),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatChip(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

// ─── Church Detail Screen ────────────────────────────────────────────

class _ChurchDetailScreen extends StatefulWidget {
  final int churchId;
  const _ChurchDetailScreen({required this.churchId});

  @override
  State<_ChurchDetailScreen> createState() => _ChurchDetailScreenState();
}

class _ChurchDetailScreenState extends State<_ChurchDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loading = true);
    final org = context.read<OrganizationProvider>();
    final detail = await org.getChurchDetail(widget.churchId);
    if (mounted) {
      setState(() {
        _detail = detail;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?['name'] ?? 'Détail église'),
        actions: [
          if (_detail != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Réglages du suivi',
              onPressed: _showEditSheet,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('Église non trouvée'))
              : RefreshIndicator(
                  onRefresh: _loadDetail,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Header card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                    child: const Icon(Icons.church, color: AppColors.primary, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_detail!['name'],
                                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                        if ((_detail!['code'] ?? '').toString().isNotEmpty)
                                          Text('Code: ${_detail!['code']}', style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              if ((_detail!['address'] ?? '').toString().isNotEmpty)
                                _InfoRow(Icons.location_on, 'Adresse', _detail!['address']),
                              if ((_detail!['city'] ?? '').toString().isNotEmpty)
                                _InfoRow(Icons.location_city, 'Ville', _detail!['city']),
                              if ((_detail!['phone'] ?? '').toString().isNotEmpty)
                                _InfoRow(Icons.phone, 'Téléphone', _detail!['phone']),
                              if ((_detail!['email'] ?? '').toString().isNotEmpty)
                                _InfoRow(Icons.email, 'Email', _detail!['email']),
                            ],
                          ),
                        ),
                      ),
                      // L'administrateur seul change d'église : il entre ici dans celle-ci.
                      if (context.watch<AuthProvider>().canChangeChurch &&
                          context.watch<AuthProvider>().churchId != widget.churchId) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _manageThisChurch,
                          icon: const Icon(Icons.login),
                          label: const Text('Gérer cette église'),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Stats grid
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        children: [
                          _StatCard('Membres', '${_detail!['member_count'] ?? 0}', Icons.people, AppColors.primary),
                          _StatCard('Évangélistes', '${_detail!['evangelist_count'] ?? 0}', Icons.person_outline, AppColors.secondary),
                          _StatCard('Cellules', '${_detail!['cell_count'] ?? 0}', Icons.groups, AppColors.inProgress),
                          _StatCard('Groupes', '${_detail!['age_group_count'] ?? 0}', Icons.diversity_3, AppColors.transferred),
                          _StatCard('Suivis actifs', '${_detail!['active_followups'] ?? 0}', Icons.assignment, AppColors.extended),
                          _StatCard('Intégrés', '${_detail!['total_integrated'] ?? 0}', Icons.check_circle, AppColors.integrated),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Pastors section
                      _buildPastorsSection(theme),
                      const SizedBox(height: 16),

                      // Managers section
                      Text('Responsables', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if ((_detail!['managers'] as List?)?.isEmpty ?? true)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Aucun responsable assigné',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                          ),
                        )
                      else
                        ...(_detail!['managers'] as List).map((m) => Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                                  child: const Icon(Icons.manage_accounts, color: AppColors.secondary),
                                ),
                                title: Text(m['name'] ?? ''),
                                subtitle: Text(m['phone'] ?? ''),
                              ),
                            )),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showAddManagerDialog,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Ajouter un responsable'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _manageThisChurch() async {
    final result = await context.read<AuthProvider>().changeChurch(widget.churchId);
    if (!mounted) return;
    if (result['success'] == true) {
      showSuccessSnackbar(context, result['message'] ?? 'Église changée');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Changement impossible');
    }
  }

  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _EditChurchSheet(
        detail: _detail!,
        churchId: widget.churchId,
        onUpdated: _loadDetail,
      ),
    );
  }

  void _showAddManagerDialog() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau Responsable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Église: ${_detail?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nom complet *', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 8),
            TextField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: 'Téléphone *', prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty || phoneC.text.trim().isEmpty) {
                showErrorSnackbar(ctx, 'Nom et téléphone requis');
                return;
              }
              final org = context.read<OrganizationProvider>();
              final result = await org.createManager(nameC.text.trim(), phoneC.text.trim(), widget.churchId);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              if (result['status'] == 'success') {
                showInvitationDialog(context, AppConstants.safeStr(result['user']?['invitation']),
                    nameC.text.trim(), phoneC.text.trim());
                _loadDetail();
              } else {
                showErrorSnackbar(context, result['message'] ?? 'Erreur');
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  /// Les pasteurs de l'annuaire du réseau : on les lit ici, on les ajoute,
  /// mute ou retire dans la gestion des églises du réseau.
  Widget _buildPastorsSection(ThemeData theme) {
    final pastors = (_detail!['pastors'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pasteurs', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('Tenus dans l\'annuaire du réseau',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (pastors.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aucun pasteur dans l\'annuaire pour cette église',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ),
          )
        else
          ...pastors.map((p) {
            final titular = p['is_titular'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (titular ? AppColors.integrated : AppColors.secondary).withValues(alpha: 0.12),
                  child: Icon(Icons.person, color: titular ? AppColors.integrated : AppColors.secondary),
                ),
                title: Text(p['name'] ?? ''),
                subtitle: Text([
                  titular ? 'Pasteur titulaire' : 'Missionnaire',
                  p['phone'],
                ].where((v) => (v ?? '').toString().isNotEmpty).join(' · ')),
              ),
            );
          }),
      ],
    );
  }
}

// ─── Réglages du suivi d'une église ──────────────────────────────────

/// Ce que le suivi règle lui-même. Le nom, l'adresse et les pasteurs de
/// l'église appartiennent à l'annuaire du réseau et s'y corrigent.
class _EditChurchSheet extends StatefulWidget {
  final Map<String, dynamic> detail;
  final int churchId;
  final VoidCallback onUpdated;

  const _EditChurchSheet({
    required this.detail,
    required this.churchId,
    required this.onUpdated,
  });

  @override
  State<_EditChurchSheet> createState() => _EditChurchSheetState();
}

class _EditChurchSheetState extends State<_EditChurchSheet> {
  late final TextEditingController _weeksC;
  late final TextEditingController _attendanceC;
  late bool _enabled;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _weeksC = TextEditingController(text: '${widget.detail['default_followup_weeks'] ?? 4}');
    _attendanceC = TextEditingController(text: '${widget.detail['integration_min_attendance'] ?? 75}');
    _enabled = widget.detail['followup_enabled'] != false;
  }

  @override
  void dispose() {
    _weeksC.dispose();
    _attendanceC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final weeks = int.tryParse(_weeksC.text.trim());
    final attendance = int.tryParse(_attendanceC.text.trim());
    if (weeks == null || attendance == null) {
      showErrorSnackbar(context, 'Saisissez des nombres');
      return;
    }
    setState(() => _submitting = true);
    final result = await context.read<OrganizationProvider>().updateChurch(widget.churchId, {
      'default_followup_weeks': weeks,
      'integration_min_attendance': attendance,
      'followup_enabled': _enabled,
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['status'] == 'success') {
      widget.onUpdated();
      Navigator.pop(context);
      showSuccessSnackbar(context, 'Réglages enregistrés');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.tune, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Réglages du suivi',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _weeksC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durée de suivi par défaut (semaines)',
                  prefixIcon: Icon(Icons.date_range),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _attendanceC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Présence minimale pour intégrer (%)',
                  prefixIcon: Icon(Icons.how_to_reg),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Suivi d\'évangélisation actif'),
                subtitle: const Text('Désactivé, l\'église quitte cette liste ; ses données restent.'),
              ),
              const SizedBox(height: 4),
              Text('Le nom, l\'adresse et les pasteurs se corrigent dans l\'annuaire du réseau.',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey, fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: const Text('Enregistrer'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared Helper Widgets ───────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
