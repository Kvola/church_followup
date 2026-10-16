import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';
import 'member_form_screen.dart';

class MemberListScreen extends StatefulWidget {
  const MemberListScreen({super.key});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MemberProvider>().loadMembers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemberProvider>();

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un membre...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
                onChanged: provider.setSearch,
              )
            : const Text('Membres'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) provider.setSearch('');
              });
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => provider.loadMembers()),
        ],
      ),
      body: provider.isLoading && provider.allMembers.isEmpty
          ? const ShimmerList()
          : provider.error != null && provider.allMembers.isEmpty
              ? ErrorState(message: provider.error!, onRetry: () => provider.loadMembers())
              : provider.members.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outlined,
                      title: provider.searchQuery.isNotEmpty ? 'Aucun résultat pour "${provider.searchQuery}"' : 'Aucun membre',
                    )
                  : RefreshIndicator(
                      onRefresh: () => provider.loadMembers(),
                      child: AnimationLimiter(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: provider.members.length,
                          itemBuilder: (context, index) {
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 50,
                                child: FadeInAnimation(
                                  child: _MemberCard(
                                    data: provider.members[index],
                                    onTap: () => _openDetail(provider.members[index]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const MemberFormScreen()),
          );
          if (created == true) provider.loadMembers();
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> member) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(memberId: member['id'], existingData: member),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _MemberCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = '${data['name'] ?? ''} ${data['first_name'] ?? ''}'.trim();
    final phone = data['phone'] ?? '';
    final memberType = data['member_type'] ?? '';
    final gender = data['gender'] ?? '';

    final typeColor = switch (memberType) {
      'integrated' => AppColors.integrated,
      'established' => AppColors.stateColor('established'),
      'in_followup' => AppColors.inProgress,
      'new' => AppColors.extended,
      'interrupted' => AppColors.abandoned,
      _ => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: typeColor.withValues(alpha: 0.12),
          child: Icon(
            gender == 'female' ? Icons.person_2 : Icons.person,
            color: typeColor,
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(phone, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (data['person_profile'] == 'old_member' && memberType != 'old_member')
                  const ProfileBadge(profile: 'old_member'),
                _tag(AppConstants.memberTypeLabels[memberType] ?? memberType, typeColor),
                // Le sexe manque : la fiche est à compléter, plutôt qu'un sexe inventé.
                if (data['to_complete'] == true) _tag('À compléter', AppColors.abandoned),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
