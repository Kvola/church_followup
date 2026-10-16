import 'package:flutter/material.dart';

import 'real_fonts.dart';

/// Le thème de production, rendu photographiable.
///
/// PROBLÈME. Un thème écrit à la main contient des `TextStyle(fontSize: 15)`
/// sans famille de police — pour les libellés de boutons, les titres de barre,
/// les onglets. À l'écran c'est sans conséquence : le moteur retombe sur la
/// police système, et personne ne voit rien. Sous `flutter test`, ce repli est
/// une police de test qui peint des **rectangles pleins**. La capture publie
/// alors un écran dont les titres et tous les boutons sont des pavés noirs,
/// tandis que le corps de texte, lui, s'affiche normalement — parce que
/// `Typography` nomme explicitement « Roboto » dans le `textTheme`.
///
/// Enregistrer Roboto sous le nom de la police de test ne suffit pas : le
/// moteur ne choisit pas son repli par ce nom-là.
///
/// SOLUTION. On nomme la police partout où le thème l'a laissée vide, et on
/// accroche au passage le repli Unicode (voir [unicodeFallbackFamily]) qui
/// fournit les glyphes absents du Roboto livré avec le SDK.
///
/// Ce n'est PAS un maquillage : la police posée est celle que l'appareil
/// choisirait de lui-même. On rend explicite, pour la photo, ce que le
/// système fait implicitement.
ThemeData captureTheme(ThemeData theme) {
  const family = 'Roboto';
  const fallback = <String>[unicodeFallbackFamily];

  // On ne renomme QUE ce qui existe. Fabriquer un `TextStyle` là où le thème
  // n'en posait aucun remplace un défaut calculé par le widget — le `ListTile`
  // y perd sa couleur de texte et la capture sort délavée, titres presque
  // blancs sur fond clair. Un `null` doit rester un `null`.
  TextStyle? named(TextStyle? style) => style?.copyWith(
        fontFamily: style.fontFamily ?? family,
        fontFamilyFallback: fallback,
      );

  ButtonStyle? button(ButtonStyle? style) {
    final textStyle = style?.textStyle;
    if (style == null || textStyle == null) return style;
    return style.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => named(textStyle.resolve(states)),
      ),
    );
  }

  return theme.copyWith(
    textTheme: theme.textTheme
        .apply(fontFamily: family, fontFamilyFallback: fallback),
    primaryTextTheme: theme.primaryTextTheme
        .apply(fontFamily: family, fontFamilyFallback: fallback),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: named(theme.appBarTheme.titleTextStyle),
      toolbarTextStyle: named(theme.appBarTheme.toolbarTextStyle),
    ),
    filledButtonTheme:
        FilledButtonThemeData(style: button(theme.filledButtonTheme.style)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: button(theme.elevatedButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: button(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: button(theme.textButtonTheme.style)),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: named(theme.chipTheme.labelStyle),
      secondaryLabelStyle: named(theme.chipTheme.secondaryLabelStyle),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(
      labelStyle: named(theme.tabBarTheme.labelStyle),
      unselectedLabelStyle: named(theme.tabBarTheme.unselectedLabelStyle),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle: named(theme.inputDecorationTheme.labelStyle),
      hintStyle: named(theme.inputDecorationTheme.hintStyle),
      helperStyle: named(theme.inputDecorationTheme.helperStyle),
      errorStyle: named(theme.inputDecorationTheme.errorStyle),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: named(theme.snackBarTheme.contentTextStyle),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: named(theme.listTileTheme.titleTextStyle),
      subtitleTextStyle: named(theme.listTileTheme.subtitleTextStyle),
      leadingAndTrailingTextStyle:
          named(theme.listTileTheme.leadingAndTrailingTextStyle),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      labelTextStyle: theme.navigationBarTheme.labelTextStyle == null
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => named(
                  theme.navigationBarTheme.labelTextStyle!.resolve(states)),
            ),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: named(theme.dialogTheme.titleTextStyle),
      contentTextStyle: named(theme.dialogTheme.contentTextStyle),
    ),
  );
}
