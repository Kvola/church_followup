from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

from odoo.tests import tagged

from .test_import import ImportCase


@tagged('post_install', '-at_install')
class TestOrganizationApi(ImportCase):
    """Phase 3 : cellules, groupes et quartiers créés et modifiés depuis l'app."""

    def test_manager_creates_a_cell_with_its_leader(self):
        district = self.env['church.district'].search([('name', '=', 'Riviera')])
        res = self._rpc('/api/church/cell/save', self.manager, name='Cellule Riviera', meeting_day='thursday',
                        meeting_time='19h', district_ids=[district.id], leader_name='Fatou',
                        leader_phone='07 00 05 05 05')
        self.assertEqual(res['status'], 'success', res)
        cell = res['cell']
        self.assertEqual((cell['meeting_time'], cell['meeting_day_label']), ('19:00', 'Jeudi'))
        self.assertEqual(cell['district_names'], ['Riviera'])
        self.assertTrue(cell['has_leader_account'], "Le responsable peut se connecter")
        again = self._rpc('/api/church/cell/save', self.manager, name='cellule  RIVIERA')
        self.assertEqual(again['code'], 'invalid')
        self.assertIn('existe déjà', again['message'])

    def test_archiving_a_cell_closes_its_leader_account(self):
        res = self._rpc('/api/church/cell/save', self.manager, name='C', leader_name='F',
                        leader_phone='0700050506')
        cell = self.env['church.prayer.cell'].browse(res['cell']['id'])
        account = cell.mobile_user_id
        self._rpc('/api/church/cell/save', self.manager, cell_id=cell.id, active=False)
        self.assertFalse(cell.active)
        self.assertFalse(account.active)
        listed = self._rpc('/api/church/cells', self.manager)['cells']
        self.assertNotIn(cell.id, [c['id'] for c in listed])
        listed = self._rpc('/api/church/cells', self.manager, include_archived=True)['cells']
        self.assertIn(cell.id, [c['id'] for c in listed], "Retrouvable pour la rouvrir")

    def test_cell_leader_changes_only_time_and_place_of_his_own_cell(self):
        cell = self.env['church.prayer.cell'].create({
            'name': 'Mienne', 'church_id': self.church.id, 'leader_name': 'F', 'leader_phone': '+2250700050507'})
        leader = cell.action_create_leader_account()
        other = self.env['church.prayer.cell'].create({'name': 'Autre', 'church_id': self.church.id})
        res = self._rpc('/api/church/cell/save', leader, cell_id=cell.id, meeting_time='18:30',
                        meeting_location='Chez nous', name='Renommée')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual((cell.meeting_time, cell.meeting_location, cell.name), ('18:30', 'Chez nous', 'Mienne'),
                         "Le nom reste la décision du responsable d'église")
        self.assertEqual(self._rpc('/api/church/cell/save', leader, cell_id=other.id,
                                   meeting_time='18:00')['code'], 'forbidden')
        self.assertEqual(self._rpc('/api/church/cell/save', leader, name='Nouvelle')['code'], 'forbidden')

    def test_age_group_and_district_are_saved_in_one_s_church(self):
        res = self._rpc('/api/church/age_group/save', self.manager, name='Jeunes')
        self.assertEqual(res['code'], 'invalid', "Type et sexe sont requis")
        ranges = self._rpc('/api/church/age_ranges', self.manager)['age_ranges']
        res = self._rpc('/api/church/age_group/save', self.manager, name='Mariés', group_type='married',
                        gender='mixed', age_range_id=ranges[0]['id'], church_id=self.other.id)
        self.assertEqual(res['status'], 'success', res)
        group = self.env['church.age.group'].browse(res['age_group']['id'])
        self.assertEqual(group.church_id, self.church, "Créé dans SON église, quoi que l'app envoie")
        self.assertEqual(res['age_group']['group_type_label'], 'Mariés')
        res = self._rpc('/api/church/district/save', self.manager, name='Abobo', city='Abidjan')
        self.assertEqual(res['district']['name'], 'Abobo')
        foreign = self.env['church.district'].search([('church_id', '=', self.other.id)], limit=1)
        res = self._rpc('/api/church/district/save', self.manager, district_id=foreign.id, name='X')
        self.assertEqual(res['code'], 'invalid', "Le quartier d'une autre église est introuvable")

    def test_evangelists_do_not_organise(self):
        ev = self.env['church.evangelist'].create({
            'name': 'Ev', 'phone': '+225 07 00 00 01 02', 'church_id': self.church.id}).mobile_user_id
        for path in ('/api/church/cell/save', '/api/church/age_group/save', '/api/church/district/save'):
            self.assertEqual(self._rpc(path, ev, name='X')['code'], 'forbidden', path)

    # ─── Le modèle par lien signé ─────────────────────────────────────

    def _link(self, account=None, kind='prayer_cell'):
        res = self._rpc('/api/church/import/template', account or self.manager, kind=kind)
        return res['download_path']

    def test_template_link_downloads_the_file(self):
        resp = self.url_open(self._link())
        self.assertEqual(resp.status_code, 200)
        self.assertIn('spreadsheetml', resp.headers['Content-Type'])
        self.assertIn('attachment', resp.headers['Content-Disposition'])
        self.assertEqual(resp.content[:2], b'PK', "Un classeur xlsx")

    def test_template_link_cannot_be_forged_or_reused_late(self):
        path = self._link()
        query = parse_qs(urlparse(path).query)
        forged = path.replace('c=%s' % query['c'][0], 'c=%s' % self.other.id)
        self.assertEqual(self.url_open(forged).status_code, 410, "Une autre église : signature fausse")
        with patch('odoo.addons.church_followup.controllers.mobile_api.time.time', return_value=4102444800):
            self.assertEqual(self.url_open(path).status_code, 410, "Lien expiré")
        self.manager.active = False
        self.assertEqual(self.url_open(path).status_code, 404, "Compte fermé : plus de modèle")
