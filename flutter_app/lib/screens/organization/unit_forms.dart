import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

String _text(dynamic v) => v is String ? v : '';

/// Le bouton d'enregistrement commun : grisé pendant l'envoi.
class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onPressed;
  const _SaveButton({required this.saving, required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: saving ? null : onPressed,
        icon: saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check),
        label: const Text('Enregistrer'),
      );
}

/// Archiver / rouvrir une unité : jamais supprimer (l'historique y tient).
class _ArchiveTile extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  final String what;
  final bool feminine;
  const _ArchiveTile({required this.active, required this.onChanged, required this.what, this.feminine = false});

  String _e(String word) => feminine ? '${word}e' : word;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(active ? '$what ${_e('actif')}' : '$what ${_e('archivé')}'),
        subtitle: Text(active
            ? 'Archiver retire des listes ; l\'historique est gardé.'
            : 'N\'apparaît plus dans les listes. Réactivez pour rouvrir.'),
        value: active,
        onChanged: onChanged,
      );
}

// ─── Cellule ─────────────────────────────────────────────────────────

/// Créer ou modifier une cellule. Son responsable n'en change que le jour,
/// l'heure, le lieu et les notes ; le reste est la décision du responsable
/// de l'église.
class CellFormScreen extends StatefulWidget {
  final Map<String, dynamic>? cell;
  const CellFormScreen({super.key, this.cell});

  @override
  State<CellFormScreen> createState() => _CellFormScreenState();
}

class _CellFormScreenState extends State<CellFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _location, _notes, _leaderName, _leaderPhone;
  String? _day;
  String _time = '';
  late Set<int> _districtIds;
  bool _active = true;
  bool _saving = false;

  bool get _isEdit => widget.cell != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cell ?? const {};
    _name = TextEditingController(text: _text(c['name']));
    _location = TextEditingController(text: _text(c['meeting_location']));
    _notes = TextEditingController(text: _text(c['notes']));
    _leaderName = TextEditingController(text: _text(c['leader_name']));
    _leaderPhone = TextEditingController(text: _text(c['leader_phone']));
    _day = AppConstants.dayLabels.containsKey(c['meeting_day']) ? c['meeting_day'] : (_isEdit ? null : 'friday');
    _time = _text(c['meeting_time']).isEmpty && !_isEdit ? '19:00' : _text(c['meeting_time']);
    _districtIds = {for (final id in (c['district_ids'] is List ? c['district_ids'] as List : const [])) if (id is int) id};
    _active = c['active'] != false;
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<OrganizationProvider>().loadDistricts());
  }

  @override
  void dispose() {
    for (final c in [_name, _location, _notes, _leaderName, _leaderPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 19,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked != null) {
      setState(() => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _addDistrict() async {
    final created = await showDistrictForm(context);
    if (created != null && created['id'] is int) setState(() => _districtIds.add(created['id'] as int));
  }

  Future<void> _save(bool manager) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      if (_isEdit) 'cell_id': widget.cell!['id'],
      'meeting_day': _day ?? '',
      'meeting_time': _time,
      'meeting_location': _location.text.trim(),
      'notes': _notes.text.trim(),
      if (manager) ...{
        'name': _name.text.trim(),
        'district_ids': _districtIds.toList(),
        'leader_name': _leaderName.text.trim(),
        'leader_phone': _leaderPhone.text.trim(),
        if (_isEdit) 'active': _active,
      },
    };
    final result = await context.read<OrganizationProvider>().saveCell(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      showSuccessSnackbar(context, result['message']);
      Navigator.pop(context, true);
    } else {
      showErrorSnackbar(context, result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<AuthProvider>().isManager;
    final districts = context.watch<OrganizationProvider>().activeDistricts;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier la cellule' : 'Nouvelle cellule')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              enabled: manager,
              decoration: const InputDecoration(labelText: 'Nom de la cellule *', prefixIcon: Icon(Icons.groups_outlined)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Le nom est requis' : null,
            ),
            if (manager) ...[
              const SizedBox(height: 16),
              SectionHeader(
                title: 'Quartiers couverts',
                trailing: TextButton.icon(
                    onPressed: _addDistrict, icon: const Icon(Icons.add, size: 18), label: const Text('Quartier')),
              ),
              if (districts.isEmpty)
                const Text('Aucun quartier : ajoutez-en un.', style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final d in districts.where((d) => d['id'] is int))
                      FilterChip(
                        label: Text(_text(d['name'])),
                        selected: _districtIds.contains(d['id']),
                        onSelected: (on) => setState(() => on ? _districtIds.add(d['id']) : _districtIds.remove(d['id'])),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _day,
                    decoration: const InputDecoration(labelText: 'Jour'),
                    items: AppConstants.dayLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _day = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Heure', prefixIcon: Icon(Icons.schedule)),
                      child: Text(_time.isEmpty ? '—' : _time),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Lieu de réunion', prefixIcon: Icon(Icons.place_outlined)),
            ),
            if (manager) ...[
              const SizedBox(height: 16),
              const SectionHeader(title: 'Responsable'),
              TextFormField(
                controller: _leaderName,
                decoration: const InputDecoration(labelText: 'Nom et prénoms', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _leaderPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  helperText: 'Son compte est ouvert : il se connecte avec ce numéro.',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.notes)),
            ),
            if (manager && _isEdit) ...[
              const SizedBox(height: 8),
              _ArchiveTile(active: _active, what: 'Cellule', feminine: true, onChanged: (v) => setState(() => _active = v)),
            ],
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, onPressed: () => _save(manager)),
          ],
        ),
      ),
    );
  }
}

