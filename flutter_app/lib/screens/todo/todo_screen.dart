import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/todo_provider.dart';
import '../../widgets/common.dart';
import '../checkpoints/checkpoint_list_screen.dart';
import '../followups/followup_detail_screen.dart';
import '../followups/followup_form_screen.dart';
import '../followups/to_assign_screen.dart';
import '../members/member_list_screen.dart';

/// Apparence de chaque type de tâche renvoyé par /api/church/todo.
const Map<String, (IconData, Color)> _kinds = {
  'decision_due': (Icons.gavel_outlined, AppColors.abandoned),
  'report_overdue': (Icons.edit_note, AppColors.extended),
  'checkpoint_due': (Icons.fact_check_outlined, AppColors.inProgress),
  'reopen_suggested': (Icons.replay_outlined, AppColors.abandoned),
  'to_assign': (Icons.person_add_alt_1_outlined, AppColors.primary),
  'evangelist_late': (Icons.schedule, AppColors.extended),
  'cell_late': (Icons.schedule, AppColors.extended),
  'to_complete': (Icons.badge_outlined, Colors.grey),
};

/// Ce qui attend l'utilisateur : chaque ligne mène là où elle se traite.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<TodoProvider>().load());
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final todo = context.read<TodoProvider>();
    final id = AppConstants.safeId(item['followup_id']);
    Widget? screen;
    switch (item['kind']) {
      case 'decision_due':
      case 'report_overdue':
        if (id != null) screen = FollowupDetailScreen(followupId: id);
      case 'to_assign':
        screen = const ToAssignScreen();
      case 'reopen_suggested':
        screen = FollowupFormScreen(initialMember: {
          'id': item['member_id'],
          'name': AppConstants.safeStr(item['title']).replaceFirst('Rouvrir un suivi ? ', ''),
        });
      case 'checkpoint_due':
        screen = const CheckpointListScreen();
      case 'to_complete':
        screen = const MemberListScreen();
    }
    if (screen == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen!));
    // Revenu de la tâche : elle a peut-être disparu.
    todo.load();
  }

  @override
  Widget build(BuildContext context) {
    final todo = context.watch<TodoProvider>();
    final name = context.watch<AuthProvider>().userName.split(' ').first;
    return Scaffold(
      appBar: AppBar(title: const Text('À faire')),
      body: todo.isLoading && todo.items.isEmpty
          ? const ShimmerList(itemCount: 4)
          : todo.error != null && todo.items.isEmpty
              ? ErrorState(message: todo.error!, onRetry: todo.load)
              : RefreshIndicator(
                  onRefresh: todo.load,
                  child: todo.items.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.task_alt,
                            title: 'Rien à faire pour l\'instant',
                            subtitle: name.isEmpty ? null : 'Bravo $name, tout est à jour.',
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (todo.summary.isNotEmpty) ...[
                              Text(todo.summary, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 12),
                            ],
                            ...todo.items.map((item) {
                              final (icon, color) = _kinds[item['kind']] ?? (Icons.circle_outlined, Colors.grey);
                              final tappable = item['kind'] != 'evangelist_late' && item['kind'] != 'cell_late';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.12),
                                    child: Icon(icon, color: color),
                                  ),
                                  title: Text(AppConstants.safeStr(item['title']),
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: AppConstants.safeStr(item['detail']).isEmpty
                                      ? null
                                      : Text(AppConstants.safeStr(item['detail'])),
                                  trailing: tappable ? const Icon(Icons.chevron_right) : null,
                                  onTap: tappable ? () => _open(item) : null,
                                ),
                              );
                            }),
                          ],
                        ),
                ),
    );
  }
}
