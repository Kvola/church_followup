import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Charge de vraies polices depuis le SDK Flutter.
///
/// Sans elles, `flutter test` peint chaque caractère comme un rectangle : une
/// capture devient un mur de boîtes noires. Nuisible dans l'aide en ligne,
/// inutilisable pour juger d'une typographie.
///
/// On échoue franchement si elles manquent — une capture de rectangles publiée
/// serait pire que pas d'image du tout.
///
/// Reprise telle quelle de `equipment_mobile/test/support/`.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT absent : impossible de charger les polices réelles.');
  }
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) {
    fail('Polices introuvables dans ${dir.path}.');
  }
  final loader = FontLoader('Roboto');
  for (final file in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final path = File('${dir.path}/$file');
    if (path.existsSync()) {
      loader.addFont(
        path.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
    }
  }
  await loader.load();

  // Les icônes aussi : sans elles, chaque icône serait un carré vide, et
  // c'est souvent l'icône qu'on demande à l'utilisateur de reconnaître.
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
            icons.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
          ))
        .load();
  }

  // ── Repli Unicode ────────────────────────────────────────────────────────
  // Le Roboto livré dans le cache Flutter est amputé : il n'a PAS la flèche
  // « → » (U+2192), pourtant utilisée pour dire « du … au … » dans les plages
  // de dates. Sur un vrai téléphone la police système prend le relais et
  // personne ne voit rien ; sous `flutter test` il n'existe aucun repli, et la
  // capture publierait un carré vide au milieu d'une date.
  //
  // La police de secours est enregistrée sous SA PROPRE famille, que le thème
  // des captures déclare en `fontFamilyFallback`. L'ajouter à la famille
  // « Roboto » ne suffit pas : le moteur y choisit UNE fonte selon la graisse
  // et le style, il ne parcourt pas la famille glyphe par glyphe.
  final fallback = File(unicodeFallbackPath);
  if (!fallback.existsSync()) {
    fail('Police de repli Unicode introuvable : ${fallback.path}. '
        'Sans elle, la flèche « → » des plages de dates sort en carré vide.');
  }
  await (FontLoader(unicodeFallbackFamily)
        ..addFont(fallback.readAsBytes().then((b) => ByteData.view(b.buffer))))
      .load();
}

/// Famille de repli pour les glyphes absents de Roboto — à passer en
/// `fontFamilyFallback` du thème utilisé pour les captures.
const unicodeFallbackFamily = 'CaptureUnicodeFallback';

/// Chemin de cette police. macOS ; à compléter si les captures doivent un jour
/// se prendre ailleurs — l'absence est signalée, jamais contournée.
const unicodeFallbackPath =
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
