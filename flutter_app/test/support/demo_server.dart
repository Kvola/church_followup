/// Serveur factice des captures de formation : une église INVENTÉE, racontée
/// de bout en bout. Les réponses ont la forme exacte de celles de
/// `controllers/mobile_api.py` — un écran qui lit une clé absente ici la lirait
/// absente en production.
///
/// Personnes, numéros (+225 07 00 …) et lieux sont fictifs. Les mêmes noms
/// peuplent la base Odoo `suivi_demo` (tools/formation/seed_suivi_demo.py),
/// pour que le manuel, l'app et le back-office racontent la même histoire.
library;

const demoChurch = 'Église Bonne Nouvelle de la Grâce de Angré';
const demoInvitation = 'Bonjour Fatou Cissé,\n\n'
    'Vous avez un compte responsable de cellule dans l\'application Suivi Évangélisation '
    '($demoChurch).\n'
    '1. Installez l\'application : https://iyf.ebng.world/apps/suivi-evangelisation\n'
    '2. Saisissez votre numéro +225 07 00 05 05 05\n'
    '3. Recopiez le code reçu par WhatsApp ou SMS.';

Map<String, dynamic> _week(int n, {bool culte = false, bool pointe = false, bool appel = false,
        bool visite = false, String etat = 'good', int score = 0, String notes = ''}) =>
    {
      'id': n, 'week_number': n, 'date': '2026-09-${(n * 7 + 1).toString().padLeft(2, '0')}',
      'sunday_attendance': culte || pointe, 'roll_call_present': pointe, 'call_made': appel,
      'visit_made': visite, 'spiritual_state': etat, 'score': score, 'notes': notes,
    };

/// Konan Aya : suivi prolongé, arrivé à terme, présence sous le seuil.
final Map<String, dynamic> suiviAya = {
  'id': 101, 'name': 'SUV/2026/0101', 'reference': 'SUV/2026/0101',
  'evangelist_id': 1, 'evangelist_name': 'Awa Koné',
  'member_id': 10, 'member_name': 'Konan Aya', 'member_phone': '+225 07 00 10 10 10',
  'start_date': '2026-08-17', 'end_date': '2026-10-12', 'planned_end_date': '2026-10-12',
  'state': 'extended', 'duration_weeks': 8, 'total_weeks': 8, 'duration_origin': 'event',
  'current_week': 7, 'week_count': 7, 'progress': 87.5, 'average_score': 8.4,
  'elapsed_weeks': 8, 'attendance_weeks': 5, 'attendance_rate': 62, 'attendance_threshold': 75,
  'below_threshold': true, 'integration_justification': '',
  'weeks': [
    _week(1, pointe: true, appel: true, etat: 'average', score: 8),
    _week(2, appel: true, visite: true, etat: 'average', score: 8, notes: 'Visite à la maison, accueil chaleureux.'),
    _week(3, pointe: true, appel: true, etat: 'good', score: 9),
    _week(4, appel: true, etat: 'poor', score: 4, notes: 'Malade, absente au culte.'),
    _week(5, pointe: true, appel: true, visite: true, etat: 'good', score: 12),
    _week(6, culte: true, appel: true, etat: 'good', score: 9),
    _week(7, pointe: true, appel: true, etat: 'excellent', score: 10, notes: 'Demande à rejoindre une cellule.'),
  ],
};

/// Traoré Mariam : suivi en cours, semaine 3 à rédiger.
final Map<String, dynamic> suiviMariam = {
  'id': 102, 'name': 'SUV/2026/0102', 'reference': 'SUV/2026/0102',
  'evangelist_id': 1, 'evangelist_name': 'Awa Koné',
  'member_id': 11, 'member_name': 'Traoré Mariam', 'member_phone': '+225 07 00 11 11 11',
  'start_date': '2026-09-21', 'end_date': '2026-11-02', 'planned_end_date': '2026-11-02',
  'state': 'in_progress', 'duration_weeks': 6, 'total_weeks': 6, 'duration_origin': 'church',
  'current_week': 2, 'week_count': 2, 'progress': 33.3, 'average_score': 10.5,
  'elapsed_weeks': 4, 'attendance_weeks': 3, 'attendance_rate': 75, 'attendance_threshold': 75,
  'below_threshold': false, 'integration_justification': '',
  'weeks': [
    _week(1, pointe: true, appel: true, visite: true, etat: 'good', score: 12),
    _week(2, pointe: true, appel: true, etat: 'average', score: 8),
  ],
};

