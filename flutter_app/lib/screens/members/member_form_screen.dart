import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/member_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class MemberFormScreen extends StatefulWidget {
  final int? memberId;
  final Map<String, dynamic>? existingData;

  const MemberFormScreen({super.key, this.memberId, this.existingData});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isEdit = false;

  /// Le serveur dit si l'on a la charge de cette personne ; sinon, lecture seule.
  bool _canEdit = true;

  // Controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _professionCtrl;

  String? _gender;
  String? _maritalStatus;

  /// Nouvelle personne ou ancien membre : choisi à l'enregistrement, il ne
  /// change pas avec le parcours.
  String _profile = 'new';
  int? _districtId;
  int? _cellId;
  int? _ageGroupId;
  int? _invitedById;
  int? _mentorId;
  DateTime? _birthday;
  DateTime? _salvationDate;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.memberId != null;
    final d = widget.existingData ?? {};

    _nameCtrl = TextEditingController(text: d['name'] ?? '');
    _firstNameCtrl = TextEditingController(text: d['first_name'] ?? '');
    _phoneCtrl = TextEditingController(text: d['phone'] ?? '');
    _addressCtrl = TextEditingController(text: d['address'] ?? '');
    _professionCtrl = TextEditingController(text: d['profession'] ?? '');
    _gender = AppConstants.genderLabels.containsKey(d['gender']) ? d['gender'] : null;
    if (AppConstants.profileLabels.containsKey(d['person_profile'])) _profile = d['person_profile'];
    _maritalStatus = d['marital_status'] is String ? d['marital_status'] : null;
    _districtId = AppConstants.safeId(d['district_id']);
    _cellId = AppConstants.safeId(d['prayer_cell_id']);
    _ageGroupId = AppConstants.safeId(d['age_group_id']);
    _invitedById = AppConstants.safeId(d['invited_by_id']);
    _mentorId = AppConstants.safeId(d['mentor_id']);

    if (d['date_of_birth'] != null && d['date_of_birth'] != false) {
      _birthday = DateTime.tryParse(d['date_of_birth'].toString());
    }
    if (d['salvation_date'] != null && d['salvation_date'] != false) {
      _salvationDate = DateTime.tryParse(d['salvation_date'].toString());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final org = context.read<OrganizationProvider>();
      org.loadDistricts();
      org.loadCells();
      org.loadAgeGroups();

      // Load members for invited_by and mentor dropdowns
      context.read<MemberProvider>().loadMembers();

      if (_isEdit && widget.memberId != null) {
        final members = context.read<MemberProvider>();
        members.loadDetail(widget.memberId!).then((_) {
          final detail = members.currentDetail;
          if (detail != null && mounted) {
            setState(() {
              _canEdit = detail['can_edit'] != false;
              _nameCtrl.text = detail['name'] ?? _nameCtrl.text;
              _firstNameCtrl.text = detail['first_name'] ?? _firstNameCtrl.text;
              _phoneCtrl.text = detail['phone'] ?? _phoneCtrl.text;
              _addressCtrl.text = detail['address'] ?? _addressCtrl.text;
              _professionCtrl.text = detail['profession'] ?? _professionCtrl.text;
              _gender = AppConstants.genderLabels.containsKey(detail['gender']) ? detail['gender'] : _gender;
              if (AppConstants.profileLabels.containsKey(detail['person_profile'])) {
                _profile = detail['person_profile'];
              }
              _maritalStatus = detail['marital_status'] is String ? detail['marital_status'] : _maritalStatus;

              _districtId = AppConstants.safeId(detail['district_id']) ?? _districtId;
              _cellId = AppConstants.safeId(detail['prayer_cell_id']) ?? _cellId;
              _ageGroupId = AppConstants.safeId(detail['age_group_id']) ?? _ageGroupId;
              _invitedById = AppConstants.safeId(detail['invited_by_id']) ?? _invitedById;
              _mentorId = AppConstants.safeId(detail['mentor_id']) ?? _mentorId;

              if (detail['date_of_birth'] != null && detail['date_of_birth'] != false) {
                _birthday = DateTime.tryParse(detail['date_of_birth'].toString()) ?? _birthday;
              }
              if (detail['salvation_date'] != null && detail['salvation_date'] != false) {
                _salvationDate = DateTime.tryParse(detail['salvation_date'].toString()) ?? _salvationDate;
              }
            });
          }
        });
      }
    });
  }

  /// Returns the value only if it exists in the items list, preventing
  /// the Flutter assertion "There should be exactly one item with [DropdownButton]'s value".
  int? _validDropdownValue(int? value, List<Map<String, dynamic>> items) {
    if (value == null) return null;
    return items.any((item) => item['id'] == value) ? value : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _firstNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _professionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool confirmNew = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'first_name': _firstNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'gender': _gender,
      'marital_status': _maritalStatus,
      'address': _addressCtrl.text.trim(),
      'profession': _professionCtrl.text.trim(),
      if (_choosesProfile) 'person_profile': _profile,
      if (confirmNew) 'confirm_new': true,
    };

    if (_districtId != null) data['district_id'] = _districtId;
    // Cellule et groupe : décisions de responsable (le serveur les ignore sinon).
    if (context.read<AuthProvider>().isManager) {
      if (_cellId != null) data['prayer_cell_id'] = _cellId;
      if (_ageGroupId != null) data['age_group_id'] = _ageGroupId;
    }
    if (_invitedById != null) data['invited_by_id'] = _invitedById;
    if (_mentorId != null) data['mentor_id'] = _mentorId;
    if (_birthday != null) data['date_of_birth'] = _birthday!.toIso8601String().split('T')[0];
    if (_salvationDate != null) data['salvation_date'] = _salvationDate!.toIso8601String().split('T')[0];

    final provider = context.read<MemberProvider>();
    final result = _isEdit
        ? await provider.updateMember(widget.memberId!, data)
        : await provider.createMember(data);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['status'] == 'success') {
      showSuccessSnackbar(context, _isEdit ? 'Membre mis à jour' : 'Membre créé');
      Navigator.pop(context, true);
    } else if (result['code'] == 'duplicate_person') {
      await _onDuplicate(result);
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  /// Le responsable de cellule ou de groupe enregistre des membres de son unité
  /// (le serveur en fait des anciens membres) : il n'a pas à choisir.
  bool get _choosesProfile {
    final auth = context.read<AuthProvider>();
    return !auth.isCellLeader && !auth.isGroupLeader;
  }

  /// Cette personne semble déjà enregistrée : la voir, ou confirmer que c'en est une autre.
  Future<void> _onDuplicate(Map<String, dynamic> result) async {
    final duplicate = result['duplicate'] is Map ? Map<String, dynamic>.from(result['duplicate']) : null;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déjà enregistrée ?'),
        content: Text('${result['message'] ?? ''}\n\nS\'il s\'agit bien d\'une autre personne, enregistrez-la quand même.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          if (duplicate?['id'] is int)
            TextButton(onPressed: () => Navigator.pop(ctx, 'open'), child: const Text('Voir sa fiche')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'new'), child: const Text('C\'est une autre personne')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'new') {
      await _save(confirmNew: true);
    } else if (choice == 'open') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MemberFormScreen(memberId: duplicate!['id'] as int, existingData: duplicate)),
      );
    }
  }

  Future<void> _pickDate(bool isBirthday) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isBirthday ? _birthday : _salvationDate) ?? DateTime(2000),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isBirthday) {
          _birthday = picked;
        } else {
          _salvationDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationProvider>();
    final isManager = context.watch<AuthProvider>().isManager;

    return Scaffold(
      appBar: AppBar(title: Text(!_canEdit ? 'Fiche du membre' : _isEdit ? 'Modifier le membre' : 'Enregistrer une personne')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_canEdit) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.extended.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility_outlined, color: AppColors.extended),
                    SizedBox(width: 10),
                    Expanded(child: Text('Consultation seulement : vous ne modifiez que les personnes dont vous avez la charge.')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Identity section
            const _SectionTitle('Identité'),
            const SizedBox(height: 8),
            if (_choosesProfile) ...[
              SegmentedButton<String>(
                segments: AppConstants.profileLabels.entries
                    .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                    .toList(),
                selected: {_profile},
                onSelectionChanged: _canEdit ? (v) => setState(() => _profile = v.first) : null,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstNameCtrl,
              decoration: const InputDecoration(labelText: 'Prénom *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Téléphone *', prefixIcon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Sexe *'),
                    initialValue: _gender,
                    validator: (v) => v == null ? 'Requis' : null,
                    items: AppConstants.genderLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'État civil'),
                    key: ValueKey('marital-$_maritalStatus'),
                    initialValue: _maritalStatus,
                    items: AppConstants.maritalLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _maritalStatus = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Dates
            const _SectionTitle('Dates'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Date de naissance',
                    value: _birthday,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Date de salut',
                    value: _salvationDate,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Organization
            const _SectionTitle('Organisation'),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Quartier/District', prefixIcon: Icon(Icons.location_on_outlined)),
              key: ValueKey('district-${_validDropdownValue(_districtId, org.activeDistricts)}'),
              initialValue: _validDropdownValue(_districtId, org.activeDistricts),
              items: org.activeDistricts.where((d) => d['id'] is int).map((d) => DropdownMenuItem(value: d['id'] as int, child: Text(AppConstants.safeStr(d['name'], '—')))).toList(),
              onChanged: (v) => setState(() => _districtId = v),
            ),
            const SizedBox(height: 12),
            if (isManager) ...[
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Cellule de prière', prefixIcon: Icon(Icons.groups_outlined)),
                key: ValueKey('cell-${_validDropdownValue(_cellId, org.activeCells)}'),
                initialValue: _validDropdownValue(_cellId, org.activeCells),
                items: org.activeCells.where((c) => c['id'] is int).map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(AppConstants.safeStr(c['name'], '—')))).toList(),
                onChanged: (v) => setState(() => _cellId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Groupe d\'âge', prefixIcon: Icon(Icons.diversity_3_outlined)),
                key: ValueKey('group-${_validDropdownValue(_ageGroupId, org.activeAgeGroups)}'),
                initialValue: _validDropdownValue(_ageGroupId, org.activeAgeGroups),
                items: org.activeAgeGroups.where((g) => g['id'] is int).map((g) => DropdownMenuItem(value: g['id'] as int, child: Text(AppConstants.safeStr(g['name'], '—')))).toList(),
                onChanged: (v) => setState(() => _ageGroupId = v),
              ),
            ],
            const SizedBox(height: 20),

            // Inviter & Mentor
            const _SectionTitle('Parrainage'),
            const SizedBox(height: 8),
            Consumer<MemberProvider>(
              builder: (_, memberProv, __) {
                final memberItems = memberProv.allMembers
                    .where((m) => m['id'] is int && m['id'] != widget.memberId)
                    .map((m) => <String, dynamic>{'id': m['id'] as int, 'name': '${m['name'] ?? ''} ${m['first_name'] ?? ''}'.trim()})
                    .toList();
                return Column(
                  children: [
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Invité(e) par', prefixIcon: Icon(Icons.person_add_outlined)),
                      key: ValueKey('invited-${memberItems.any((m) => m['id'] == _invitedById) ? _invitedById : null}'),
                      initialValue: memberItems.any((m) => m['id'] == _invitedById) ? _invitedById : null,
                      items: memberItems.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text((m['name'] as String?) ?? '—'))).toList(),
                      onChanged: (v) => setState(() => _invitedById = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Mentor', prefixIcon: Icon(Icons.supervisor_account_outlined)),
                      key: ValueKey('mentor-${memberItems.any((m) => m['id'] == _mentorId) ? _mentorId : null}'),
                      initialValue: memberItems.any((m) => m['id'] == _mentorId) ? _mentorId : null,
                      items: memberItems.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text((m['name'] as String?) ?? '—'))).toList(),
                      onChanged: (v) => setState(() => _mentorId = v),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Additional
            const _SectionTitle('Informations supplémentaires'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.home_outlined)),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _professionCtrl,
              decoration: const InputDecoration(labelText: 'Profession', prefixIcon: Icon(Icons.work_outlined)),
              textCapitalization: TextCapitalization.sentences,
            ),
            if (_isEdit && context.watch<MemberProvider>().currentDetail != null) ...[
              const SizedBox(height: 24),
              _JourneySection(detail: context.watch<MemberProvider>().currentDetail!),
            ],
            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isSaving || !_canEdit ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(_isEdit ? 'Mettre à jour' : 'Créer le membre', style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({required this.label, this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today, size: 20),
        ),
        child: Text(
          value != null ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}' : '—',
          style: TextStyle(color: value != null ? null : Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Le parcours de la personne : chaque suivi (motif d'interruption, reprise),
/// puis l'affermissement après l'intégration.
class _JourneySection extends StatelessWidget {
  final Map<String, dynamic> detail;
  const _JourneySection({required this.detail});

  static const _milestones = {'3m': 'à 3 mois', '6m': 'à 6 mois'};
  static const _results = {'favorable': 'favorable', 'unfavorable': 'défavorable'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journey = (detail['journey'] as List? ?? []).whereType<Map>().toList();
    final checkpoints = (detail['checkpoints'] as List? ?? []).whereType<Map>().toList();
    final dates = <String, String>{
      'Intégré(e) le': AppConstants.frDate(detail['integration_date']),
      'Baptisé(e) le': AppConstants.frDate(detail['baptism_date']),
      'Affermi(e) le': AppConstants.frDate(detail['established_date']),
    }..removeWhere((_, v) => v.isEmpty);
    if (journey.isEmpty && checkpoints.isEmpty && dates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parcours', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (detail['reopen_suggested'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Deux contrôles défavorables de suite : rouvrir un suivi est proposé.',
                style: TextStyle(color: AppColors.abandoned)),
          ),
        const SizedBox(height: 8),
        ...journey.map((j) {
          final state = AppConstants.safeStr(j['state']);
          final reason = [AppConstants.safeStr(j['abandon_reason_label']), AppConstants.safeStr(j['abandon_note'])]
              .where((t) => t.isNotEmpty)
              .join(' — ');
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.assignment_outlined, color: AppColors.stateColor(state)),
              title: Text('${AppConstants.frDate(j['start_date'])} · ${j['duration_weeks'] ?? 0} sem. · '
                  '${AppConstants.safeStr(j['evangelist_name'])}'),
              subtitle: Text([
                AppConstants.safeStr(j['state_label']),
                if (reason.isNotEmpty) reason,
                if (j['resumes_followup_id'] is int) 'reprise d\'un suivi interrompu',
              ].join(' · ')),
            ),
          );
        }),
        if (dates.isNotEmpty || checkpoints.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...dates.entries.map((e) => Chip(label: Text('${e.key} ${e.value}'))),
              ...checkpoints.map((c) {
                final done = c['state'] == 'done';
                final favorable = c['result'] == 'favorable';
                return Chip(
                  avatar: Icon(
                    done ? (favorable ? Icons.check_circle : Icons.cancel) : Icons.schedule,
                    size: 16,
                    color: done ? (favorable ? AppColors.integrated : AppColors.abandoned) : Colors.grey,
                  ),
                  label: Text('Contrôle ${_milestones[c['milestone']] ?? ''}'
                      '${done ? ' ${_results[c['result']] ?? ''}' : ' le ${AppConstants.frDate(c['due_date'])}'}'),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}
