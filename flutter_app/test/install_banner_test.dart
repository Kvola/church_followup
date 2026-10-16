import 'package:church_followup_mobile/widgets/install_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, InstallBanner banner) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [banner]))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Android : télécharger l\'APK, à une adresse relative', (t) async {
    Uri? opened;
    await _pump(t, InstallBanner(isWeb: true, platform: TargetPlatform.android,
        isStandalone: () => false, openUrl: (u) async => opened = u));
    expect(find.text('Installez l\'application Android'), findsOneWidget);
    await t.tap(find.text('Télécharger'));
    expect(opened!.path, '/apps/suivi-evangelisation/download');
  });

  testWidgets('iPhone : la marche à suivre, pas de bouton impossible', (t) async {
    await _pump(t, InstallBanner(isWeb: true, platform: TargetPlatform.iOS, isStandalone: () => false));
    expect(find.textContaining('Sur l\'écran d\'accueil'), findsOneWidget);
    expect(find.text('Télécharger'), findsNothing);
    expect(find.text('Compris'), findsOneWidget);
  });

  testWidgets('ordinateur : le bouton du navigateur, seulement s\'il le propose', (t) async {
    var prompted = false;
    await _pump(t, InstallBanner(isWeb: true, platform: TargetPlatform.windows, isStandalone: () => false,
        canPrompt: () => true, prompt: () async => prompted = true));
    await t.tap(find.text('Installer'));
    await t.pumpAndSettle();
    expect(prompted, isTrue);
    expect(find.byType(FilledButton), findsNothing, reason: 'Acceptée : la banderole se retire');

    await _pump(t, InstallBanner(key: UniqueKey(), isWeb: true, platform: TargetPlatform.macOS,
        isStandalone: () => false, canPrompt: () => false));
    expect(find.textContaining('Installez'), findsNothing, reason: 'Rien à proposer : rien à dire');
  });

  testWidgets('déjà installée, ou dans l\'APK : silence', (t) async {
    await _pump(t, InstallBanner(isWeb: true, platform: TargetPlatform.android, isStandalone: () => true));
    expect(find.textContaining('Installez'), findsNothing);
    await _pump(t, InstallBanner(key: UniqueKey(), isWeb: false, platform: TargetPlatform.android));
    expect(find.textContaining('Installez'), findsNothing);
  });

  testWidgets('fermée, elle ne revient plus sur ce navigateur', (t) async {
    await _pump(t, InstallBanner(isWeb: true, platform: TargetPlatform.android, isStandalone: () => false));
    await t.tap(find.text('Plus tard'));
    await t.pumpAndSettle();
    expect(find.textContaining('Installez'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(InstallBanner.prefKey), isTrue);
    await _pump(t, InstallBanner(key: UniqueKey(), isWeb: true, platform: TargetPlatform.android,
        isStandalone: () => false));
    expect(find.textContaining('Installez'), findsNothing);
  });
}
