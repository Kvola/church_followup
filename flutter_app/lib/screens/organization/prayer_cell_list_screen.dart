import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';
import 'unit_forms.dart';

class PrayerCellListScreen extends StatefulWidget {
  const PrayerCellListScreen({super.key});

  @override
  State<PrayerCellListScreen> createState() => _PrayerCellListScreenState();
}

class _PrayerCellListScreenState extends State<PrayerCellListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadCells();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isManager;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'new-cell',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CellFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle cellule'),
            )
          : null,
      appBar: AppBar(
        title: const Text('Cellules de prière'),
        actions: [
          if (canManage)
            IconButton(
              icon: Icon(provider.showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
              tooltip: provider.showArchived ? 'Masquer les archivés' : 'Afficher les archivés',
              onPressed: () => provider.showArchived = !provider.showArchived,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadCells()),
        ],
      ),
      body: provider.isLoading && provider.cells.isEmpty
          ? const ShimmerList()
          : provider.error != null && provider.cells.isEmpty
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadCells())
              : provider.cells.isEmpty
                  ? const EmptyState(icon: Icons.groups_outlined, title: 'Aucune cellule de prière')
                  : RefreshIndicator(
                      onRefresh: () => provider.loadCells(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: provider.cells.length,
                        itemBuilder: (_, index) => _CellCard(
                          data: provider.cells[index],
                          // Le responsable d'église, ou le responsable de CETTE cellule.
                          canEdit: canManage || auth.isCellLeader,
                        ),
                      ),
                    ),
    );
  }
}

class _CellCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool canEdit;
  const _CellCard({required this.data, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final leaderName = data['leader_name'] ?? '';
    final leaderPhone = data['leader_phone'] ?? '';
    final meetingDay = data['meeting_day'] ?? '';
    final meetingTime = data['meeting_time'] ?? '';
    final location = AppConstants.safeStr(data['meeting_location']);
    final districts = data['district_names'] is List ? (data['district_names'] as List).join(', ') : '';
    final archived = data['active'] == false;
    final rawMembers = data['members'];
    final members = rawMembers is List ? rawMembers : <dynamic>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.inProgress.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '${members.length}',
              style: const TextStyle(color: AppColors.inProgress, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        title: Row(children: [
          Flexible(child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: archived ? Colors.grey : null))),
          if (archived) const ArchivedChip(),
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leaderName.isNotEmpty)
              Text('Responsable : $leaderName', style: theme.textTheme.bodySmall),
            if (districts.isNotEmpty)
              Text(districts, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (meetingDay.isNotEmpty)
              Text(
                '${AppConstants.dayLabels[meetingDay] ?? meetingDay}${meetingTime.isNotEmpty ? ' à $meetingTime' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (location.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 18),
              title: Text(location),
              contentPadding: EdgeInsets.zero,
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => CellFormScreen(cell: data))),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier'),
              ),
            ),
          if (leaderPhone.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.phone, size: 18),
              title: Text(leaderPhone),
              contentPadding: EdgeInsets.zero,
            ),
          const Divider(),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Aucun membre', style: TextStyle(color: Colors.grey)),
            )
          else
            ...members.map((m) {
              final member = Map<String, dynamic>.from(m);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    AppConstants.initial(member['name']),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text('${member['name'] ?? ''} ${member['first_name'] ?? ''}'.trim()),
                subtitle: AppConstants.safeStr(member['phone']).isNotEmpty
                    ? Text(AppConstants.safeStr(member['phone']), style: const TextStyle(fontSize: 12))
                    : null,
                contentPadding: EdgeInsets.zero,
              );
            }),
        ],
      ),
    );
  }
}
