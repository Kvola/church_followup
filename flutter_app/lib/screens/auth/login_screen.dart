import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: AppConstants.defaultUrl);
  final _dbCtrl = TextEditingController(text: AppConstants.defaultDatabase);

  bool _showAdvanced = false;
  bool _isLoading = false;
  bool _obscurePin = true;
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
    final phone = await auth.getLastPhone();
    if (phone.isNotEmpty) _phoneCtrl.text = phone;
    if (auth.serverUrl.isNotEmpty) _urlCtrl.text = auth.serverUrl;
    if (auth.database.isNotEmpty) _dbCtrl.text = auth.database;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _urlCtrl.dispose();
    _dbCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final auth = context.read<AuthProvider>();
    final result = await auth.login(
      url: _urlCtrl.text.trim(),
      db: _dbCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      pin: _pinCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Erreur de connexion'),
          backgroundColor: AppColors.abandoned,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Hero(
                        tag: 'app_logo',
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                          ),
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
                        'Connectez-vous pour continuer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: size.height * 0.05),

                      // Phone
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone',
                          prefixIcon: Icon(Icons.phone_outlined),
                          hintText: '+243 ...',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                      ),
                      const SizedBox(height: 16),

                      // PIN
                      TextFormField(
                        controller: _pinCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: _obscurePin,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Code PIN',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          hintText: '••••••',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscurePin = !_obscurePin),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                      ),
                      const SizedBox(height: 12),

                      // Advanced toggle
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                          icon: Icon(
                            _showAdvanced ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                          label: const Text('Paramètres serveur'),
                          style: TextButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),

                      // Server settings
                      AnimatedCrossFade(
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

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Se connecter', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      SizedBox(height: size.height * 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
