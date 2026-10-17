import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/followup_provider.dart';
import '../../providers/member_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';
import 'followup_detail_screen.dart' show WeeksStepper;

class FollowupFormScreen extends StatefulWidget {
  /// Personne déjà choisie (depuis « À attribuer » ou « À faire »). Elle est
  /// proposée même si elle n'est ni nouvelle ni interrompue (suivi rouvert
  /// après deux contrôles défavorables).
  final Map<String, dynamic>? initialMember;
  const FollowupFormScreen({super.key, this.initialMember});

  @override
  State<FollowupFormScreen> createState() => _FollowupFormScreenState();
}

class _FollowupFormScreenState extends State<FollowupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedMemberId;
  int? _selectedEvangelistId;

  /// Un ancien membre est suivi par une cellule de prière (proposée : la sienne).
  int? _selectedCellId;
  int _durationWeeks = 4;
  bool _durationTouched = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMemberId = AppConstants.safeId(widget.initialMember?['id']);
    _durationWeeks = context.read<AuthProvider>().defaultFollowupWeeks;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (!auth.isEvangelist) {
        context.read<FollowupProvider>().loadEvangelists();
        context.read<OrganizationProvider>().loadCells();
      }
      await context.read<MemberProvider>().loadAssignable();
      if (mounted && _selectedMemberId != null) _applyProposal(_selectedMemberId);
    });
  }

  List<Map<String, dynamic>> _candidates(List<Map<String, dynamic>> loaded) {
    final initial = widget.initialMember;
    // Un évangéliste ne suit que des nouvelles personnes : les anciens membres
    // sont confiés à une cellule, par le responsable.
    final evangelist = context.read<AuthProvider>().isEvangelist;
    final list = loaded
        .where((m) => m['id'] is int && !(evangelist && m['person_profile'] == 'old_member'))
        .toList();
    if (initial != null && initial['id'] is int && !list.any((m) => m['id'] == initial['id'])) {
      list.insert(0, initial);
    }
    return list;
  }

  Map<String, dynamic>? _member(int? id) {
    for (final m in _candidates(context.read<MemberProvider>().allMembers)) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  /// La durée proposée pour la personne (événement d'origine ou réglage de
  /// l'église) pré-remplit le choix, tant que l'évangéliste n'y a pas touché.
  bool get _forCell => _member(_selectedMemberId)?['person_profile'] == 'old_member';

  void _applyProposal(int? memberId) {
    final cell = _member(memberId)?['prayer_cell_id'];
    setState(() => _selectedCellId = cell is int ? cell : null);
    final proposed = _member(memberId)?['proposed_followup_weeks'];
    if (!_durationTouched && proposed is int && proposed > 0) {
      setState(() => _durationWeeks = proposed.clamp(AppConstants.minFollowupWeeks, AppConstants.maxFollowupWeeks));
    }
  }

  Future<void> _save() async {
    final isEvangelist = context.read<AuthProvider>().isEvangelist;
    if (!_formKey.currentState!.validate()) return;
    final forCell = _forCell;
    if (_selectedMemberId == null ||
        (forCell ? _selectedCellId == null : !isEvangelist && _selectedEvangelistId == null)) {
      showErrorSnackbar(context, forCell
          ? 'Choisissez la cellule qui suivra cet ancien membre'
          : 'Veuillez choisir la personne et l\'évangéliste');
      return;
    }

    setState(() => _isSaving = true);
    final result = await context.read<FollowupProvider>().createFollowup({
      'member_id': _selectedMemberId,
      if (forCell) 'prayer_cell_id': _selectedCellId,
      if (!forCell && !isEvangelist) 'evangelist_id': _selectedEvangelistId,
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
    final members = _candidates(memberProvider.allMembers);
    final forCell = _forCell;
    final cells = context.watch<OrganizationProvider>().activeCells.where((c) => c['id'] is int).toList();

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
                                      (m['member_type'] == 'interrupted' ? ' — reprise' : '') +
                                      (m['person_profile'] == 'old_member' ? ' — ancien membre' : ''),
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
            if (forCell) ...[
              _section(
                theme,
                'Cellule qui suit',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Un ancien membre est suivi par une cellule de prière : son responsable rédige '
                      'les rapports et décide au terme.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey('cells-${cells.length}-$_selectedCellId'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'Choisir une cellule',
                        prefixIcon: Icon(Icons.groups_outlined),
                      ),
                      items: cells
                          .map((c) => DropdownMenuItem(
                                value: c['id'] as int,
                                // Sans responsable qui puisse se connecter, personne ne suivrait.
                                enabled: c['has_leader_account'] != false,
                                child: Text(
                                  c['has_leader_account'] == false
                                      ? '${c['name'] ?? ''} — sans responsable connecté'
                                      : '${c['name'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCellId = v),
                      initialValue: cells.any((c) => c['id'] == _selectedCellId) ? _selectedCellId : null,
                      validator: (_) => _selectedCellId == null ? 'Requis' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else if (!isEvangelist) ...[
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
