from datetime import timedelta

from odoo import fields
from odoo.tests import tagged

from .test_import import ImportCase


@tagged('post_install', '-at_install')
class TestCellFollowupApi(ImportCase):
    """Phase 2 : le responsable de cellule suit les anciens membres que SA cellule porte."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Cell = cls.env['church.prayer.cell']
        cls.cell = Cell.create({'name': 'Cellule Riviera', 'church_id': cls.church.id,
                                'leader_name': 'Fatou', 'leader_phone': '+225 07 00 05 05 05'})
        cls.leader = cls.cell.action_create_leader_account()
        cls.cell2 = Cell.create({'name': 'Cellule Château', 'church_id': cls.church.id,
                                 'leader_name': 'Eric', 'leader_phone': '+225 07 00 06 06 06'})
        cls.leader2 = cls.cell2.action_create_leader_account()
        cls.ev = cls.env['church.evangelist'].create({
            'name': 'Awa Koné', 'phone': '+225 07 00 01 01 01', 'church_id': cls.church.id})
        Member = cls.env['church.member']
        cls.old = Member.create({'name': 'YAO', 'first_name': 'Marc', 'church_id': cls.church.id,
                                 'person_profile': 'old_member', 'member_type': 'integrated',
                                 'prayer_cell_id': cls.cell2.id})
        cls.new = Member.create({'name': 'BAMBA', 'first_name': 'Ali', 'church_id': cls.church.id})

    def _confide(self, **params):
        return self._rpc('/api/church/followup/create', self.manager, member_id=self.old.id, **params)

    def test_manager_confides_an_old_member_to_a_cell(self):
        res = self._confide()
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(res['followup']['followed_by_name'], 'Cellule Château', "Sa cellule, par défaut")
        self.old.followup_ids.action_abandon('moved')
        # Une app ancienne envoie un évangéliste : l'ancien membre va quand même à une cellule.
        res = self._confide(evangelist_id=self.ev.id, prayer_cell_id=self.cell.id)
        self.assertEqual(res['followup']['followed_by'], 'cell')
        self.assertEqual(res['followup']['prayer_cell_name'], 'Cellule Riviera')

    def test_evangelist_cannot_take_an_old_member(self):
        res = self._rpc('/api/church/followup/create', self.ev.mobile_user_id, member_id=self.old.id)
        self.assertEqual(res['code'], 'invalid')
        self.assertIn('ancien membre', res['message'])

    def test_cell_leader_follows_reports_and_decides(self):
        followup_id = self._confide(prayer_cell_id=self.cell.id)['followup']['id']
        listed = self._rpc('/api/church/followups', self.leader)['followups']
        self.assertEqual([f['id'] for f in listed], [followup_id])
        self.assertEqual(self._rpc('/api/church/followups', self.leader2)['followups'], [],
                         "L'autre cellule ne voit pas ce suivi")
        detail = self._rpc('/api/church/followup/detail', self.leader, followup_id=followup_id)['followup']
        self.assertEqual((detail['followed_by'], detail['target_cell_id']), ('cell', self.cell.id))
        res = self._rpc('/api/church/followup/week/save', self.leader, followup_id=followup_id,
                        week_number=1, call_made=True, cell_attendance=True, spiritual_state='good')
        self.assertEqual(res['status'], 'success', res)
        week = self.env['church.followup.week'].browse(res['week']['id'])
        self.assertEqual(week.reported_by_id, self.leader)
        self.assertTrue(week.cell_attendance)
        detail = self._rpc('/api/church/followup/detail', self.leader, followup_id=followup_id)['followup']
        self.assertEqual(detail['weeks'][0]['reported_by_name'], 'Fatou')
        res = self._rpc('/api/church/followup/detail', self.leader2, followup_id=followup_id)
        self.assertEqual(res['code'], 'invalid')
        # Le membre suivi s'ouvre au responsable de la cellule qui le suit.
        res = self._rpc('/api/church/member/detail', self.leader, member_id=self.old.id)
        self.assertEqual(res['status'], 'success', res)
        # Décider : transférer à une autre cellule.
        res = self._rpc('/api/church/followup/action', self.leader, followup_id=followup_id,
                        action='transfer', transferred_to_cell_id=self.cell2.id)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual([f['followed_by_name'] for f in
                          self._rpc('/api/church/followups', self.leader2)['followups']
                          if f['state'] == 'in_progress'], ['Cellule Château'])

    def test_todo_and_dashboard_know_the_cells(self):
        followup = self.env['church.followup'].create({
            'church_id': self.church.id, 'member_id': self.old.id, 'prayer_cell_id': self.cell.id,
            'start_date': fields.Date.today() - timedelta(weeks=3)})
        kinds = [i['kind'] for i in self._rpc('/api/church/todo', self.leader)['items']]
        self.assertIn('report_overdue', kinds)
        items = self._rpc('/api/church/todo', self.manager)['items']
        late = [i for i in items if i['kind'] == 'cell_late']
        self.assertEqual(late[0]['prayer_cell_id'], self.cell.id)
        self.assertIn('Cellule Riviera', late[0]['title'])
        board = self._rpc('/api/church/dashboard', self.leader)['dashboard']
        self.assertEqual(board['active_followups'], 1)
        board = self._rpc('/api/church/dashboard', self.manager)['dashboard']
        self.assertEqual([c['name'] for c in board['cell_stats']], ['Cellule Riviera'])
        report = self._rpc('/api/church/report/followup', self.manager, prayer_cell_id=self.cell.id)['report']
        self.assertEqual((report['follower']['kind'], report['follower']['active']), ('cell', 1))
        self.assertEqual(report['followups'][0]['member_name'], followup.member_id.display_name_custom)
        res = self._rpc('/api/church/report/followup', self.leader2, prayer_cell_id=self.cell.id)
        self.assertEqual(res['code'], 'invalid', "Le rapport d'une autre cellule est fermé")

    def test_import_confides_old_members_to_cells(self):
        bad = self._run('to_follow', [
            {'Profil': 'Ancien membre', 'Nom': 'TRA', 'Prénoms': 'Lou', 'Évangéliste': 'Awa Koné'},
            {'Nom': 'KONE', 'Prénoms': 'Ali', 'Cellule qui suit': 'Cellule Riviera'},
        ])
        self.assertFalse(bad['ok'])
        text = '\n'.join(bad['errors'])
        self.assertIn('Ligne 2 : un ancien membre est suivi par une cellule', text)
        self.assertIn('Ligne 3 : une nouvelle personne est suivie par un évangéliste', text)
        good = self._run('to_follow', [
            {'Profil': 'Ancien membre', 'Nom': 'TRA', 'Prénoms': 'Lou', 'Cellule qui suit': 'Cellule Riviera'},
            {'Profil': 'Ancien membre', 'Nom': 'GBA', 'Prénoms': 'Eve'},
            {'Nom': 'KONE', 'Prénoms': 'Ali', 'Évangéliste': 'Awa Koné'},
        ])
        self.assertTrue(good['ok'], good)
        Member = self.env['church.member']
        self.assertEqual(Member.search([('name', '=', 'TRA')]).followup_ids.prayer_cell_id, self.cell)
        self.assertEqual(Member.search([('name', '=', 'GBA')]).member_type, 'new', "Dans « À attribuer »")
        self.assertEqual(Member.search([('name', '=', 'KONE')]).followup_ids.evangelist_id, self.ev)
        self.assertIn('2 suivi(s) démarré(s)', ' '.join(good['warnings']))
