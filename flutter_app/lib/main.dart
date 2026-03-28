import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/church_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ChurchFollowupApp());
}

class ChurchFollowupApp extends StatelessWidget {
  const ChurchFollowupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChurchService(),
      child: MaterialApp(
        title: 'Suivi Évangélisation',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF5B4FCF),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        home: Consumer<ChurchService>(
          builder: (context, service, _) {
            if (service.isAuthenticated) {
              return const HomeScreen();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}
