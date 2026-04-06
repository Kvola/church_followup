import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

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
          // Search bar
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
          // Stats
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
          // List
          Expanded(
            child: org.isLoading && org.churches.isEmpty
                ? const ShimmerList()
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.church_outlined,
                        title: 'Aucune église',
                        subtitle: 'Créez votre première église',
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
        onPressed: _showCreateChurchDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle église'),
      ),
    );
  }

  void _showCreateChurchDialog() {
    final nameC = TextEditingController();
    final codeC = TextEditingController();
    final addressC = TextEditingController();
    final cityC = TextEditingController();
    final phoneC = TextEditingController();
    final emailC = TextEditingController();
    final pastorC = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nouvelle Église', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.church))),
              const SizedBox(height: 8),
              TextField(controller: codeC, decoration: const InputDecoration(labelText: 'Code', prefixIcon: Icon(Icons.tag))),
              const SizedBox(height: 8),
              TextField(controller: pastorC, decoration: const InputDecoration(labelText: 'Pasteur', prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 8),
              TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on))),
              const SizedBox(height: 8),
              TextField(controller: cityC, decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city))),
              const SizedBox(height: 8),
              TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              TextField(controller: emailC, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  if (nameC.text.trim().isEmpty) {
                    showErrorSnackbar(ctx, 'Le nom est requis');
                    return;
                  }
                  final org = context.read<OrganizationProvider>();
                  final result = await org.createChurch({
                    'name': nameC.text.trim(),
                    'code': codeC.text.trim(),
                    'pastor_name': pastorC.text.trim(),
                    'address': addressC.text.trim(),
                    'city': cityC.text.trim(),
                    'phone': phoneC.text.trim(),
                    'email': emailC.text.trim(),
                  });
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (result['status'] == 'success') {
                    showSuccessSnackbar(ctx, result['message'] ?? 'Église créée');
                  } else {
                    showErrorSnackbar(ctx, result['message'] ?? 'Erreur');
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Créer l\'église'),
              ),
            ],
          ),
        ),
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

// ─── Church Card ─────────────────────────────────────────────────────

class _ChurchCard extends StatelessWidget {
  final Map<String, dynamic> church;
  final VoidCallback onTap;

  const _ChurchCard({required this.church, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                child: Icon(Icons.church, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(church['name'] ?? '', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if ((church['city'] ?? '').toString().isNotEmpty)
                      Text(church['city'], style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                    if ((church['pastor_name'] ?? '').toString().isNotEmpty)
                      Text('Pasteur: ${church['pastor_name']}', style: theme.textTheme.bodySmall),
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
              icon: const Icon(Icons.edit),
              onPressed: _showEditDialog,
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
                                    child: Icon(Icons.church, color: AppColors.primary, size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_detail!['name'], style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                        if ((_detail!['code'] ?? '').toString().isNotEmpty)
                                          Text('Code: ${_detail!['code']}', style: theme.textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              if ((_detail!['pastor_name'] ?? '').toString().isNotEmpty)
                                _InfoRow(Icons.person, 'Pasteur', _detail!['pastor_name']),
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
                      // Managers section
                      Text('Responsables', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if ((_detail!['managers'] as List?)?.isEmpty ?? true)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Aucun responsable assigné', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                          ),
                        )
                      else
                        ...(_detail!['managers'] as List).map((m) => Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                                  child: Icon(Icons.manage_accounts, color: AppColors.secondary),
                                ),
                                title: Text(m['name'] ?? ''),
                                subtitle: Text(m['phone'] ?? ''),
                              ),
                            )),
                      const SizedBox(height: 12),
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
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nom complet *', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 8),
            TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Téléphone *', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
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
                final pin = result['user']?['pin'] ?? '';
                showSuccessSnackbar(context, '${result['message']} — PIN: $pin');
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

  void _showEditDialog() {
    final nameC = TextEditingController(text: _detail?['name'] ?? '');
    final codeC = TextEditingController(text: _detail?['code'] ?? '');
    final pastorC = TextEditingController(text: _detail?['pastor_name'] ?? '');
    final addressC = TextEditingController(text: _detail?['address'] ?? '');
    final cityC = TextEditingController(text: _detail?['city'] ?? '');
    final phoneC = TextEditingController(text: _detail?['phone'] ?? '');
    final emailC = TextEditingController(text: _detail?['email'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Modifier l\'église', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 8),
              TextField(controller: codeC, decoration: const InputDecoration(labelText: 'Code')),
              const SizedBox(height: 8),
              TextField(controller: pastorC, decoration: const InputDecoration(labelText: 'Pasteur')),
              const SizedBox(height: 8),
              TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Adresse')),
              const SizedBox(height: 8),
              TextField(controller: cityC, decoration: const InputDecoration(labelText: 'Ville')),
              const SizedBox(height: 8),
              TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 8),
              TextField(controller: emailC, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final org = context.read<OrganizationProvider>();
                  final result = await org.updateChurch(widget.churchId, {
                    'name': nameC.text.trim(),
                    'code': codeC.text.trim(),
                    'pastor_name': pastorC.text.trim(),
                    'address': addressC.text.trim(),
                    'city': cityC.text.trim(),
                    'phone': phoneC.text.trim(),
                    'email': emailC.text.trim(),
                  });
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  if (result['status'] == 'success') {
                    showSuccessSnackbar(context, 'Église mise à jour');
                    _loadDetail();
                  } else {
                    showErrorSnackbar(context, result['message'] ?? 'Erreur');
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
