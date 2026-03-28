import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class AttendanceCellScreen extends StatefulWidget {
  const AttendanceCellScreen({super.key});

  @override
  State<AttendanceCellScreen> createState() => _AttendanceCellScreenState();
}

class _AttendanceCellScreenState extends State<AttendanceCellScreen> {
  List<dynamic> _cells = [];
  int? _selectedCellId;
  List<dynamic> _members = [];
  final Set<int> _presentIds = {};
  DateTime _date = DateTime.now();
  bool _loadingCells = true;
  bool _loadingMembers = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCells();
  }

  Future<void> _loadCells() async {
    final service = context.read<ChurchService>();
    final cells = await service.getPrayerCells();
    if (mounted) {
      setState(() {
        _cells = cells;
        _loadingCells = false;
      });
    }
  }

  Future<void> _loadMembers() async {
    if (_selectedCellId == null) return;
    setState(() => _loadingMembers = true);
    final cell = _cells.firstWhere((c) => c['id'] == _selectedCellId, orElse: () => null);
    if (cell != null && mounted) {
      setState(() {
        _members = cell['members'] as List? ?? [];
        _presentIds.clear();
        _loadingMembers = false;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedCellId == null) return;
    setState(() => _saving = true);
    final service = context.read<ChurchService>();
    final result = await service.saveCellAttendance(
      _selectedCellId!,
      _date.toIso8601String().split('T')[0],
      _presentIds.toList(),
    );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success'] == true ? 'Présences enregistrées' : (result['message'] ?? 'Erreur')),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      locale: const Locale('fr'),
    );
    if (date != null) setState(() => _date = date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loadingCells
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        value: _selectedCellId,
                        decoration: const InputDecoration(
                          labelText: 'Cellule de prière',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.home_work),
                        ),
                        items: _cells
                            .map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] ?? '')))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedCellId = v);
                          _loadMembers();
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _pickDate,
                            child: Text('${_date.day}/${_date.month}/${_date.year}'),
                          ),
                          const Spacer(),
                          if (_members.isNotEmpty)
                            Text('${_presentIds.length}/${_members.length}', style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _selectedCellId == null
                      ? const Center(child: Text('Sélectionnez une cellule'))
                      : _loadingMembers
                          ? const Center(child: CircularProgressIndicator())
                          : _members.isEmpty
                              ? const Center(child: Text('Aucun membre dans cette cellule'))
                              : ListView.builder(
                                  itemCount: _members.length,
                                  itemBuilder: (_, i) {
                                    final m = _members[i];
                                    final id = m['id'] as int;
                                    return CheckboxListTile(
                                      value: _presentIds.contains(id),
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _presentIds.add(id);
                                          } else {
                                            _presentIds.remove(id);
                                          }
                                        });
                                      },
                                      title: Text(m['name'] ?? ''),
                                      subtitle: Text(m['phone'] ?? ''),
                                      secondary: CircleAvatar(child: Text((m['name'] ?? '?')[0])),
                                    );
                                  },
                                ),
                ),
              ],
            ),
      floatingActionButton: _selectedCellId != null && _members.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Enregistrer'),
            )
          : null,
    );
  }
}
