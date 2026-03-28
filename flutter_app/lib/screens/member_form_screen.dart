import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class MemberFormScreen extends StatefulWidget {
  final int? memberId;
  const MemberFormScreen({super.key, this.memberId});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();

  String _gender = 'male';
  String _memberType = 'new';
  String _maritalStatus = 'single';
  DateTime? _dob;

  List<dynamic> _districts = [];
  List<dynamic> _prayerCells = [];
  int? _districtId;
  int? _prayerCellId;

  bool get _isEdit => widget.memberId != null;

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    _districts = await service.getDistricts();
    _prayerCells = await service.getPrayerCells();

    if (_isEdit) {
      final member = await service.getMemberDetail(widget.memberId!);
      if (member != null && mounted) {
        _nameCtrl.text = member['name'] ?? '';
        _firstNameCtrl.text = member['first_name'] ?? '';
        _phoneCtrl.text = member['phone'] ?? '';
        _addressCtrl.text = member['address'] ?? '';
        _professionCtrl.text = member['profession'] ?? '';
        _gender = member['gender'] ?? 'male';
        _memberType = member['member_type'] ?? 'new';
        _maritalStatus = member['marital_status'] ?? 'single';
        _districtId = member['district_id'] is List ? member['district_id'][0] : member['district_id'];
        _prayerCellId = member['prayer_cell_id'] is List ? member['prayer_cell_id'][0] : member['prayer_cell_id'];
        if (member['date_of_birth'] != null) {
          _dob = DateTime.tryParse(member['date_of_birth']);
        }
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final vals = {
      'name': _nameCtrl.text.trim(),
      'first_name': _firstNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'gender': _gender,
      'member_type': _memberType,
      'marital_status': _maritalStatus,
      'address': _addressCtrl.text.trim(),
      'profession': _professionCtrl.text.trim(),
      'district_id': _districtId,
      'prayer_cell_id': _prayerCellId,
      if (_dob != null) 'date_of_birth': _dob!.toIso8601String().split('T')[0],
    };

    final service = context.read<ChurchService>();
    Map<String, dynamic> result;
    if (_isEdit) {
      result = await service.updateMember(widget.memberId!, vals);
    } else {
      result = await service.createMember(vals);
    }

    if (mounted) {
      if (result['success'] == true) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Erreur'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
    );
    if (date != null) setState(() => _dob = date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Modifier Membre' : 'Nouveau Membre')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nom *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                    validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _firstNameCtrl,
                    decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Téléphone *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: const InputDecoration(labelText: 'Genre', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Homme')),
                      DropdownMenuItem(value: 'female', child: Text('Femme')),
                    ],
                    onChanged: (v) => setState(() => _gender = v ?? 'male'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date de Naissance',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.cake),
                      ),
                      child: Text(_dob != null ? '${_dob!.day}/${_dob!.month}/${_dob!.year}' : 'Sélectionner'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _maritalStatus,
                    decoration: const InputDecoration(labelText: 'Situation matrimoniale', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'single', child: Text('Célibataire')),
                      DropdownMenuItem(value: 'married', child: Text('Marié(e)')),
                      DropdownMenuItem(value: 'divorced', child: Text('Divorcé(e)')),
                      DropdownMenuItem(value: 'widowed', child: Text('Veuf/Veuve')),
                    ],
                    onChanged: (v) => setState(() => _maritalStatus = v ?? 'single'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _memberType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'new', child: Text('Nouveau')),
                      DropdownMenuItem(value: 'in_followup', child: Text('En suivi')),
                      DropdownMenuItem(value: 'integrated', child: Text('Intégré')),
                      DropdownMenuItem(value: 'old_member', child: Text('Ancien membre')),
                    ],
                    onChanged: (v) => setState(() => _memberType = v ?? 'new'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _professionCtrl,
                    decoration: const InputDecoration(labelText: 'Profession', border: OutlineInputBorder(), prefixIcon: Icon(Icons.work)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(labelText: 'Adresse', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _districtId,
                    decoration: const InputDecoration(labelText: 'Quartier', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Aucun')),
                      ..._districts.map<DropdownMenuItem<int>>((d) => DropdownMenuItem(value: d['id'] as int, child: Text(d['name'] ?? ''))),
                    ],
                    onChanged: (v) => setState(() => _districtId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _prayerCellId,
                    decoration: const InputDecoration(labelText: 'Cellule de Prière', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('Aucune')),
                      ..._prayerCells.map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] ?? ''))),
                    ],
                    onChanged: (v) => setState(() => _prayerCellId = v),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_isEdit ? 'Mettre à jour' : 'Créer le Membre'),
                  ),
                ],
              ),
            ),
    );
  }
}
