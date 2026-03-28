import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class AgeGroupListScreen extends StatefulWidget {
  const AgeGroupListScreen({super.key});

  @override
  State<AgeGroupListScreen> createState() => _AgeGroupListScreenState();
}

class _AgeGroupListScreenState extends State<AgeGroupListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadAgeGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groupes d\'âge'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadAgeGroups()),
        ],
      ),
      body: provider.isLoading && provider.ageGroups.isEmpty
          ? const ShimmerList()
          : provider.error != null && provider.ageGroups.isEmpty
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadAgeGroups())
              : provider.ageGroups.isEmpty
                  ? const EmptyState(icon: Icons.diversity_3_outlined, title: 'Aucun groupe d\'âge')
                  : RefreshIndicator(
                      onRefresh: () => provider.loadAgeGroups(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.ageGroups.length,
                        itemBuilder: (_, index) => _GroupCard(data: provider.ageGroups[index]),
                      ),
                    ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _GroupCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = data['name'] ?? '';
    final groupType = data['group_type'] ?? '';
    final leaderName = data['leader_name'] ?? '';
    final leaderPhone = data['leader_phone'] ?? '';
    final gender = data['gender'] ?? '';
    final rawMembers = data['members'];
    final members = rawMembers is List ? rawMembers : <dynamic>[];

    final typeColor = _typeColor(groupType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(_typeIcon(groupType), color: typeColor, size: 22),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                AppConstants.groupTypeLabels[groupType] ?? groupType,
                style: TextStyle(fontSize: 11, color: typeColor, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text('${members.length} membres', style: theme.textTheme.bodySmall),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (leaderName.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_pin, size: 18),
              title: Text('Leader: $leaderName'),
              subtitle: leaderPhone.isNotEmpty ? Text(leaderPhone) : null,
              contentPadding: EdgeInsets.zero,
            ),
          if (gender.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.wc, size: 18),
              title: Text(AppConstants.genderLabels[gender] ?? gender),
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
                  backgroundColor: typeColor.withValues(alpha: 0.1),
                  child: Text(
                    AppConstants.initial(member['name']),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text('${member['name'] ?? ''} ${member['first_name'] ?? ''}'.trim()),
                contentPadding: EdgeInsets.zero,
              );
            }),
        ],
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'married':
        return AppColors.primary;
      case 'youth':
        return AppColors.inProgress;
      case 'college':
        return AppColors.extended;
      case 'highschool':
        return AppColors.transferred;
      case 'children':
        return AppColors.integrated;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'married':
        return Icons.people;
      case 'youth':
        return Icons.directions_run;
      case 'college':
        return Icons.school;
      case 'highschool':
        return Icons.menu_book;
      case 'children':
        return Icons.child_care;
      default:
        return Icons.group;
    }
  }
}
