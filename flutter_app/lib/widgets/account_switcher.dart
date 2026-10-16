import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/organization_provider.dart';
import 'common.dart';

/// Choisir l'église à gérer — réservé à l'administrateur.
///
/// Les autres comptes entrent dans leur église à la connexion et y restent :
/// cette feuille ne leur est jamais proposée, et le serveur la refuserait.
Future<void> showChurchPicker(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  if (!auth.canChangeChurch) return;
  final org = context.read<OrganizationProvider>();
  final chosen = await showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _ChurchPickerSheet(org: org, currentChurchId: auth.churchId),
  );
  if (chosen == null || chosen == auth.churchId || !context.mounted) return;
  final result = await auth.changeChurch(chosen);
  if (!context.mounted) return;
  if (result['success'] == true) {
    showSuccessSnackbar(context, result['message'] ?? 'Église changée');
  } else {
    showErrorSnackbar(context, result['message'] ?? 'Changement impossible');
  }
}

class _ChurchPickerSheet extends StatefulWidget {
  final OrganizationProvider org;
  final int currentChurchId;
  const _ChurchPickerSheet({required this.org, required this.currentChurchId});

  @override
  State<_ChurchPickerSheet> createState() => _ChurchPickerSheetState();
}

class _ChurchPickerSheetState extends State<_ChurchPickerSheet> {
  @override
  void initState() {
    super.initState();
    // Après la construction : le chargement prévient ses auditeurs.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.org.loadChurches());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.org,
      builder: (context, _) {
        final churches = widget.org.churches.where((c) => c['active'] != false).toList();
        Widget tile(int id, String name, String subtitle, IconData icon) => ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(name),
              subtitle: subtitle.isEmpty ? null : Text(subtitle),
              trailing: id == widget.currentChurchId
                  ? const Icon(Icons.check_circle, color: AppColors.integrated)
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, id),
            );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text('Changer d\'église', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    tile(0, 'Toutes les églises', 'Vue d\'ensemble du réseau', Icons.public),
                    const Divider(height: 1),
                    if (widget.org.isLoading && churches.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final c in churches)
                      tile(c['id'] as int, '${c['name'] ?? ''}', '${c['region'] ?? ''}', Icons.church_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
