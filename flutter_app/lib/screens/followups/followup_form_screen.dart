import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/followup_provider.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';
import 'followup_detail_screen.dart' show WeeksStepper;

class FollowupFormScreen extends StatefulWidget {
  /// Personne déjà choisie (depuis la liste « À attribuer », par exemple).
  final int? initialMemberId;
  const FollowupFormScreen({super.key, this.initialMemberId});

  @override
  State<FollowupFormScreen> createState() => _FollowupFormScreenState();
}

class _FollowupFormScreenState extends State<FollowupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedMemberId;
  int? _selectedEvangelistId;
  int _durationWeeks = 4;
  bool _durationTouched = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = widget.initialMemberId;
    _durationWeeks = context.read<AuthProvider>().defaultFollowupWeeks;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (!auth.isEvangelist) context.read<FollowupProvider>().loadEvangelists();
      await context.read<MemberProvider>().loadAssignable();
      if (mounted && _selectedMemberId != null) _applyProposal(_selectedMemberId);
    });
  }

  Map<String, dynamic>? _member(int? id) {
    for (final m in context.read<MemberProvider>().allMembers) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  /// La durée proposée pour la personne (événement d'origine ou réglage de
  /// l'église) pré-remplit le choix, tant que l'évangéliste n'y a pas touché.
  void _applyProposal(int? memberId) {
    final proposed = _member(memberId)?['proposed_followup_weeks'];
    if (!_durationTouched && proposed is int && proposed > 0) {
      setState(() => _durationWeeks = proposed.clamp(AppConstants.minFollowupWeeks, AppConstants.maxFollowupWeeks));
    }
  }

  Future<void> _save() async {
    final isEvangelist = context.read<AuthProvider>().isEvangelist;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMemberId == null || (!isEvangelist && _selectedEvangelistId == null)) {
      showErrorSnackbar(context, 'Veuillez choisir la personne et l\'évangéliste');
      return;
    }

    setState(() => _isSaving = true);
    final result = await context.read<FollowupProvider>().createFollowup({
      'member_id': _selectedMemberId,
      if (!isEvangelist) 'evangelist_id': _selectedEvangelistId,
      'duration_weeks': _durationWeeks,
    });
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['status'] == 'success') {
      showSuccessSnackbar(context, 'Suivi ouvert pour $_durationWeeks semaines');
      Navigator.pop(context, true);
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberProvider = context.watch<MemberProvider>();
    final followupProvider = context.watch<FollowupProvider>();
    final isEvangelist = context.watch<AuthProvider>().isEvangelist;
    final theme = Theme.of(context);
    final member = _member(_selectedMemberId);
    final proposedLabel = AppConstants.safeStr(member?['proposed_followup_label']);
    final members = memberProvider.allMembers.where((m) => m['id'] is int).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau suivi')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _section(
              theme,
              'Personne à suivre',
              memberProvider.isLoading && members.isEmpty
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<int>(
                      // Reconstruit quand la liste arrive : la sélection initiale s'y applique.
                      key: ValueKey('members-${members.length}'),
                      decoration: const InputDecoration(
                        hintText: 'Choisir une personne',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      isExpanded: true,
                      items: members
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text(
                                  '${m['name'] ?? ''} ${m['first_name'] ?? ''}'.trim() +
                                      (m['member_type'] == 'interrupted' ? ' — reprise' : ''),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedMemberId = v);
                        _applyProposal(v);
                      },
                      initialValue: members.any((m) => m['id'] == _selectedMemberId) ? _selectedMemberId : null,
                      validator: (_) => _selectedMemberId == null ? 'Requis' : null,
                    ),
            ),
            const SizedBox(height: 12),
            if (!isEvangelist) ...[
              _section(
                theme,
                'Évangéliste',
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    hintText: 'Choisir un évangéliste',
                    prefixIcon: Icon(Icons.person_pin_outlined),
                  ),
                  items: followupProvider.evangelists
                      .where((e) => e['id'] is int)
                      .map((e) => DropdownMenuItem(value: e['id'] as int, child: Text(e['name'] ?? '')))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedEvangelistId = v),
                  initialValue: _selectedEvangelistId,
                  validator: (_) => _selectedEvangelistId == null ? 'Requis' : null,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _section(
              theme,
              'Durée du suivi',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeeksStepper(
                    value: _durationWeeks,
                    onChanged: (v) => setState(() {
                      _durationWeeks = v;
                      _durationTouched = true;
                    }),
                  ),
                  if (proposedLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('Proposé : $proposedLabel',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Ouvrir le suivi', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