final Map<String, dynamic> suiviJean = {
  'id': 103, 'name': 'SUV/2026/0103', 'reference': 'SUV/2026/0103',
  'evangelist_id': 2, 'evangelist_name': 'Paul Yao',
  'member_id': 17, 'member_name': 'Koffi Jean', 'member_phone': '+225 07 00 17 17 17',
  'start_date': '2026-09-07', 'end_date': '2026-10-05', 'state': 'in_progress',
  'duration_weeks': 4, 'total_weeks': 4, 'duration_origin': 'church', 'current_week': 1,
  'week_count': 1, 'progress': 25.0, 'average_score': 6.0, 'attendance_rate': 25,
  'below_threshold': true, 'weeks': [_week(1, appel: true, etat: 'average', score: 5)],
};

Map<String, dynamic> _person(int id, String name, String first, String type,
        {String gender = 'female', String cell = '', String group = '', int age = 0,
        int weeks = 6, String origin = 'church', String label = '', bool toComplete = false,
        String profile = 'new'}) =>
    {
      'id': id, 'name': name, 'first_name': first, 'phone': '+225 07 00 ${id}0 ${id}0 $id',
      'gender': toComplete ? '' : gender, 'to_complete': toComplete, 'member_type': type,
      'person_profile': profile,
      'person_profile_label': profile == 'old_member' ? 'Ancien membre' : 'Nouvelle personne',
      'district_id': 1, 'district_name': 'Angré 8e tranche',
      'prayer_cell_id': cell.isEmpty ? false : 1, 'prayer_cell_name': cell,
      'age_group_id': group.isEmpty ? false : 1, 'age_group_name': group, 'age': age,
      'marital_status': 'single', 'invited_by_id': false, 'invited_by_name': '',
      'mentor_id': false, 'mentor_name': '', 'proposed_followup_weeks': weeks,
      'proposed_followup_origin': origin,
      'proposed_followup_label': label.isEmpty ? '$weeks semaines — Réglage de l\'église' : label,
    };

final List<Map<String, dynamic>> demoMembers = [
  _person(10, 'Konan', 'Aya', 'in_followup', age: 24),
  _person(11, 'Traoré', 'Mariam', 'in_followup', age: 31),
  _person(12, 'Bamba', 'Ibrahim', 'new', gender: 'male', age: 19, weeks: 8, origin: 'event',
      label: '8 semaines — Événement d\'origine (Camp de Toussaint 2026)'),
  // Ancienne membre qu'on reprend en suivi : elle attend son évangéliste.
  _person(13, 'Kouassi', 'Esther', 'new', age: 27, profile: 'old_member'),
  _person(14, 'Diallo', 'Moussa', 'interrupted', gender: 'male', age: 35),
  _person(15, 'Ouattara', 'Fanta', 'integrated', cell: 'Cellule Angré 8e tranche', group: 'Jeunes', age: 22),
  _person(16, 'Yapi', 'Serge', 'established', gender: 'male', cell: 'Cellule Angré 8e tranche', group: 'Mariés 25-35', age: 33),
  _person(17, 'Koffi', 'Jean', 'in_followup', gender: 'male', age: 28),
  _person(18, 'Aké', 'Nadège', 'new', toComplete: true),
];

