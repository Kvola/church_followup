import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/church_service.dart';

class AttendanceSundayScreen extends StatefulWidget {
  const AttendanceSundayScreen({super.key});

  @override
  State<AttendanceSundayScreen> createState() => _AttendanceSundayScreenState();
}

class _AttendanceSundayScreenState extends State<AttendanceSundayScreen> {
  List<dynamic> _members = [];
  final Set<int> _presentIds = {};
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<ChurchService>();
    final members = await service.getMembers();
    if (mounted) {
      setState(() {
        _members = members;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final service = context.read<ChurchService>();
    final result = await service.saveSundayAttendance(
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
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_today),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _pickDate,
                  child: Text(
                    '${_date.day}/${_date.month}/${_date.year}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text('${_presentIds.length}/${_members.length} présents', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: const Text('Enregistrer'),
      ),
    );
  }
}
