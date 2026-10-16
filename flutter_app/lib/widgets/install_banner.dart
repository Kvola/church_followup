import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/install/install_prompt.dart' as install;

/// La banderole qui invite à installer l'application — dans la version
/// navigateur seulement.
///
/// Le bon geste dépend de l'appareil :
/// * **Android** : l'application Android (APK), la plus complète ;
/// * **iPhone** : il n'y a pas d'APK — « Partager › Sur l'écran d'accueil »,
///   qui est aussi la condition pour qu'iOS délivre les notifications ;
/// * **ordinateur** (Chrome, Edge) : la fenêtre d'installation du navigateur,
///   si le navigateur la propose ; sinon rien, plutôt qu'un conseil vague.
///
/// Elle se tait si l'app est déjà installée, et ne revient plus sur ce
/// navigateur une fois fermée.
class InstallBanner extends StatefulWidget {
  const InstallBanner({
    super.key,
    this.isWeb = kIsWeb,
    this.platform,
    this.isStandalone = install.isStandalone,
    this.canPrompt = install.canPromptInstall,
    this.prompt = install.promptInstall,
    this.openUrl,
  });

  /// Paramètres injectables : les tests jouent chaque appareil.
  final bool isWeb;
  final TargetPlatform? platform;
  final bool Function() isStandalone;
  final bool Function() canPrompt;
  final Future<bool> Function() prompt;
  final Future<void> Function(Uri)? openUrl;

  static const prefKey = 'install_banner_dismissed';

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

enum _Kind { android, iphone, desktop }

class _InstallBannerState extends State<InstallBanner> {
  _Kind? _kind;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    if (!widget.isWeb || widget.isStandalone()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(InstallBanner.prefKey) == true) return;
    } catch (_) {
      // Stockage indisponible (navigation privée) : on propose quand même.
    }
    final platform = widget.platform ?? defaultTargetPlatform;
    final kind = switch (platform) {
      TargetPlatform.android => _Kind.android,
      TargetPlatform.iOS => _Kind.iphone,
      _ => widget.canPrompt() ? _Kind.desktop : null,
    };
    if (mounted && kind != null) setState(() => _kind = kind);
  }

  Future<void> _dismiss() async {
    setState(() => _kind = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(InstallBanner.prefKey, true);
    } catch (_) {}
  }

  Future<void> _downloadApk() async {
    // Relative : la page est servie par le serveur qui publie l'APK.
    final url = Uri.base.resolve('/apps/${AppConstants.appSlug}/download');
    final open = widget.openUrl ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await open(url);
  }

  Future<void> _installHere() async {
    final accepted = await widget.prompt();
    if (accepted) await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    if (kind == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (IconData icon, String title, String text) = switch (kind) {
      _Kind.android => (
          Icons.android,
          'Installez l\'application Android',
          'Plus rapide, et les relances arrivent en notification.',
        ),
      _Kind.iphone => (
          Icons.ios_share,
          'Installez l\'application sur l\'iPhone',
          'Touchez Partager, puis « Sur l\'écran d\'accueil ». C\'est aussi ce qui permet de recevoir les notifications.',
        ),
      _Kind.desktop => (
          Icons.install_desktop,
          'Installez l\'application sur cet ordinateur',
          'Elle s\'ouvre dans sa propre fenêtre, sans chercher l\'onglet.',
        ),
    };
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(text, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              // Wrap : en grands caractères, les boutons passent à la ligne.
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: _dismiss,
                      child: Text(kind == _Kind.iphone ? 'Compris' : 'Plus tard'),
                    ),
                    if (kind == _Kind.android)
                      FilledButton.tonal(onPressed: _downloadApk, child: const Text('Télécharger')),
                    if (kind == _Kind.desktop)
                      FilledButton.tonal(onPressed: _installHere, child: const Text('Installer')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