final Map<String, dynamic> todoEvangelist = {
  'status': 'success', 'count': 2,
  'summary': '1\u00a0décision(s) à prendre, 1\u00a0rapport(s) en retard',
  'items': [
    {'kind': 'decision_due', 'followup_id': 101, 'member_id': 10, 'due_date': '2026-10-12',
     'title': 'Décision à prendre : Konan Aya',
     'detail': 'Suivi arrivé à terme le 12/10/2026. Intégrer, prolonger ou transférer ?'},
    {'kind': 'report_overdue', 'followup_id': 102, 'member_id': 11, 'week_number': 3,
     'title': 'Rapport en retard : Traoré Mariam, semaine 3', 'detail': 'À rédiger dans l\'application.'},
  ],
};

final Map<String, dynamic> todoManager = {
  'status': 'success', 'count': 7,
  'summary': '1\u00a0décision(s) à prendre, 3\u00a0personne(s) à attribuer, 1\u00a0évangéliste(s) en retard, 1\u00a0fiche(s) à compléter',
  'items': [
    {'kind': 'decision_due', 'followup_id': 101, 'member_id': 10,
     'title': 'Décision à prendre : Konan Aya',
     'detail': 'Suivi arrivé à terme le 12/10/2026. Intégrer, prolonger ou transférer ?'},
    {'kind': 'to_assign', 'member_id': 12, 'title': 'À attribuer : Bamba Ibrahim',
     'detail': '8 semaines — Événement d\'origine (Camp de Toussaint 2026)'},
    {'kind': 'to_assign', 'member_id': 13, 'title': 'À attribuer : Kouassi Esther',
     'detail': '6 semaines — Réglage de l\'église'},
    {'kind': 'to_assign', 'member_id': 18, 'title': 'À attribuer : Aké Nadège',
     'detail': '6 semaines — Réglage de l\'église'},
    {'kind': 'to_complete', 'count': 1, 'title': '1\u00a0fiche(s) à compléter',
     'detail': 'Le sexe manque : il oriente le choix du groupe d\'âge.'},
    {'kind': 'evangelist_late', 'evangelist_id': 2, 'title': 'Paul Yao : 2\u00a0rapport(s) en retard',
     'detail': 'À relancer.'},
  ],
};

final Map<String, dynamic> todoCellLeader = {
  'status': 'success', 'count': 1, 'summary': '1\u00a0contrôle(s) à faire',
  'items': [
    {'kind': 'checkpoint_due', 'checkpoint_id': 7, 'member_id': 15, 'due_date': '2026-10-15',
     'title': 'Contrôle à 3 mois : Ouattara Fanta', 'detail': 'La personne vient-elle toujours ?'},
  ],
};

final Map<String, dynamic> checkpointFanta = {
  'id': 7, 'member_id': 15, 'member_name': 'Ouattara Fanta', 'member_phone': '+225 07 00 15 15 15',
  'prayer_cell_name': 'Cellule Angré 8e tranche', 'milestone': '3m', 'is_catchup': false,
  'due_date': '2026-10-15', 'state': 'planned', 'result': '', 'done_date': '',
  'service_count': 11, 'cell_count': 9, 'notes': '', 'baptized': false, 'has_mentor': true,
};

final Map<String, dynamic> memberYapi = {
  ..._person(16, 'Yapi', 'Serge', 'established', gender: 'male', cell: 'Cellule Angré 8e tranche',
      group: 'Mariés 25-35', age: 33),
  'date_of_birth': '1993-04-12', 'address': 'Angré 8e tranche, près du marché', 'profession': 'Comptable',
  'salvation_date': '2026-01-18', 'can_edit': true, 'planned_followup_weeks': 0,
  'baptism_date': '2026-04-05', 'integration_date': '2026-03-15', 'established_date': '2026-09-16',
  'reopen_suggested': false,
  'journey': [
    {'followup_id': 90, 'reference': 'SUV/2026/0090', 'evangelist_name': 'Paul Yao',
     'start_date': '2025-11-03', 'end_date': '2025-12-01', 'duration_weeks': 4, 'state': 'abandoned',
     'state_label': 'Interrompu(e)', 'abandon_reason': 'unreachable', 'abandon_reason_label': 'Injoignable',
     'abandon_note': 'Téléphone éteint trois semaines', 'resumes_followup_id': false},
    {'followup_id': 95, 'reference': 'SUV/2026/0095', 'evangelist_name': 'Awa Koné',
     'start_date': '2026-01-19', 'end_date': '2026-03-16', 'duration_weeks': 8, 'state': 'integrated',
     'state_label': 'Intégré(e)', 'abandon_reason': '', 'abandon_reason_label': '', 'abandon_note': '',
     'resumes_followup_id': 90},
  ],
  'checkpoints': [
    {'id': 3, 'milestone': '3m', 'state': 'done', 'result': 'favorable', 'due_date': '2026-06-15',
     'is_catchup': false},
    {'id': 4, 'milestone': '6m', 'state': 'done', 'result': 'favorable', 'due_date': '2026-09-15',
     'is_catchup': false},
  ],
};

