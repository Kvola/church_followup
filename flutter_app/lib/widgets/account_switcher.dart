import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'common.dart';

/// Propose les autres églises où la personne a un compte (même numéro).
///
/// Le code reçu à la connexion a prouvé qu'elle tient ce numéro : passer d'une
/// église à l'autre ne redemande rien.
Future<void> showAccountSwitcher(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final chosen = await showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text('Changer d\'église', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        for (final account in auth.accounts)
          ListTile(
            leading: const Icon(Icons.church_outlined, color: AppColors.primary),
            title: Text(account['church_name']?.toString() ?? ''),
            subtitle: Text(account['role_label']?.toString() ?? ''),
            trailing: account['id'] == auth.userId
                ? const Icon(Icons.check_circle, color: AppColors.integrated)
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(ctx, account['id'] as int?),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
  if (chosen == null || chosen == auth.userId || !context.mounted) return;
  final result = await auth.switchAccount(chosen);
  if (!context.mounted) return;
  if (result['success'] == true) {
    showSuccessSnackbar(context, result['message'] ?? 'Église changée');
  } else {
    showErrorSnackbar(context, result['message'] ?? 'Changement impossible');
  }
}
