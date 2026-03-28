import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cellules de prière'),
        actions: [
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
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.cells.length,
                        itemBuilder: (_, index) => _CellCard(data: provider.cells[index]),
                      ),
                    ),
    );
  }
}

class _CellCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CellCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final leaderName = data['leader_name'] ?? '';
    final leaderPhone = data['leader_phone'] ?? '';
    final meetingDay = data['meeting_day'] ?? '';
    final meetingTime = data['meeting_time'] ?? '';
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
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leaderName.isNotEmpty)
              Text('Leader: $leaderName', style: theme.textTheme.bodySmall),
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