/// Réponse factice d'une route, selon le rôle connecté.
Map<String, dynamic> demoResponse(String path, Map<String, dynamic> params, String role) {
  bool ends(String suffix) => path.endsWith(suffix);
  if (ends('/todo')) {
    return switch (role) {
      'evangelist' => todoEvangelist,
      'cell_leader' => todoCellLeader,
      _ => todoManager,
    };
  }
  if (ends('/followup/detail')) {
    final id = params['followup_id'];
    return {'status': 'success', 'followup': id == 102 ? suiviMariam : suiviAya};
  }
  if (ends('/followups/to_assign')) {
    return {
      'status': 'success',
      // Comme le serveur : toute nouvelle personne, fiche complète ou non.
      'members': demoMembers.where((m) => m['member_type'] == 'new').toList(),
      'interrupted': [
        {...demoMembers.firstWhere((m) => m['id'] == 14), 'interrupted_on': '2026-09-28',
         'abandon_reason': 'moved', 'abandon_reason_label': 'A déménagé', 'abandon_note': 'Parti à Bouaké'},
      ],
    };
  }
  if (ends('/followups')) {
    final all = [suiviAya, suiviMariam, suiviJean];
    return {'status': 'success',
            'followups': role == 'evangelist' ? all.where((f) => f['evangelist_id'] == 1).toList() : all};
  }
  if (ends('/members')) {
    final type = params['member_type'];
    final list = type == null ? demoMembers : demoMembers.where((m) => m['member_type'] == type).toList();
    return {'status': 'success', 'members': list};
  }
  if (ends('/member/detail')) return {'status': 'success', 'member': memberYapi};
  if (ends('/checkpoints')) return {'status': 'success', 'checkpoints': [checkpointFanta]};
  if (ends('/evangelists')) {
    return {'status': 'success', 'evangelists': [
      {'id': 1, 'name': 'Awa Koné', 'phone': '+225 07 00 01 01 01', 'active_followup_count': 2,
       'integrated_count': 6, 'integration_rate': 75.0},
      {'id': 2, 'name': 'Paul Yao', 'phone': '+225 07 00 02 02 02', 'active_followup_count': 1,
       'integrated_count': 3, 'integration_rate': 60.0},
      {'id': 3, 'name': 'Grâce N\'Guessan', 'phone': '+225 07 00 03 03 03', 'active_followup_count': 0,
       'integrated_count': 4, 'integration_rate': 80.0},
    ]};
  }
  if (ends('/cells')) {
    return {'status': 'success', 'cells': [
      {'id': 1, 'name': 'Cellule Angré 8e tranche', 'leader_name': 'Fatou Cissé', 'leader_phone': '+225 07 00 05 05 05',
       'active': true, 'has_leader_account': true, 'district_ids': [1], 'district_names': ['Angré 8e tranche'],
       'notes': '', 'meeting_day_label': 'Vendredi',
       'meeting_day': 'friday', 'meeting_time': '19:00', 'meeting_location': 'Chez la famille Cissé',
       'member_count': 2, 'members': [
         {'id': 15, 'name': 'Ouattara Fanta', 'phone': '+225 07 00 15 15 15'},
         {'id': 16, 'name': 'Yapi Serge', 'phone': '+225 07 00 16 16 16'}]},
      {'id': 2, 'name': 'Cellule Angré Château', 'leader_name': 'Eric Gnamien', 'leader_phone': '',
       'active': true, 'has_leader_account': false, 'district_ids': [2], 'district_names': ['Angré Château'],
       'notes': '', 'meeting_day_label': 'Jeudi',
       'meeting_day': 'thursday', 'meeting_time': '18:30', 'meeting_location': '', 'member_count': 0,
       'members': []},
    ]};
  }
  if (ends('/age_groups')) {
    return {'status': 'success', 'age_groups': [
      {'id': 1, 'name': 'Jeunes', 'group_type': 'youth', 'gender': 'mixed', 'leader_name': 'Ruth Aka',
       'leader_phone': '', 'member_count': 1, 'members': []},
      {'id': 2, 'name': 'Mariés 25-35', 'group_type': 'married', 'gender': 'mixed', 'leader_name': '',
       'leader_phone': '', 'member_count': 1, 'members': []},
    ]};
  }
  if (ends('/districts')) {
    return {'status': 'success', 'districts': [
      {'id': 1, 'name': 'Angré 8e tranche', 'city': 'Cocody', 'active': true,
       'prayer_cell_name': 'Cellule Angré 8e tranche', 'member_count': 12},
      {'id': 2, 'name': 'Angré Château', 'city': 'Cocody', 'active': true,
       'prayer_cell_name': 'Cellule Angré Château', 'member_count': 5},
    ]};
  }
  if (ends('/age_ranges')) {
    return {'status': 'success', 'age_ranges': [
      {'id': 1, 'name': 'Mariés 25-35 ans', 'age_min': 25, 'age_max': 35},
      {'id': 2, 'name': 'Mariés 36-50 ans', 'age_min': 36, 'age_max': 50},
    ]};
  }
  if (ends('/churches')) {
    return {'status': 'success', 'churches': [
      {'id': 1, 'name': demoChurch, 'region': 'Abidjan Est', 'active': true},
      {'id': 2, 'name': 'Église Bonne Nouvelle de la Grâce de Yopougon', 'region': 'Abidjan Ouest', 'active': true},
    ]};
  }
  if (ends('/import/kinds')) return {'status': 'success', 'kinds': demoImportKinds};
  if (ends('/dashboard')) {
    return {'status': 'success', 'dashboard': {
      'church_name': demoChurch, 'total_members': 64, 'total_evangelists': 3, 'total_cells': 4,
      'total_groups': 4, 'active_followups': 3, 'total_integrated': 13, 'total_abandoned': 4,
      'integration_rate': 76.5,
      'evangelist_stats': [
        {'id': 1, 'name': 'Awa Koné', 'active_count': 2, 'integrated_count': 6, 'total_count': 9, 'integration_rate': 75.0},
        {'id': 2, 'name': 'Paul Yao', 'active_count': 1, 'integrated_count': 3, 'total_count': 5, 'integration_rate': 60.0},
        {'id': 3, 'name': 'Grâce N\'Guessan', 'active_count': 0, 'integrated_count': 4, 'total_count': 5, 'integration_rate': 80.0},
      ],
    }};
  }
  if (ends('/mobile_users')) {
    return {'status': 'success', 'users': [
      {'id': 1, 'name': 'Pasteur Marc Kouadio', 'phone': '+225 07 00 09 09 09', 'role': 'manager', 'active': true,
       'church_id': 1, 'church_name': demoChurch, 'email': '', 'last_login': '2026-10-15 08:12:00'},
      {'id': 2, 'name': 'Awa Koné', 'phone': '+225 07 00 01 01 01', 'role': 'evangelist', 'active': true,
       'church_id': 1, 'church_name': demoChurch, 'email': '', 'last_login': '2026-10-15 19:40:00'},
      {'id': 3, 'name': 'Paul Yao', 'phone': '+225 07 00 02 02 02', 'role': 'evangelist', 'active': true,
       'church_id': 1, 'church_name': demoChurch, 'email': '', 'last_login': ''},
      {'id': 4, 'name': 'Fatou Cissé', 'phone': '+225 07 00 05 05 05', 'role': 'cell_leader', 'active': true,
       'church_id': 1, 'church_name': demoChurch, 'email': '', 'last_login': ''},
    ]};
  }
  if (ends('/cooking_rotation')) return {'status': 'success', 'rotations': []};
  if (ends('/auth/request_otp')) {
    return {'status': 'success', 'identifier_masked': '+225 07 •• •• •• 01', 'channel': 'phone',
            'message': 'Si ce numéro ou cette adresse a un compte, un code vient d\'y être envoyé.'};
  }
  if (ends('/user/share_message')) {
    return {'status': 'success', 'message': demoInvitation, 'phone': '+225 07 00 05 05 05'};
  }
  return {'status': 'success'};
}

