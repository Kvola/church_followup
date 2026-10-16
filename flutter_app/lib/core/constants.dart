import 'package:flutter/foundation.dart' show kIsWeb;
class AppConstants {
  static const String appName = 'Suivi Évangélisation';
  // Compilés dans l'APK par le script de publication (--dart-define, défaut
  // https://iyf.ebng.world). Aucune valeur par défaut ici : une adresse écrite
  // en dur finirait dans le bundle web, que build_pwa.sh refuse alors.
  static const String defaultUrl = String.fromEnvironment('BASE_URL');

  /// L'adresse du serveur à appeler.
  ///
  /// Sur le web, VIDE : la version navigateur est servie par le serveur
  /// qu'elle appelle, les adresses restent relatives, et un même bundle sert
  /// le développement comme la production. Compiler une adresse dans le
  /// bundle a déjà coûté un incident (la PWA des membres appelait
  /// `localhost:8069` : chaque navigateur visait sa propre machine).
  static String get serverUrl => kIsWeb ? '' : defaultUrl;
  static const String defaultDatabase = String.fromEnvironment('DB');

  /// Version installée, donnée à la construction. Vide (build de développement) :
  /// l'app ne cherche pas de mise à jour, faute de pouvoir se comparer.
  static const String appVersion = String.fromEnvironment('APP_VERSION');

  /// Identifiant de l'application dans le catalogue /apps du serveur.
  static const String appSlug = 'suivi-evangelisation';
  static const String developerName = 'DIBI Bi Kavola Augustin';
  static const String developerPhone = '+225 07 49 94 33 27';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 2;
  static const int cacheDurationMinutes = 30;
  static const int maxScorePerWeek = 13;

  // Storage keys
  static const String keyServerUrl = 'server_url';
  static const String keyDatabase = 'database';
  static const String keyUserId = 'user_id';
  static const String keyUserData = 'user_data';
  static const String keyPhone = 'last_phone';

  // Labels
  static const Map<String, String> stateLabels = {
    'in_progress': 'En cours',
    'integrated': 'Intégré',
    'abandoned': 'Interrompu',
    'extended': 'Prolongé',
    'transferred': 'Transféré',
    'never_logged': 'Jamais connecté',
  };

  static const Map<String, String> spiritualLabels = {
    'excellent': 'Excellent',
    'good': 'Bon',
    'average': 'Moyen',
    'poor': 'Faible',
    'critical': 'Critique',
  };

  static const Map<String, String> roleLabels = {
    'super_admin': 'Super administrateur',
    'manager': 'Responsable',
    'evangelist': 'Évangéliste',
    'cell_leader': 'Responsable de cellule',
    'group_leader': 'Responsable de groupe d\'âge',
  };

  static const Map<String, String> memberTypeLabels = {
    'new': 'À attribuer',
    'in_followup': 'En suivi',
    'interrupted': 'Suivi interrompu',
    'integrated': 'Intégré',
    'established': 'Fidèle affermi',
    'old_member': 'Ancien membre',
  };

  /// Motifs d'interruption d'un suivi (le serveur en exige un).
  static const Map<String, String> abandonReasons = {
    'unreachable': 'Injoignable',
    'moved': 'A déménagé',
    'other_church': 'Fréquente une autre église',
    'not_interested': 'Ne souhaite pas poursuivre',
    'other': 'Autre raison',
  };

  /// D'où vient la durée d'un suivi.
  static const Map<String, String> durationOriginLabels = {
    'church': "Réglage de l'église",
    'event': "Événement d'origine",
    'manual': 'Choix',
  };

  static const int minFollowupWeeks = 1;
  static const int maxFollowupWeeks = 26;

  /// Qui est la personne, une fois pour toutes (le statut, lui, suit le parcours).
  static const Map<String, String> profileLabels = {
    'new': 'Nouvelle personne',
    'old_member': 'Ancien membre',
  };

  static const Map<String, String> genderLabels = {
    'male': 'Homme',
    'female': 'Femme',
  };

  /// Sexe d'un groupe d'âge (qui peut être mixte, contrairement à une personne).
  static const Map<String, String> groupGenderLabels = {
    'male': 'Hommes',
    'female': 'Femmes',
    'mixed': 'Mixte',
  };

  static const Map<String, String> maritalLabels = {
    'single': 'Célibataire',
    'married': 'Marié(e)',
    'divorced': 'Divorcé(e)',
    'widowed': 'Veuf/Veuve',
  };

  static const Map<String, String> dayLabels = {
    'monday': 'Lundi',
    'tuesday': 'Mardi',
    'wednesday': 'Mercredi',
    'thursday': 'Jeudi',
    'friday': 'Vendredi',
    'saturday': 'Samedi',
    'sunday': 'Dimanche',
  };

  static const Map<String, String> groupTypeLabels = {
    'married': 'Mariés',
    'youth': 'Jeunes',
    'college': 'Collégiens',
    'highschool': 'Lycéens',
    'children': 'Enfants',
  };

  static const Map<String, String> cookingStateLabels = {
    'planned': 'Planifié',
    'done': 'Terminé',
    'cancelled': 'Annulé',
  };

  /// Safely extract an int ID from Odoo data.
  /// Odoo many2one fields can be: int, [id, name], false, or null.
  static int? safeId(dynamic value) {
    if (value is int) return value;
    if (value is List && value.isNotEmpty && value[0] is int) return value[0];
    return null;
  }

  /// Safely get the first character for an avatar, never crashes on empty/null.
  static String initial(dynamic value) {
    if (value is String && value.isNotEmpty) return value[0].toUpperCase();
    return '?';
  }

  /// Safely extract a display string from Odoo data.
  /// Handles false, null, and non-string types.
  /// « 2026-03-15 » → « 15/03/2026 » ; une valeur illisible est rendue telle quelle.
  static String frDate(dynamic value) {
    final raw = safeStr(value);
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  static String safeStr(dynamic value, [String fallback = '']) {
    if (value == null || value == false) return fallback;
    final s = value.toString();
    return s.isNotEmpty ? s : fallback;
  }
}
