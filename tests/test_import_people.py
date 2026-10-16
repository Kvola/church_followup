import datetime
import json

from odoo.tests import tagged

from .test_import import ImportCase


@tagged('post_install', '-at_install')
class TestImportPeople(ImportCase):
    """Phase 2 : le profil, les doublons de personnes, et les imports de personnes."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Member = cls.env['church.member']
        cls.ev = cls.env['church.evangelist'].create({
            'name': 'Awa Koné', 'phone': '+225 07 00 01 01 01', 'church_id': cls.church.id})
        cls.cell = cls.env['church.prayer.cell'].create({'name': 'Cellule Riviera', 'church_id': cls.church.id})

    def _member(self, name, first_name, **vals):
        return self.Member.create(dict({'name': name, 'first_name': first_name, 'church_id': self.church.id}, **vals))

    # ─── Profil ───────────────────────────────────────────────────────

    def test_profile_is_kept_whatever_the_journey(self):
        old = self._member('YAO', 'Marc', member_type='old_member')
        self.assertEqual(old.person_profile, 'old_member')
        followup = self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id, 'member_id': old.id})
        self.assertEqual(old.member_type, 'in_followup', "Le statut suit le parcours…")
        self.assertEqual(old.person_profile, 'old_member', "… le profil, non")
        self.assertEqual(followup.person_profile, 'old_member')
        self.assertEqual(self._member('AKA', 'Jean').person_profile, 'new')

    # ─── Doublons ─────────────────────────────────────────────────────

    def test_same_person_is_recognised_without_confusing_a_family(self):
        aya = self._member('KONAN', 'Aya Marie', phone='07 08 09 10 11')
        find = self.Member._find_same_person
        self.assertEqual(find(self.church, 'Konan', 'Aya', '+2250708091011')[0], aya, "Même numéro, même nom")
        self.assertEqual(find(self.church, 'Aya Marie', 'konan')[0], aya, "Nom et prénoms inversés")
        child = find(self.church, 'BAMBA', 'Ali', '0708091011')[0]
        self.assertFalse(child, "Un numéro partagé en famille ne confond pas deux personnes")
        self.assertFalse(find(self.church, 'Konan', 'Aya Marie', '0101010101')[0],
                         "Même nom mais autre numéro : un homonyme")
        self.assertFalse(find(self.other, 'Konan', 'Aya Marie', '0708091011')[0], "Autre église")
        self._member('KONAN', 'Aya Marie')
        _same, _why, ambiguous = find(self.church, 'Konan', 'Aya Marie')
        self.assertTrue(ambiguous, "Deux homonymes sans numéro : on ne choisit pas au hasard")

    def test_app_warns_before_creating_a_duplicate(self):
        self._member('KONAN', 'Aya', phone='07 08 09 10 11', prayer_cell_id=self.cell.id)
        params = {'name': 'Konan', 'first_name': 'Aya', 'gender': 'female', 'phone': '+225 0708091011'}
        res = self._rpc('/api/church/member/create', self.manager, **params)
        self.assertEqual(res['code'], 'duplicate_person', res)
        self.assertIn('Cellule Riviera', res['message'])
        self.assertEqual(res['duplicate']['person_profile'], 'new')
        res = self._rpc('/api/church/member/create', self.manager, confirm_new=True, **params)
        self.assertEqual(res['status'], 'success', "Confirmé : c'est une autre personne")

    # ─── Évangélistes ─────────────────────────────────────────────────

    def test_evangelists_import_opens_their_accounts_once(self):
        rows = [{'Nom et prénoms': 'Paul Yao', 'Téléphone': '07 00 02 02 02'},
                {'Nom et prénoms': 'Awa KONÉ', 'Téléphone': 700010101}]
        result = self._run('evangelist', rows)
        self.assertTrue(result['ok'], result)
        self.assertEqual((result['created'], result['unchanged']), (1, 1), "Awa est reconnue à son numéro")
        self.assertFalse(result['warnings'], "« 07 00 01 01 01 » et « +225… » sont le même numéro")
        paul = self.env['church.evangelist'].search([('name', '=', 'Paul Yao')])
        self.assertEqual(paul.mobile_user_id.role, 'evangelist')
        self.assertEqual(self._run('evangelist', rows)['created'], 0, "Réimporter ne crée rien")

    def test_evangelist_number_used_elsewhere_refuses_the_file(self):
        self.env['church.mobile.user'].create({
            'name': 'Ailleurs', 'phone': '+225 07 00 00 07 07', 'role': 'manager', 'church_id': self.other.id})
        result = self._run('evangelist', [{'Nom et prénoms': 'X', 'Téléphone': '0700000707'}])
        self.assertFalse(result['ok'])
        self.assertIn('Église B', result['errors'][0])
        self.assertFalse(self.env['church.evangelist'].search([('name', '=', 'X')]))

    # ─── Membres ──────────────────────────────────────────────────────

    def test_members_import_as_old_members_and_completes_existing(self):
        known = self._member('YAO', 'Marc', phone='07 11 11 11 11')
        result = self._run('member', [
            {'Nom': 'Yao', 'Prénoms': 'Marc', 'Téléphone': '+225 0711111111', 'Profession': 'Maçon'},
            {'Nom': 'TOURÉ', 'Prénoms': 'Fanta', 'Sexe': 'Femme', 'Cellule de prière': 'cellule riviera',
             'Quartier': 'Riviera', 'Date de naissance': datetime.datetime(1990, 3, 1),
             'Date de baptême': '04/08/2019'},
        ])
        self.assertTrue(result['ok'], result)
        self.assertEqual((result['created'], result['updated']), (1, 1))
        self.assertEqual(known.profession, 'Maçon', "La fiche connue est complétée")
        self.assertEqual(known.person_profile, 'new', "… sans changer son profil")
        fanta = self.Member.search([('name', '=', 'TOURÉ')])
        self.assertEqual((fanta.member_type, fanta.person_profile), ('old_member', 'old_member'))
        self.assertEqual(fanta.prayer_cell_id, self.cell)
        self.assertEqual(fanta.baptism_date, datetime.date(2019, 8, 4))

    def test_member_with_unknown_cell_is_refused(self):
        result = self._run('member', [{'Nom': 'A', 'Prénoms': 'B', 'Cellule de prière': 'Cellule Lune'}])
        self.assertFalse(result['ok'])
        self.assertIn('Cellule de prière', result['errors'][0])
        self.assertIn('Cellule Riviera', result['errors'][0], "Les valeurs permises sont rappelées")

    # ─── Personnes à suivre ───────────────────────────────────────────

    def test_to_follow_starts_followup_or_waits_for_an_evangelist(self):
        old = self._member('YAO', 'Marc', phone='07 11 11 11 11', member_type='integrated',
                           person_profile='old_member')
        result = self._run('to_follow', [
            {'Nom': 'KONAN', 'Prénoms': 'Aya', 'Évangéliste': 'Awa Koné', 'Durée du suivi (semaines)': 8},
            {'Nom': 'BAMBA', 'Prénoms': 'Ali'},
            {'Profil': 'Ancien membre', 'Nom': 'Yao', 'Prénoms': 'Marc', 'Téléphone': '0711111111'},
        ])
        self.assertTrue(result['ok'], result)
        aya = self.Member.search([('name', '=', 'KONAN')])
        self.assertEqual(aya.member_type, 'in_followup')
        self.assertEqual(aya.followup_ids.duration_weeks, 8)
        self.assertEqual(aya.followup_ids.evangelist_id, self.ev)
        ali = self.Member.search([('name', '=', 'BAMBA')])
        self.assertEqual((ali.member_type, ali.person_profile), ('new', 'new'), "Dans « À attribuer »")
        self.assertEqual(old.member_type, 'new', "L'ancien membre repris attend son évangéliste")
        self.assertEqual(old.person_profile, 'old_member', "… et reste un ancien membre")
        self.assertIn('1 suivi(s) démarré(s), 2 personne(s)', ' '.join(result['warnings']))
        to_assign = self._rpc('/api/church/followups/to_assign', self.manager)
        profiles = {m['name']: m['person_profile_label'] for m in to_assign['members']}
        self.assertEqual(profiles, {'BAMBA': 'Nouvelle personne', 'YAO': 'Ancien membre'})

    def test_to_follow_leaves_a_running_followup_alone(self):
        aya = self._member('KONAN', 'Aya', phone='0708091011')
        self.env['church.followup'].create({'church_id': self.church.id, 'evangelist_id': self.ev.id,
                                            'member_id': aya.id})
        result = self._run('to_follow', [{'Nom': 'Konan', 'Prénoms': 'Aya', 'Téléphone': '0708091011',
                                          'Évangéliste': 'Awa Koné'}])
        self.assertTrue(result['ok'], result)
        self.assertEqual(len(aya.followup_ids), 1, "Pas de second suivi")
        self.assertIn('Déjà en suivi', ' '.join(result['warnings']))

    def test_to_follow_refuses_duplicates_and_bad_durations(self):
        result = self._run('to_follow', [
            {'Nom': 'BAMBA', 'Prénoms': 'Ali', 'Téléphone': '0101010101'},
            {'Nom': 'Bamba', 'Prénoms': 'Ali', 'Téléphone': '+225 01 01 01 01 01'},
            {'Nom': 'TRA', 'Prénoms': 'Lou', 'Durée du suivi (semaines)': 40},
        ])
        self.assertFalse(result['ok'])
        text = '\n'.join(result['errors'])
        self.assertIn('Ligne 3 : même fiche que la ligne 2', text)
        self.assertIn('Ligne 4 — Durée du suivi', text)
        self.assertFalse(self.Member.search([('name', 'in', ('BAMBA', 'TRA'))]), "Rien n'est écrit")

    def test_to_follow_refuses_to_guess_between_homonyms(self):
        self._member('KONAN', 'Aya')
        self._member('Konan', 'Aya')
        result = self._run('to_follow', [{'Nom': 'TRA', 'Prénoms': 'Lou'}, {'Nom': 'KONAN', 'Prénoms': 'Aya'}])
        self.assertFalse(result['ok'])
        self.assertIn('Ligne 3 : plusieurs personnes', result['errors'][0])
        self.assertFalse(self.Member.search([('name', '=', 'TRA')]), "La ligne déjà écrite est défaite")

    def test_import_kinds_offered_to_the_app(self):
        kinds = [k['kind'] for k in self._rpc('/api/church/import/kinds', self.manager)['kinds']]
        self.assertEqual(kinds, ['district', 'prayer_cell', 'age_group', 'evangelist', 'member', 'to_follow'])
        json.dumps(kinds)
