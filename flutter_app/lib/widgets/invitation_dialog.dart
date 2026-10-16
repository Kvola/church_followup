import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'common.dart';

/// Ouvre WhatsApp sur ce numéro avec ce message.
Future<void> launchWhatsApp(BuildContext context, String phone, String message) async {
  final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '').replaceFirst('+', '');
  final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    showErrorSnackbar(context, 'Impossible d\'ouvrir WhatsApp');
  }
}

/// Ouvre l'application SMS sur ce numéro avec ce message.
Future<void> launchSms(BuildContext context, String phone, String message) async {
  final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': message});
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    showErrorSnackbar(context, 'Impossible d\'ouvrir les SMS');
  }
}

/// Montre l'invitation à installer l'application, prête à transmettre.
///
/// Elle ne contient aucun secret : le code de connexion arrive sur le numéro
/// du compte au moment de se connecter. On peut donc la renvoyer sans risque.
void showInvitationDialog(BuildContext context, String message, String userName, String phone) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Invitation à transmettre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Envoyez ce message à $userName :'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(message, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              MiniShareButton(
                icon: Icons.message,
                color: Colors.blue,
                label: 'WhatsApp',
                onTap: () {
                  Navigator.pop(ctx);
                  launchWhatsApp(context, phone, message);
                },
              ),
              MiniShareButton(
                icon: Icons.sms_outlined,
                color: Colors.orange,
                label: 'SMS',
                onTap: () {
                  Navigator.pop(ctx);
                  launchSms(context, phone, message);
                },
              ),
              MiniShareButton(
                icon: Icons.copy,
                color: Colors.teal,
                label: 'Copier',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message));
                  showSuccessSnackbar(ctx, 'Copié');
                },
              ),
              MiniShareButton(
                icon: Icons.share,
                color: AppColors.primary,
                label: 'Partager',
                onTap: () {
                  Navigator.pop(ctx);
                  Share.share(message, subject: AppConstants.appName);
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
      ],
    ),
  );
}

class MiniShareButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const MiniShareButton({super.key, required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
