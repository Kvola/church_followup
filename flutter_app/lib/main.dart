import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/followup_provider.dart';
import 'providers/member_provider.dart';
import 'providers/organization_provider.dart';
import 'providers/todo_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformError: $error\n$stack');
      return true;
    };

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    runApp(const ChurchFollowupApp());
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class ChurchFollowupApp extends StatefulWidget {
  const ChurchFollowupApp({super.key, this.auth});

  /// Fourni par les tests ; sinon créé ici.
  final AuthProvider? auth;

  @override
  State<ChurchFollowupApp> createState() => _ChurchFollowupAppState();
}

class _ChurchFollowupAppState extends State<ChurchFollowupApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _shownScope;

  /// Déconnexion, session expirée, autre église : `home` change, mais les
  /// écrans ouverts PAR-DESSUS (Paramètres, une fiche…) restaient affichés —
  /// on croyait la déconnexion sans effet. Ils appartiennent à l'ancien
  /// périmètre : on les referme.
  void _onScope(String scope) {
    if (_shownScope != null && _shownScope != scope) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _navigatorKey.currentState?.popUntil((route) => route.isFirst));
    }
    _shownScope = scope;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => widget.auth ?? AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, DashboardProvider>(
          create: (_) => DashboardProvider(),
          update: (_, auth, dash) => dash!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<AuthProvider, FollowupProvider>(
          create: (_) => FollowupProvider(),
          update: (_, auth, prov) => prov!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<AuthProvider, MemberProvider>(
          create: (_) => MemberProvider(),
          update: (_, auth, prov) => prov!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrganizationProvider>(
          create: (_) => OrganizationProvider(),
          update: (_, auth, prov) => prov!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<AuthProvider, TodoProvider>(
          create: (_) => TodoProvider(),
          update: (_, auth, prov) => prov!..updateAuth(auth),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final scope = auth.sessionScope;
          _onScope(scope);
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'Suivi Évangélisation',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            // Android 15+ dessine l'app SOUS la barre de navigation du
            // téléphone (bord à bord imposé). Une liste à marge explicite, un
            // bouton en bas de feuille ou de dialogue s'y cachaient. La marge
            // est posée ici, une fois, pour toutes les pages et feuilles.
            builder: (context, child) => ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(top: false, left: false, right: false, child: child!),
            ),
            // La clé reconstruit l'accueil (et recharge ses onglets) quand
            // l'administrateur passe sur une autre église.
            home: auth.isAuthenticated ? HomeScreen(key: ValueKey(scope)) : const LoginScreen(),
          );
        },
      ),
    );
  }
}
