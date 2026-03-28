import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/followup_provider.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';

class FollowupFormScreen extends StatefulWidget {
  const FollowupFormScreen({super.key});

  @override
  State<FollowupFormScreen> createState() => _FollowupFormScreenState();
}

class _FollowupFormScreenState extends State<FollowupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedMemberId;
  int? _selectedEvangelistId;
  int _durationWeeks = 8;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MemberProvider>().loadMembers(memberType: 'new');
      context.read<FollowupProvider>().loadEvangelists();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMemberId == null || _selectedEvangelistId == null) {
      showErrorSnackbar(context, 'Veuillez sélectionner un membre et un évangéliste');
      return;
    }

    setState(() => _isSaving = true);

    final result = await context.read<FollowupProvider>().createFollowup({
      'member_id': _selectedMemberId,
      'evangelist_id': _selectedEvangelistId,
      'duration_weeks': _durationWeeks,
    });

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['status'] == 'success') {
      showSuccessSnackbar(context, 'Suivi créé avec succès');
      Navigator.pop(context, true);
    } else {
      showErrorSnackbar(context, result['message'] ?? 'Erreur');
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberProvider = context.watch<MemberProvider>();
    final followupProvider = context.watch<FollowupProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau suivi')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Member selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Membre à suivre', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        hintText: 'Sélectionner un membre',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: memberProvider.allMembers
                          .where((m) => m['id'] is int)
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text('${m['name'] ?? ''} ${m['first_name'] ?? ''}'.trim()),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedMemberId = v),
                      value: _selectedMemberId,
                      validator: (_) => _selectedMemberId == null ? 'Requis' : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Evangelist selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Évangéliste', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        hintText: 'Sélectionner un évangéliste',
                        prefixIcon: Icon(Icons.person_pin_outlined),
                      ),
                      items: followupProvider.evangelists
                          .where((e) => e['id'] is int)
                          .map((e) => DropdownMenuItem(
                                value: e['id'] as int,
                                child: Text(e['name'] ?? ''),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedEvangelistId = v),
                      value: _selectedEvangelistId,
                      validator: (_) => _selectedEvangelistId == null ? 'Requis' : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Duration
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Durée du suivi', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _durationWeeks.toDouble(),
                            min: 4,
                            max: 24,
                            divisions: 20,
                            label: '$_durationWeeks semaines',
                            onChanged: (v) => setState(() => _durationWeeks = v.round()),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$_durationWeeks sem.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Créer le suivi', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
