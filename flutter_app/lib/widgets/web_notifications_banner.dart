import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'common.dart';

/// Version navigateur : proposer de recevoir les relances ici.
///
/// Seulement quand c'est possible et pas encore décidé (permission
/// « default ») : un navigateur qui a refusé ne repose plus la question, et
/// l'iPhone n'en reçoit qu'une fois l'app ajoutée à l'écran d'accueil — le
/// navigateur répond alors « unsupported » et la banderole se tait.
class WebNotificationsBanner extends StatefulWidget {
  const WebNotificationsBanner({super.key});

  static const prefKey = 'web_notifications_banner_dismissed';

  @override
  State<WebNotificationsBanner> createState() => _WebNotificationsBannerState();
}

class _WebNotificationsBannerState extends State<WebNotificationsBanner> {
  bool _visible = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final push = context.read<AuthProvider>().push;
    if (!push.webPushConfigured || push.webPermission != 'default') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(WebNotificationsBanner.prefKey) == true) return;
    } catch (_) {}
    if (mounted) setState(() => _visible = true);
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    try {
      (await SharedPreferences.getInstance()).setBool(WebNotificationsBanner.prefKey, true);
    } catch (_) {}
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final ok = await context.read<AuthProvider>().enableWebNotifications();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _visible = false;
    });
    if (ok) {
      showSuccessSnackbar(context, 'Notifications activées sur ce navigateur');
    } else {
      showErrorSnackbar(context, 'Notifications refusées : vous pourrez les autoriser dans les réglages du navigateur.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: AppColors.extended.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notifications_active_outlined, color: AppColors.extended),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recevez les relances sur ce navigateur',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Une personne confiée, une décision à prendre, le récapitulatif du lundi.',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(onPressed: _busy ? null : _dismiss, child: const Text('Plus tard')),
                  FilledButton.tonal(onPressed: _busy ? null : _enable, child: const Text('Activer')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
