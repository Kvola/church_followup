import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/followup_provider.dart';
import '../../widgets/common.dart';
import 'followup_detail_screen.dart';
import 'followup_form_screen.dart';

class FollowupListScreen extends StatefulWidget {
  const FollowupListScreen({super.key});

  @override
  State<FollowupListScreen> createState() => _FollowupListScreenState();
}

class _FollowupListScreenState extends State<FollowupListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FollowupProvider>().loadFollowups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FollowupProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isEvangelist ? 'Mes suivis' : 'Suivis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.loadFollowups(),
          ),
        ],
      ),
      body: Column(
        children: [
          // State filter chips
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _FilterChip(
                  label: 'Tous',
                  selected: provider.stateFilter == null,
                  onSelected: () => provider.setStateFilter(null),
                ),
                ...AppConstants.stateLabels.entries.map((e) => _FilterChip(
                      label: e.value,
                      selected: provider.stateFilter == e.key,
                      color: AppColors.stateColor(e.key),
                      onSelected: () => provider.setStateFilter(e.key),
                    )),
              ],
            ),
          ),

          // List
          Expanded(
            child: provider.isLoading && provider.followups.isEmpty
                ? const ShimmerList()
                : provider.error != null && provider.followups.isEmpty
                    ? ErrorState(message: provider.error!, onRetry: () => provider.loadFollowups())
                    : provider.followups.isEmpty
                        ? EmptyState(
                            icon: Icons.assignment_outlined,
                            title: 'Aucun suivi trouvé',
                            subtitle: provider.stateFilter != null ? 'Changez le filtre pour voir d\'autres suivis' : null,
                          )
                        : RefreshIndicator(
                            onRefresh: () => provider.loadFollowups(),
                            child: AnimationLimiter(
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                                itemCount: provider.followups.length,
                                itemBuilder: (context, index) {
                                  return AnimationConfiguration.staggeredList(
                                    position: index,
                                    duration: const Duration(milliseconds: 375),
                                    child: SlideAnimation(
                                      verticalOffset: 50,
                                      child: FadeInAnimation(
                                        child: _FollowupCard(
                                          data: provider.followups[index],
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => FollowupDetailScreen(
                                                followupId: provider.followups[index]['id'],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: (auth.isManager || auth.isEvangelist)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const FollowupFormScreen()),
                );
                if (created == true) provider.loadFollowups();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nouveau'),
            )
          : null,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onSelected;

  const _FilterChip({required this.label, required this.selected, this.color, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
        checkmarkColor: color ?? Theme.of(context).colorScheme.primary,
        side: selected ? BorderSide(color: (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.4)) : null,
      ),
    );
  }
}

class _FollowupCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _FollowupCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = data['state'] ?? '';
    final stateColor = AppColors.stateColor(state);
    final memberName = data['member_name'] ?? 'Inconnu';
    final evangelistName = data['evangelist_name'] ?? '';
    final weeksCompleted = data['current_week'] ?? data['week_count'] ?? 0;
    final durationWeeks = data['duration_weeks'] ?? 0;
    final avgScore = (data['average_score'] ?? 0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: stateColor.withValues(alpha: 0.12),
                child: Text(
                  memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
                  style: TextStyle(color: stateColor, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memberName,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (evangelistName.isNotEmpty)
                      Text(
                        '→ $evangelistName',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StateBadge(state: state, small: true),
                        const SizedBox(width: 8),
                        Icon(Icons.calendar_today, size: 12, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          '$weeksCompleted/$durationWeeks sem.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Score
              if (avgScore > 0) ScoreIndicator(score: avgScore),
            ],
          ),
        ),
      ),
    );
  }
}
