@Tags(['formation'])
library;

import 'package:church_followup_mobile/screens/admin/mobile_users_screen.dart';
import 'package:church_followup_mobile/screens/attendance/attendance_sunday_screen.dart';
import 'package:church_followup_mobile/screens/auth/login_screen.dart';
import 'package:church_followup_mobile/screens/checkpoints/checkpoint_list_screen.dart';
import 'package:church_followup_mobile/screens/dashboard/dashboard_screen.dart';
import 'package:church_followup_mobile/screens/followups/followup_detail_screen.dart';
import 'package:church_followup_mobile/screens/followups/followup_form_screen.dart';
import 'package:church_followup_mobile/screens/followups/followup_list_screen.dart';
import 'package:church_followup_mobile/screens/followups/to_assign_screen.dart';
import 'package:church_followup_mobile/screens/home/home_screen.dart';
import 'package:church_followup_mobile/screens/members/member_form_screen.dart';
import 'package:church_followup_mobile/screens/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_server.dart';
import 'support/real_fonts.dart';
import 'support/shoot.dart';

/// Les captures du guide, du manuel de formation et des vidéos.
///
///     flutter test --tags formation --run-skipped --update-goldens
///
/// Elles atterrissent dans `test/formation/` ; `scripts/sync_training_shots.sh`
/// copie celles que citent les documents. Données de démonstration seulement
/// (support/demo_server.dart) : aucun vrai numéro.
void main() {
  setUpAll(loadRealFonts);

  Future<void> tapText(WidgetTester t, String text) async {
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Future<void> menuAction(WidgetTester t, String action) async {
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await tapText(t, action);
  }

  // ─── Tout le monde ────────────────────────────────────────────────
  testWidgets('connexion', (t) => shoot(t, name: 'connexion', screen: const LoginScreen(), role: ''));
  testWidgets('connexion_code', (t) => shoot(t, name: 'connexion_code', screen: const LoginScreen(), role: '',
      avantLaPhoto: (t) async {
        await t.enterText(find.byType(TextFormField).first, '07 00 01 01 01');
        await tapText(t, 'Recevoir un code');
      }));

  // ─── Évangéliste ──────────────────────────────────────────────────
  testWidgets('evangeliste_a_faire', (t) => shoot(t, name: 'evangeliste_a_faire', screen: const HomeScreen()));
  testWidgets('evangeliste_mes_suivis', (t) => shoot(t, name: 'evangeliste_mes_suivis',
      screen: const HomeScreen(), avantLaPhoto: (t) => tapText(t, 'Mes suivis')));
  testWidgets('suivi_detail', (t) => shoot(t, name: 'suivi_detail',
      screen: const FollowupDetailScreen(followupId: 102)));
  testWidgets('suivi_detail_rapports', (t) => shoot(t, name: 'suivi_detail_rapports',
      screen: const FollowupDetailScreen(followupId: 101), avantLaPhoto: (t) async {
        await t.drag(find.byType(ListView).first, const Offset(0, -500));
      }));
  testWidgets('rapport_semaine', (t) => shoot(t, name: 'rapport_semaine',
      screen: const FollowupDetailScreen(followupId: 102), avantLaPhoto: (t) => tapText(t, 'Ajouter')));
  testWidgets('prolonger', (t) => shoot(t, name: 'prolonger',
      screen: const FollowupDetailScreen(followupId: 102), avantLaPhoto: (t) => menuAction(t, 'Prolonger')));
  testWidgets('interrompre', (t) => shoot(t, name: 'interrompre',
      screen: const FollowupDetailScreen(followupId: 102), avantLaPhoto: (t) async {
        await menuAction(t, 'Interrompre');
        await tapText(t, 'A déménagé');
      }));
  testWidgets('integrer_sous_le_seuil', (t) => shoot(t, name: 'integrer_sous_le_seuil',
      screen: const FollowupDetailScreen(followupId: 101), avantLaPhoto: (t) => menuAction(t, 'Intégrer')));
  testWidgets('nouveau_suivi', (t) => shoot(t, name: 'nouveau_suivi',
      screen: FollowupFormScreen(initialMember: demoMembers.firstWhere((m) => m['id'] == 12))));
  testWidgets('presence_dimanche', (t) => shoot(t, name: 'presence_dimanche',
      screen: const AttendanceSundayScreen()));

  // ─── Responsable ──────────────────────────────────────────────────
  testWidgets('responsable_a_faire', (t) => shoot(t, name: 'responsable_a_faire',
      screen: const HomeScreen(), role: 'manager'));
  testWidgets('responsable_tableau_de_bord', (t) => shoot(t, name: 'responsable_tableau_de_bord',
      screen: const DashboardScreen(), role: 'manager'));
  testWidgets('a_attribuer', (t) => shoot(t, name: 'a_attribuer', screen: const ToAssignScreen(), role: 'manager'));
  testWidgets('confier_un_suivi', (t) => shoot(t, name: 'confier_un_suivi', role: 'manager',
      screen: FollowupFormScreen(initialMember: demoMembers.firstWhere((m) => m['id'] == 12))));
  testWidgets('responsable_suivis', (t) => shoot(t, name: 'responsable_suivis',
      screen: const FollowupListScreen(), role: 'manager'));
  testWidgets('comptes', (t) => shoot(t, name: 'comptes', screen: const MobileUsersScreen(), role: 'manager'));
  testWidgets('invitation', (t) => shoot(t, name: 'invitation', screen: const MobileUsersScreen(), role: 'manager',
      avantLaPhoto: (t) async {
        await t.tap(find.byTooltip('Envoyer l\'invitation').last);
        await t.pumpAndSettle();
      }));
  testWidgets('changer_eglise', (t) => shoot(t, name: 'changer_eglise', screen: const SettingsScreen(), role: 'manager',
      avantLaPhoto: (t) => tapText(t, 'Changer d\'église')));
  testWidgets('fiche_parcours', (t) => shoot(t, name: 'fiche_parcours', role: 'manager',
      screen: const MemberFormScreen(memberId: 16), avantLaPhoto: (t) async {
        await t.scrollUntilVisible(find.text('Parcours'), 300, scrollable: find.byType(Scrollable).first);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -260));
      }));

  // ─── Responsable de cellule ───────────────────────────────────────
  testWidgets('cellule_a_faire', (t) => shoot(t, name: 'cellule_a_faire',
      screen: const HomeScreen(), role: 'cell_leader'));
  testWidgets('controles', (t) => shoot(t, name: 'controles', screen: const CheckpointListScreen(), role: 'cell_leader'));
  testWidgets('controle', (t) => shoot(t, name: 'controle', role: 'cell_leader',
      screen: CheckpointScreen(checkpoint: checkpointFanta), avantLaPhoto: (t) => tapText(t, 'Oui, elle tient')));
}
