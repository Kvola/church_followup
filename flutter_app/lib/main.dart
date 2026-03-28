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

class ChurchFollowupApp extends StatelessWidget {
  const ChurchFollowupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'Suivi Évangélisation',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            home: auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),
          );
        },
      ),
    );
  }
}
