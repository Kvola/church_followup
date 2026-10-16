import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';
import 'followup_form_screen.dart';

/// Les personnes qui attendent qu'un évangéliste leur soit confié : nouvelles
/// (saisies ou venues d'un événement) et suivis interrompus à reprendre.
class ToAssignScreen extends StatefulWidget {
  const ToAssignScreen({super.key});

  @override
  State<ToAssignScreen> createState() => _ToAssignScreenState();
}

class _ToAssignScreenState extends State<ToAssignScreen> {
  List<Map<String, dynamic>> _fresh = [];
  List<Map<String, dynamic>> _interrupted = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<AuthProvider>().api.getPeopleToAssign();
      if (!mounted) return;
      setState(() {
        _fresh = data['members'] ?? [];
        _interrupted = data['interrupted'] ?? [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> member) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FollowupFormScreen(initialMember: member)),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _fresh.isEmpty && _interrupted.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('À attribuer')),
      body: _loading && empty
          ? const ShimmerList(itemCount: 4)
          : _error != null && empty
              ? ErrorState(message: _error!, onRetry: _load)
              : empty
                  ? const EmptyState(
                      icon: Icons.how_to_reg_outlined,
                      title: 'Personne n\'attend de suivi',
                      subtitle: 'Les personnes venues d\'un événement ou saisies sans suivi apparaissent ici.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_fresh.isNotEmpty) ...[
                            SectionHeader(title: 'Nouvelles personnes (${_fresh.length})'),
                            const SizedBox(height: 8),
                            ..._fresh.map((m) => _PersonCard(
                                  member: m,
                                  subtitle: AppConstants.safeStr(m['proposed_followup_label']),
                                  color: AppColors.inProgress,
                                  onTap: () => _assign(m),
                                )),
                            const SizedBox(height: 16),
                          ],
                          if (_interrupted.isNotEmpty) ...[
                            SectionHeader(title: 'Suivis interrompus (${_interrupted.length})'),
                            const SizedBox(height: 8),
                            ..._interrupted.map((m) => _PersonCard(
                                  member: m,
                                  subtitle: [
                                    AppConstants.safeStr(m['abandon_reason_label']),
                                    AppConstants.safeStr(m['abandon_note']),
                                  ].where((t) => t.isNotEmpty).join(' — '),
                                  color: AppColors.abandoned,
                                  actionLabel: 'Reprendre',
                                  onTap: () => _assign(m),
                                )),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final String subtitle;
  final Color color;
  final String actionLabel;
  final VoidCallback onTap;

  const _PersonCard({
    required this.member,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.actionLabel = 'Confier',
  });

  @override
  Widget build(BuildContext context) {
    final name = '${member['name'] ?? ''} ${member['first_name'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(AppConstants.initial(name), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: FilledButton.tonal(onPressed: onTap, child: Text(actionLabel)),
        onTap: onTap,
      ),
    );
  }
}
