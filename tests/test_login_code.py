"""Le code de connexion arrive à qui y a droit — et l'on sait pourquoi sinon.

Essai réel du 2026-10-16 : un administrateur demande un code avec son numéro,
puis son e-mail ; rien n'arrive. Il n'avait pas de compte mobile, et la route
répond pareil qu'un compte existe ou non (anti-énumération). Rien ne disait
pourquoi. D'où : l'administrateur du suivi dans Odoo entre par son identité
Odoo ; le back-office envoie un code et dit par où il est parti ; le journal
trace les demandes sans compte.
"""
import json
from unittest.mock import patch

from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestLoginCode(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True, no_reset_password=True))
        cls.env.company.country_id = cls.env.ref('base.ci')
        cls.env['ir.config_parameter'].sudo().set_param('church_followup.otp_debug_return', '1')
        cls.church = cls.env['equipment.church'].create({'name': 'Église Code'})
        Users = cls.env['res.users']
        cls.admin = Users.create({
            'name': 'Dibi Admin', 'login': 'admin.suivi@exemple.ci', 'email': 'admin.suivi@exemple.ci',
            'phone': '07 49 00 00 01',
            'group_ids': [(4, cls.env.ref('church_followup.group_church_admin').id)]})
        cls.clerk = Users.create({
            'name': 'Simple Employé', 'login': 'employe@exemple.ci', 'email': 'employe@exemple.ci',
            'group_ids': [(4, cls.env.ref('base.group_user').id)]})

    def _rpc(self, path, token=None, **params):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer %s' % token
        with patch.object(type(self.env['otp.code']), '_send', lambda *a, **k: None):
            resp = self.url_open(path, data=json.dumps({'jsonrpc': '2.0', 'method': 'call',
                                                        'params': params}).encode(), headers=headers)
        return resp.json()['result']

    def _sign_in(self, identifier):
        code = self._rpc('/api/church/auth/request_otp', identifier=identifier).get('debug_otp')
        self.assertTrue(code, "Aucun code émis pour %s" % identifier)
        return self._rpc('/api/church/auth/verify_otp', identifier=identifier, code=code)

    def test_odoo_admin_of_the_followup_signs_in_by_email(self):
        res = self._sign_in('Admin.Suivi@exemple.ci')
        self.assertEqual(res['status'], 'success', res)
        account = self.env['church.mobile.user'].browse(res['user']['id'])
        self.assertEqual((account.role, account.user_id), ('super_admin', self.admin))
        self.assertEqual(self._rpc('/api/church/dashboard', token=res['token'])['status'], 'success')
        # Le compte ouvert est réutilisé, pas recréé (un second code attendrait
        # la minute de délai entre deux envois : on interroge le modèle).
        again = self.env['church.mobile.user']._accounts_for_identifier('admin.suivi@exemple.ci', 'email')
        self.assertEqual(again, account)

    def test_odoo_admin_of_the_followup_signs_in_by_phone(self):
        res = self._sign_in('+225 07 49 00 00 01')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(self.env['church.mobile.user'].browse(res['user']['id']).phone_e164, '+2250749000001')

    def test_other_odoo_users_get_nothing(self):
        res = self._rpc('/api/church/auth/request_otp', identifier='employe@exemple.ci')
        self.assertEqual(res['status'], 'success', "Même réponse qu'un compte existe ou non")
        self.assertNotIn('debug_otp', res)
        self.assertFalse(self.env['church.mobile.user'].search([('email', '=', 'employe@exemple.ci')]))

    def test_a_deactivated_admin_account_is_not_reopened(self):
        account = self.env['church.mobile.user'].browse(self._sign_in('admin.suivi@exemple.ci')['user']['id'])
        account.active = False
        res = self._rpc('/api/church/auth/request_otp', identifier='admin.suivi@exemple.ci')
        self.assertNotIn('debug_otp', res)

    def test_unknown_identifier_is_logged(self):
        with self.assertLogs('odoo.addons.church_followup.controllers.mobile_api', 'INFO') as logs:
            self._rpc('/api/church/auth/request_otp', identifier='+225 07 49 94 33 27')
        self.assertIn('aucun compte du suivi', '\n'.join(logs.output))
        self.assertNotIn('49943327', '\n'.join(logs.output), "Le numéro est masqué dans le journal")

    def test_back_office_sends_a_code_that_the_app_accepts(self):
        account = self.env['church.mobile.user'].create({
            'name': 'Awa Koné', 'phone': '07 00 01 01 01', 'role': 'manager', 'church_id': self.church.id})
        with patch.object(type(self.env['otp.code']), '_send', lambda *a, **k: None):
            action = account.action_send_login_code()
        wizard = self.env['church.mobile.user.code'].browse(action['res_id'])
        self.assertEqual(wizard.identifier, '+2250700010101')
        self.assertRegex(wizard.code, r'^\d{6}$')
        self.assertIn('+2250700010101', wizard.report)
        res = self._rpc('/api/church/auth/verify_otp', identifier='07 00 01 01 01', code=wizard.code)
        self.assertEqual(res['status'], 'success', res)

    def test_an_email_only_account_has_no_phone_siblings(self):
        lone = self.env['church.mobile.user'].create({
            'name': 'Sans numéro', 'email': 'seul@exemple.ci', 'role': 'super_admin'})
        self.env['church.mobile.user'].create({
            'name': 'Autre', 'phone': '07 00 02 02 02', 'role': 'manager', 'church_id': self.church.id})
        self.assertEqual(lone._sibling_accounts(), lone)
