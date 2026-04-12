import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/followup_provider.dart';
import '../../widgets/common.dart';

class EvangelistListScreen extends StatefulWidget {
  const EvangelistListScreen({super.key});

  @override
  State<EvangelistListScreen> createState() => _EvangelistListScreenState();
}

class _EvangelistListScreenState extends State<EvangelistListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FollowupProvider>().loadEvangelists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FollowupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Évangélistes'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadEvangelists()),
        ],
      ),
      body: provider.evangelists.isEmpty && provider.isLoading
          ? const ShimmerList()
          : provider.evangelists.isEmpty
              ? const EmptyState(icon: Icons.people_alt_outlined, title: 'Aucun évangéliste')
              : RefreshIndicator(
                  onRefresh: () => provider.loadEvangelists(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: provider.evangelists.length,
                    itemBuilder: (_, index) => _EvangelistCard(data: provider.evangelists[index]),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
      ),
    );
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvel évangéliste'),
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
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final result = await context.read<FollowupProvider>().createEvangelist(
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                  );
              if (mounted) {
                if (result['status'] == 'success') {
                  showSuccessSnackbar(context, 'Évangéliste créé');
                } else {
                  showErrorSnackbar(context, result['message'] ?? 'Erreur');
                }
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }
}

class _EvangelistCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _EvangelistCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final phone = data['phone'] ?? '';
    final activeCount = data['active_followup_count'] ?? 0;
    final integratedCount = data['integrated_count'] ?? 0;
    final rate = (data['integration_rate'] ?? 0).toDouble();

    final rateColor = rate >= 70
        ? AppColors.integrated
        : rate >= 40
            ? AppColors.extended
            : rate == 0
                ? Colors.grey
                : AppColors.abandoned;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      if (phone.isNotEmpty) Text(phone, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                // Rate badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: rateColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    rate > 0 ? '${rate.toStringAsFixed(0)}%' : '—',
                    style: TextStyle(color: rateColor, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniStat('Actifs', '$activeCount', AppColors.inProgress),
                const SizedBox(width: 16),
                _miniStat('Intégrés', '$integratedCount', AppColors.integrated),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$value ', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
