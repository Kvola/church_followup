import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

/// Connexion par code à usage unique, comme l'application de l'association :
/// on saisit son numéro (ou son adresse e-mail), un code arrive par WhatsApp,
/// SMS ou e-mail, on le recopie. Aucun mot de passe à retenir ni à transmettre.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  static const _resendDelay = 60;

  final _identifierKey = GlobalKey<FormState>();
  final _codeKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: AppConstants.serverUrl);
  final _dbCtrl = TextEditingController(text: AppConstants.defaultDatabase);

  // APK construit sans adresse (hors script de publication) : on montre
  // d'emblée où la saisir, plutôt qu'un échec réseau sans explication.
  bool _showAdvanced = !kIsWeb && AppConstants.serverUrl.isEmpty;
  bool _isLoading = false;
  bool _codeStep = false;
  String _masked = '';
  String? _debugOtp;
  int _resendIn = 0;
  Timer? _resendTimer;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadLastConnection();
  }

  Future<void> _loadLastConnection() async {
    final auth = context.read<AuthProvider>();
    final last = await auth.getLastPhone();
    if (last.isNotEmpty) _identifierCtrl.text = last;
    if (auth.serverUrl.isNotEmpty) _urlCtrl.text = auth.serverUrl;
    if (auth.database.isNotEmpty) _dbCtrl.text = auth.database;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _animCtrl.dispose();
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    _urlCtrl.dispose();
    _dbCtrl.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^\+?[0-9 ().-]{8,20}$');

  String? _validateIdentifier(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Saisissez votre numéro ou votre adresse e-mail';
    if (v.contains('@') ? !_emailPattern.hasMatch(v) : !_phonePattern.hasMatch(v)) {
      return 'Numéro ou adresse e-mail invalide';
    }
    return null;
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendDelay);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = _resendIn > 0 ? _resendIn - 1 : 0);
      if (_resendIn == 0) t.cancel();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.abandoned),
    );
  }

  Future<void> _requestCode() async {
    if (!_identifierKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final result = await context.read<AuthProvider>().requestOtp(
          url: _urlCtrl.text.trim(),
          db: _dbCtrl.text.trim(),
          identifier: _identifierCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] != true) {
      _showError(result['message'] ?? 'Envoi du code impossible');
      return;
    }
    setState(() {
      _codeStep = true;
      _masked = (result['masked'] ?? '').toString();
      _debugOtp = result['debugOtp']?.toString();
      _codeCtrl.clear();
    });
    _startResendCountdown();
  }

  Future<void> _verifyCode() async {
    if (!_codeKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final result = await context.read<AuthProvider>().verifyOtp(_codeCtrl.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] != true) {
      _showError(result['message'] ?? 'Code incorrect');
    }
    // En cas de succès, l'application passe d'elle-même à l'accueil.
  }

  void _changeIdentifier() {
    _resendTimer?.cancel();
    setState(() {
      _codeStep = false;
      _resendIn = 0;
      _debugOtp = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final sessionMessage = context.watch<AuthProvider>().sessionMessage;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Hero(
                      tag: 'app_logo',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset('assets/logo.png', width: 100, height: 100, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _codeStep ? 'Saisissez le code reçu' : 'Connectez-vous avec votre numéro',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: size.height * 0.05),

                    // Session expirée : dire pourquoi on revient ici.
                    if (sessionMessage != null && !_codeStep) ...[
                      _Notice(icon: Icons.lock_clock, color: AppColors.extended, text: sessionMessage),
                      const SizedBox(height: 16),
                    ],

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _codeStep ? _buildCodeStep(theme) : _buildIdentifierStep(theme),
                    ),
                    SizedBox(height: size.height * 0.05),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentifierStep(ThemeData theme) {
    return Form(
      key: _identifierKey,
      child: Column(
        key: const ValueKey('identifier'),
        children: [
          TextFormField(
            controller: _identifierCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onFieldSubmitted: (_) => _requestCode(),
            decoration: const InputDecoration(
              labelText: 'Téléphone ou e-mail',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '07 00 00 00 00',
              helperText: 'Le numéro ou l\'e-mail enregistré pour votre compte',
            ),
            validator: _validateIdentifier,
          ),
          const SizedBox(height: 12),
          // Sur le web, pas de serveur à choisir : c'est celui qui sert la page.
          if (!kIsWeb) Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 18),
              label: const Text('Paramètres serveur'),
              // Hérite du thème (police comprise) au lieu de le remplacer.
              style: TextButton.styleFrom(textStyle: theme.textTheme.labelMedium),
            ),
          ),
          // Sur le web, ni bouton ni champs : un champ masqué mais présent
          // resterait dans le formulaire, et sa validation (« Requis », l'adresse
          // étant volontairement vide) bloquerait l'envoi SANS RIEN AFFICHER.
          if (!kIsWeb) AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL du serveur',
                    prefixIcon: Icon(Icons.dns_outlined),
                    hintText: 'https://...',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requis';
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme) return 'URL invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dbCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Base de données',
                    prefixIcon: Icon(Icons.storage_outlined),
                    hintText: 'nom_base',
                  ),
                ),
              ],
            ),
            crossFadeState: _showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
          const SizedBox(height: 28),
          _PrimaryButton(label: 'Recevoir un code', loading: _isLoading, onPressed: _requestCode),
        ],
      ),
    );
  }

  Widget _buildCodeStep(ThemeData theme) {
    return Form(
      key: _codeKey,
      child: Column(
        key: const ValueKey('code'),
        children: [
          _Notice(
            icon: Icons.mark_chat_read_outlined,
            color: AppColors.primary,
            text: 'Si ce compte existe, un code de 6 chiffres vient d\'être envoyé à $_masked '
                '(WhatsApp, SMS ou e-mail). Il est valable 10 minutes.',
          ),
          if (_debugOtp != null) ...[
            const SizedBox(height: 8),
            Text('Code de test : $_debugOtp', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          TextFormField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofocus: true,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 10, fontWeight: FontWeight.bold),
            onChanged: (v) {
              if (v.length == 6 && !_isLoading) _verifyCode();
            },
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            validator: (v) => (v ?? '').length == 6 ? null : 'Le code a 6 chiffres',
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Se connecter', loading: _isLoading, onPressed: _verifyCode),
          const SizedBox(height: 12),
          // Wrap, pas Row : sur un écran étroit ou en grands caractères, le
          // second bouton passe à la ligne au lieu de déborder.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(onPressed: _isLoading ? null : _changeIdentifier, child: const Text('Changer de numéro')),
              TextButton(
                onPressed: _resendIn > 0 || _isLoading ? null : _requestCode,
                child: Text(_resendIn > 0 ? 'Renvoyer (${_resendIn}s)' : 'Renvoyer le code'),
              ),
            ],
          ),
          // Le serveur répond pareil qu'un compte existe ou non : sans cette
          // aide, celui dont le numéro n'est pas enregistré attend en vain.
          if (_resendIn == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Pas de code ? Vérifiez que c\'est bien le numéro (ou l\'adresse e-mail) '
              'enregistré pour votre compte. Sinon, demandez à votre responsable : '
              'il peut vous envoyer un code depuis Odoo, ou vous le dicter.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
