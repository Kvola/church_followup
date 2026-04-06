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
        onPressed: () => _showCreateChurchSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle église'),
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
      builder: (ctx) => _CreateChurchSheet(
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

// ─── Create Church Bottom Sheet ──────────────────────────────────────

class _CreateChurchSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateChurchSheet({required this.onCreated});

  @override
  State<_CreateChurchSheet> createState() => _CreateChurchSheetState();
}

class _CreateChurchSheetState extends State<_CreateChurchSheet> {
  final _nameC = TextEditingController();
  final _codeC = TextEditingController();
  final _addressC = TextEditingController();
  final _cityC = TextEditingController();
  final _phoneC = TextEditingController();
  final _emailC = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  // Pastors to create along with the church
  final List<Map<String, dynamic>> _pastors = [];

  void _addPastor() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    String type = 'assistant';

    // If no pastors yet, default to principal
    if (_pastors.isEmpty) {
      type = 'principal';
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Ajouter un pasteur'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneC,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'principal', label: Text('Principal'), icon: Icon(Icons.star)),
                    ButtonSegment(value: 'assistant', label: Text('Assistant'), icon: Icon(Icons.person_outline)),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => setDialogState(() => type = v.first),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                onPressed: () {
                  if (nameC.text.trim().isEmpty) {
                    showErrorSnackbar(ctx, 'Le nom est requis');
                    return;
                  }
                  setState(() {
                    // If this is principal, demote any existing principal
                    if (type == 'principal') {
                      for (var p in _pastors) {
                        if (p['pastor_type'] == 'principal') {
                          p['pastor_type'] = 'assistant';
                        }
                      }
                    }
                    _pastors.add({
                      'name': nameC.text.trim(),
                      'phone': phoneC.text.trim(),
                      'pastor_type': type,
                    });
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Ajouter'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final org = context.read<OrganizationProvider>();
    final result = await org.createChurch({
      'name': _nameC.text.trim(),
      'code': _codeC.text.trim(),
      'address': _addressC.text.trim(),
      'city': _cityC.text.trim(),
      'phone': _phoneC.text.trim(),
      'email': _emailC.text.trim(),
      'pastors': _pastors,
    });

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['status'] == 'success') {
      widget.onCreated();
      Navigator.pop(context);
      showSuccessSnackbar(context, result['message'] ?? 'Église créée');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _codeC.dispose();
    _addressC.dispose();
    _cityC.dispose();
    _phoneC.dispose();
    _emailC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.church, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('Nouvelle Église', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),

                // Church info section
                Text('Informations', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.primary)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameC,
                  decoration: const InputDecoration(labelText: 'Nom de l\'église *', prefixIcon: Icon(Icons.church)),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeC,
                        decoration: const InputDecoration(labelText: 'Code', prefixIcon: Icon(Icons.tag)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _cityC,
                        decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressC,
                  decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneC,
                        decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _emailC,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Pastors section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pasteurs', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.primary)),
                    TextButton.icon(
                      onPressed: _addPastor,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
                if (_pastors.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Aucun pasteur ajouté (optionnel)',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  )
                else
                  ..._pastors.asMap().entries.map((e) {
                    final i = e.key;
                    final p = e.value;
                    final isPrincipal = p['pastor_type'] == 'principal';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isPrincipal
                              ? AppColors.extended.withValues(alpha: 0.15)
                              : AppColors.secondary.withValues(alpha: 0.12),
                          child: Icon(
                            isPrincipal ? Icons.star : Icons.person,
                            size: 16,
                            color: isPrincipal ? AppColors.extended : AppColors.secondary,
                          ),
                        ),
                        title: Text(p['name'], style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          isPrincipal ? 'Principal' : 'Assistant',
                          style: TextStyle(fontSize: 11, color: isPrincipal ? AppColors.extended : Colors.grey),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _pastors.removeAt(i)),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 20),

                // Submit
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Créer l\'église'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
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
    final pastors = (church['pastors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final principal = pastors.where((p) => p['pastor_type'] == 'principal').toList();
    final pastorLabel = principal.isNotEmpty
        ? principal.first['name']
        : (church['pastor_name'] ?? '').toString();

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
                    Text(church['name'] ?? '',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if ((church['city'] ?? '').toString().isNotEmpty)
                      Text(church['city'],
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                    if (pastorLabel.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.person, size: 12, color: AppColors.extended),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(pastorLabel,
                                style: theme.textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (pastors.length > 1)
                            Text(' +${pastors.length - 1}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
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
              icon: const Icon(Icons.edit),
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
                                    child: Icon(Icons.church, color: AppColors.primary, size: 28),
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
                                  child: Icon(Icons.manage_accounts, color: AppColors.secondary),
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

  Widget _buildPastorsSection(ThemeData theme) {
    final pastors = (_detail!['pastors'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Pasteurs', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _showAddPastorDialog,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        if (pastors.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aucun pasteur enregistré',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ),
          )
        else
          ...pastors.map((p) {
            final isPrincipal = p['pastor_type'] == 'principal';
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isPrincipal
                      ? AppColors.extended.withValues(alpha: 0.15)
                      : AppColors.secondary.withValues(alpha: 0.12),
                  child: Icon(
                    isPrincipal ? Icons.star : Icons.person,
                    color: isPrincipal ? AppColors.extended : AppColors.secondary,
                  ),
                ),
                title: Text(p['name'] ?? ''),
                subtitle: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPrincipal ? AppColors.extended : AppColors.inProgress).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isPrincipal ? 'Principal' : 'Assistant',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPrincipal ? AppColors.extended : AppColors.inProgress,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if ((p['phone'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(p['phone'], style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => _handlePastorAction(action, p),
                  itemBuilder: (_) => [
                    if (!isPrincipal)
                      const PopupMenuItem(
                        value: 'promote',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.star, color: Colors.amber),
                          title: Text('Définir principal'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.archive, color: Colors.red),
                        title: Text('Archiver'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _handlePastorAction(String action, Map<String, dynamic> pastor) async {
    final org = context.read<OrganizationProvider>();
    Map<String, dynamic> result;

    if (action == 'promote') {
      result = await org.updatePastor(pastor['id'] as int, {'pastor_type': 'principal'});
    } else {
      result = await org.deletePastor(pastor['id'] as int);
    }

    if (!mounted) return;
    if (result['status'] == 'success') {
      showSuccessSnackbar(context, result['message'] ?? 'OK');
      _loadDetail();
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  void _showAddPastorDialog() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    String type = 'assistant';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ajouter un pasteur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Église: ${_detail?['name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Nom complet *', prefixIcon: Icon(Icons.person)),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'principal', label: Text('Principal'), icon: Icon(Icons.star)),
                  ButtonSegment(value: 'assistant', label: Text('Assistant'), icon: Icon(Icons.person_outline)),
                ],
                selected: {type},
                onSelectionChanged: (v) => setDialogState(() => type = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (nameC.text.trim().isEmpty) {
                  showErrorSnackbar(ctx, 'Le nom est requis');
                  return;
                }
                final org = context.read<OrganizationProvider>();
                final result = await org.createPastor({
                  'name': nameC.text.trim(),
                  'phone': phoneC.text.trim(),
                  'pastor_type': type,
                  'church_id': widget.churchId,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                if (result['status'] == 'success') {
                  showSuccessSnackbar(context, result['message'] ?? 'Pasteur ajouté');
                  _loadDetail();
                } else {
                  showErrorSnackbar(context, result['message'] ?? 'Erreur');
                }
              },
              child: const Text('Ajouter'),
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
}

// ─── Edit Church Bottom Sheet ────────────────────────────────────────

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
  late final TextEditingController _nameC;
  late final TextEditingController _codeC;
  late final TextEditingController _addressC;
  late final TextEditingController _cityC;
  late final TextEditingController _phoneC;
  late final TextEditingController _emailC;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.detail['name'] ?? '');
    _codeC = TextEditingController(text: widget.detail['code'] ?? '');
    _addressC = TextEditingController(text: widget.detail['address'] ?? '');
    _cityC = TextEditingController(text: widget.detail['city'] ?? '');
    _phoneC = TextEditingController(text: widget.detail['phone'] ?? '');
    _emailC = TextEditingController(text: widget.detail['email'] ?? '');
  }

  @override
  void dispose() {
    _nameC.dispose();
    _codeC.dispose();
    _addressC.dispose();
    _cityC.dispose();
    _phoneC.dispose();
    _emailC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameC.text.trim().isEmpty) {
      showErrorSnackbar(context, 'Le nom est requis');
      return;
    }
    setState(() => _submitting = true);

    final org = context.read<OrganizationProvider>();
    final result = await org.updateChurch(widget.churchId, {
      'name': _nameC.text.trim(),
      'code': _codeC.text.trim(),
      'address': _addressC.text.trim(),
      'city': _cityC.text.trim(),
      'phone': _phoneC.text.trim(),
      'email': _emailC.text.trim(),
    });

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['status'] == 'success') {
      widget.onUpdated();
      Navigator.pop(context);
      showSuccessSnackbar(context, 'Église mise à jour');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.edit, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Modifier l\'église',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameC,
                decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.church)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _codeC, decoration: const InputDecoration(labelText: 'Code', prefixIcon: Icon(Icons.tag)))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _cityC, decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: _addressC, decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: _phoneC, decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone)),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _emailC, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Les pasteurs se gèrent depuis la page de détail de l\'église.',
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
