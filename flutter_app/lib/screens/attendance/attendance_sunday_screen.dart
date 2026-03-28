import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/member_provider.dart';
import '../../providers/organization_provider.dart';
import '../../widgets/common.dart';

class AttendanceSundayScreen extends StatefulWidget {
  const AttendanceSundayScreen({super.key});

  @override
  State<AttendanceSundayScreen> createState() => _AttendanceSundayScreenState();
}

class _AttendanceSundayScreenState extends State<AttendanceSundayScreen> {
  DateTime _selectedDate = DateTime.now();
  final Set<int> _presentIds = {};
  bool _isSaving = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MemberProvider>().loadMembers();
    });
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final all = context.read<MemberProvider>().allMembers;
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all.where((m) {
      final name = '${m['name'] ?? ''} ${m['first_name'] ?? ''}'.toLowerCase();
      return name.contains(q);
    }).toList();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final result = await context.read<OrganizationProvider>().saveSundayAttendance(
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
    final memberProvider = context.watch<MemberProvider>();
    final members = _filteredMembers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Présence dimanche'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => memberProvider.loadMembers()),
        ],
      ),
      body: Column(
        children: [
          // Date picker & summary
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_presentIds.length}/${memberProvider.allMembers.length}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher...',
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),

          // Select all/none
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _presentIds.addAll(memberProvider.allMembers.map((m) => m['id']).whereType<int>());
                  }),
                  child: const Text('Tout sélectionner'),
                ),
                TextButton(
                  onPressed: () => setState(() => _presentIds.clear()),
                  child: const Text('Tout désélectionner'),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: memberProvider.isLoading
                ? const ShimmerList()
                : members.isEmpty
                    ? const EmptyState(icon: Icons.people_outlined, title: 'Aucun membre')
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: members.length,
                        itemBuilder: (_, index) {
                          final m = members[index];
                          final id = m['id'];
                          if (id is! int) return const SizedBox.shrink();
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
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isSaving || _presentIds.isEmpty ? null : _save,
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text('Enregistrer (${_presentIds.length} présents)', style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }
}
