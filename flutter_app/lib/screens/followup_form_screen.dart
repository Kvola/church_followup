import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class FollowupFormScreen extends StatefulWidget {
  const FollowupFormScreen({super.key});

  @override
  State<FollowupFormScreen> createState() => _FollowupFormScreenState();
}

class _FollowupFormScreenState extends State<FollowupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _members = [];
  List<dynamic> _evangelists = [];
  bool _loading = true;
  bool _saving = false;

  int? _memberId;
  int? _evangelistId;
  int _totalWeeks = 4;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = context.read<ChurchService>();
    final members = await service.getMembers();
    final evangelists = await service.getEvangelists();
    if (mounted) {
      setState(() {
        _members = members;
        _evangelists = evangelists;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final service = context.read<ChurchService>();
    final result = await service.createFollowup({
      'member_id': _memberId,
      'evangelist_id': _evangelistId,
      'total_weeks': _totalWeeks,
    });

    if (mounted) {
      if (result['success'] == true || result['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Suivi créé avec succès'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Erreur'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau Suivi')),
      body: SafeArea(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  DropdownButtonFormField<int>(
                    value: _memberId,
                    decoration: const InputDecoration(
                      labelText: 'Personne à suivre',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    items: _members
                        .map<DropdownMenuItem<int>>((m) => DropdownMenuItem(
                              value: m['id'] as int,
                              child: Text(m['name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _memberId = v),
                    validator: (v) => v == null ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _evangelistId,
                    decoration: const InputDecoration(
                      labelText: 'Évangéliste',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_pin),
                    ),
                    items: _evangelists
                        .map<DropdownMenuItem<int>>((e) => DropdownMenuItem(
                              value: e['id'] as int,
                              child: Text(e['name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _evangelistId = v),
                    validator: (v) => v == null ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _totalWeeks,
                    decoration: const InputDecoration(
                      labelText: 'Durée (semaines)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.schedule),
                    ),
                    items: [2, 3, 4, 5, 6, 8]
                        .map((w) => DropdownMenuItem(value: w, child: Text('$w semaines')))
                        .toList(),
                    onChanged: (v) => setState(() => _totalWeeks = v ?? 4),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: const Text('Créer le Suivi'),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
