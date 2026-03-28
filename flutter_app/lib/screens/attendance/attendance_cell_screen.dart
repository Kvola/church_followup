import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class AttendanceCellScreen extends StatefulWidget {
  const AttendanceCellScreen({super.key});

  @override
  State<AttendanceCellScreen> createState() => _AttendanceCellScreenState();
}

class _AttendanceCellScreenState extends State<AttendanceCellScreen> {
  DateTime _selectedDate = DateTime.now();
  int? _selectedCellId;
  final Set<int> _presentIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrganizationProvider>().loadCells();
    });
  }

  List<Map<String, dynamic>> get _cellMembers {
    if (_selectedCellId == null) return [];
    final provider = context.read<OrganizationProvider>();
    final cell = provider.cells.firstWhere(
      (c) => c['id'] == _selectedCellId,
      orElse: () => {},
    );
    final members = cell['members'];
    if (members is! List) return [];
    return members
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _save() async {
    if (_selectedCellId == null) return;

    setState(() => _isSaving = true);

    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final result = await context.read<OrganizationProvider>().saveCellAttendance(
      _selectedCellId!,
      dateStr,
      _presentIds.toList(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['status'] == 'success') {
      showSuccessSnackbar(context, 'Présence enregistrée (${_presentIds.length} présents)');
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProvider>();
    final members = _cellMembers;

    return Scaffold(
      appBar: AppBar(title: const Text('Présence cellule')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Cell picker
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Cellule de prière',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  value: _selectedCellId,
                  items: provider.cells
                      .where((c) => c['id'] is int)
                      .map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] ?? '')))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedCellId = v;
                    _presentIds.clear();
                  }),
                ),
                const SizedBox(height: 12),

                // Date picker
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_selectedCellId != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_presentIds.length}/${members.length} présents',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _presentIds.addAll(members.map((m) => m['id']).whereType<int>());
                    }),
                    child: const Text('Tous'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _presentIds.clear()),
                    child: const Text('Aucun'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: members.isEmpty
                  ? const EmptyState(icon: Icons.groups_outlined, title: 'Aucun membre dans cette cellule')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: members.length,
                      itemBuilder: (_, index) {
                        final m = members[index];
                        final id = m['id'] as int;
                        final name = '${m['name'] ?? ''} ${m['first_name'] ?? ''}'.trim();
                        final isPresent = _presentIds.contains(id);

                        return CheckboxListTile(
                          value: isPresent,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _presentIds.add(id);
                              } else {
                                _presentIds.remove(id);
                              }
                            });
                          },
                          title: Text(name),
                          secondary: CircleAvatar(
                            radius: 18,
                            backgroundColor: isPresent
                                ? AppColors.integrated.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.1),
                            child: Icon(
                              isPresent ? Icons.check : Icons.person_outline,
                              size: 18,
                              color: isPresent ? AppColors.integrated : Colors.grey,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          dense: true,
                        );
                      },
                    ),
            ),
          ] else
            const Expanded(
              child: EmptyState(
                icon: Icons.groups_outlined,
                title: 'Sélectionnez une cellule',
                subtitle: 'Choisissez une cellule de prière pour enregistrer la présence',
              ),
            ),
        ],
      ),
      bottomNavigationBar: _selectedCellId != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isSaving || _presentIds.isEmpty ? null : _save,
                    child: _isSaving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text('Enregistrer (${_presentIds.length})', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