/// Les six imports, dans l'ordre où l'app les propose (comme le serveur).
const demoImportKinds = [
  {'kind': 'district', 'label': 'Quartiers',
   'description': "Les quartiers où vivent les membres. Les cellules de prière s'y rattachent."},
  {'kind': 'prayer_cell', 'label': 'Cellules de prière',
   'description': "Les cellules de prière de l'église. Un quartier inconnu est créé ; plusieurs quartiers se séparent par « ; »."},
  {'kind': 'age_group', 'label': "Groupes d'âge", 'description': "Les groupes d'âge de l'église (mariés, jeunes, lycéens…)."},
  {'kind': 'evangelist', 'label': 'Évangélistes',
   'description': "Les évangélistes de l'église. Leur compte de l'application est ouvert : ils se connectent avec leur numéro."},
  {'kind': 'member', 'label': 'Membres',
   'description': "Les membres de l'église (anciens membres), avec leur cellule et leur groupe."},
  {'kind': 'to_follow', 'label': 'Personnes à suivre',
   'description': "Nouvelles personnes ou anciens membres repris en suivi. Avec un évangéliste, le suivi démarre ; sans, « À attribuer »."},
];

/// Un import refusé, tel que le serveur le rend.
const demoImportRefused = {
  'status': 'error', 'code': 'import_refused', 'ok': false, 'error_count': 3,
  'message': "Rien n'a été importé : 3 erreur(s) à corriger dans le fichier.",
  'errors': [
    'Ligne 4 — Téléphone : « 07 12 » n\'est pas un numéro complet.',
    'Ligne 7 — Évangéliste : « Awa K. » n\'est pas une valeur permise (Awa Koné, Paul Yao, Grâce N\'Guessan).',
    'Ligne 9 : même fiche que la ligne 3 (« Bamba »).',
  ],
  'warnings': [],
};

/// Le compte connecté pour chaque rôle de démonstration.
Map<String, dynamic> demoUser(String role) => {
      'id': 1, 'role': role, 'church_id': 1, 'church_name': demoChurch,
      'is_multi_church': false, 'default_followup_weeks': 6,
      'can_change_church': role == 'super_admin',
      // Le pasteur Kouadio est dans l'annuaire : il entre en responsable, et se lit « Pasteur ».
      if (role == 'manager') ...{'is_pastor': true, 'role_label': 'Pasteur'},
      'name': switch (role) {
        'evangelist' => 'Awa Koné',
        'cell_leader' => 'Fatou Cissé',
        'super_admin' => 'Formateur IYF',
        _ => 'Pasteur Marc Kouadio',
      },
      if (role == 'evangelist') 'evangelist_id': 1,
      if (role == 'cell_leader') ...{'prayer_cell_id': 1, 'prayer_cell_name': 'Cellule Angré 8e tranche'},
    };

/// Un numéro n'ouvre qu'une église : chacun n'a que son compte.
List<Map<String, dynamic>> demoAccounts(String role) => [];
