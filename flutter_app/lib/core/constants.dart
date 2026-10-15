class AppConstants {
  static const String appName = 'Suivi Évangélisation';
  static const String defaultUrl = 'https://iyf.kavola.site';
  static const String defaultDatabase = 'iyf.kavola.site';
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
  };

  static const Map<String, String> spiritualLabels = {
    'excellent': 'Excellent',
    'good': 'Bon',
    'average': 'Moyen',
    'poor': 'Faible',
    'critical': 'Critique',
  };

  static const Map<String, String> roleLabels = {
    'super_admin': 'Super Admin',
    'manager': 'Gestionnaire',
    'evangelist': 'Évangéliste',
    'cell_leader': 'Chef de cellule',
    'group_leader': 'Chef de groupe',
  };

  static const Map<String, String> memberTypeLabels = {
    'new': 'Nouveau',
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
    'college': 'Universitaires',
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
  static String safeStr(dynamic value, [String fallback = '']) {
    if (value == null || value == false) return fallback;
    final s = value.toString();
    return s.isNotEmpty ? s : fallback;
  }
}