// ─── Groupe d'âge ────────────────────────────────────────────────────

class AgeGroupFormScreen extends StatefulWidget {
  final Map<String, dynamic>? group;
  const AgeGroupFormScreen({super.key, this.group});

  @override
  State<AgeGroupFormScreen> createState() => _AgeGroupFormScreenState();
}

class _AgeGroupFormScreenState extends State<AgeGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _notes, _leaderName, _leaderPhone;
  String? _type;
  String? _gender;
  int? _rangeId;
  bool _active = true;
  bool _saving = false;

  bool get _isEdit => widget.group != null;

  @override
  void initState() {
    super.initState();
    final g = widget.group ?? const {};
    _name = TextEditingController(text: _text(g['name']));
    _notes = TextEditingController(text: _text(g['notes']));
    _leaderName = TextEditingController(text: _text(g['leader_name']));
    _leaderPhone = TextEditingController(text: _text(g['leader_phone']));
    _type = AppConstants.groupTypeLabels.containsKey(g['group_type']) ? g['group_type'] : null;
    _gender = AppConstants.groupGenderLabels.containsKey(g['gender']) ? g['gender'] : (_isEdit ? null : 'mixed');
    _rangeId = AppConstants.safeId(g['age_range_id']);
    _active = g['active'] != false;
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<OrganizationProvider>().loadAgeRanges());
  }

  @override
  void dispose() {
    for (final c in [_name, _notes, _leaderName, _leaderPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await context.read<OrganizationProvider>().saveAgeGroup({
      if (_isEdit) 'age_group_id': widget.group!['id'],
      'name': _name.text.trim(),
      'group_type': _type,
      'gender': _gender,
      'age_range_id': _rangeId ?? 0,
      'notes': _notes.text.trim(),
      'leader_name': _leaderName.text.trim(),
      'leader_phone': _leaderPhone.text.trim(),
      if (_isEdit) 'active': _active,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      showSuccessSnackbar(context, result['message']);
      Navigator.pop(context, true);
    } else {
      showErrorSnackbar(context, result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranges = context.watch<OrganizationProvider>().ageRanges.where((r) => r['id'] is int).toList();
    final rangeValue = ranges.any((r) => r['id'] == _rangeId) ? _rangeId : null;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier le groupe' : 'Nouveau groupe d\'âge')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom du groupe *', prefixIcon: Icon(Icons.diversity_3_outlined)),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Le nom est requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type *'),
              items: AppConstants.groupTypeLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v),
              validator: (v) => v == null ? 'Le type est requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Sexe *'),
              items: AppConstants.groupGenderLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _gender = v),
              validator: (v) => v == null ? 'Le sexe est requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('range-$rangeValue-${ranges.length}'),
              initialValue: rangeValue,
              decoration: const InputDecoration(labelText: 'Tranche d\'âge', helperText: 'Surtout pour les mariés.'),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('—')),
                ...ranges.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(_text(r['name'])))),
              ],
              onChanged: (v) => setState(() => _rangeId = v),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Responsable'),
            TextFormField(
              controller: _leaderName,
              decoration: const InputDecoration(labelText: 'Nom et prénoms', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _leaderPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined),
                helperText: 'Son compte est ouvert : il se connecte avec ce numéro.',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes', prefixIcon: Icon(Icons.notes)),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              _ArchiveTile(active: _active, what: 'Groupe', onChanged: (v) => setState(() => _active = v)),
            ],
            const SizedBox(height: 20),
            _SaveButton(saving: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

// ─── Quartier ────────────────────────────────────────────────────────

/// Créer ou modifier un quartier dans une feuille ; rend le quartier enregistré.
Future<Map<String, dynamic>?> showDistrictForm(BuildContext context, {Map<String, dynamic>? district}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _DistrictForm(district: district),
    ),
  );
}

class _DistrictForm extends StatefulWidget {
  final Map<String, dynamic>? district;
  const _DistrictForm({this.district});

  @override
  State<_DistrictForm> createState() => _DistrictFormState();
}

class _DistrictFormState extends State<_DistrictForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _city, _description;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.district ?? const {};
    _name = TextEditingController(text: _text(d['name']));
    _city = TextEditingController(text: _text(d['city']));
    _description = TextEditingController(text: _text(d['description']));
    _active = d['active'] != false;
  }

  @override
  void dispose() {
    for (final c in [_name, _city, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await context.read<OrganizationProvider>().saveDistrict({
      if (widget.district != null) 'district_id': widget.district!['id'],
      'name': _name.text.trim(),
      'city': _city.text.trim(),
      'description': _description.text.trim(),
      if (widget.district != null) 'active': _active,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      showSuccessSnackbar(context, result['message']);
      Navigator.pop(context, Map<String, dynamic>.from(result['record'] as Map));
    } else {
      showErrorSnackbar(context, result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.district == null ? 'Nouveau quartier' : 'Modifier le quartier',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            autofocus: widget.district == null,
            decoration: const InputDecoration(labelText: 'Nom du quartier *', prefixIcon: Icon(Icons.location_on_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Le nom est requis' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'Ville')),
          const SizedBox(height: 12),
          TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
          if (widget.district != null)
            _ArchiveTile(active: _active, what: 'Quartier', onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: 16),
          _SaveButton(saving: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
