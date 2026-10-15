import json
from datetime import timedelta

from odoo import fields
from odoo.tests import tagged
from odoo.tests.common import HttpCase


@tagged('post_install', '-at_install')
class TestChurchMobileApi(HttpCase):
    """Phase A : chaque route authentifiée, cloisonnée par église et par rôle,
    et qui répond par un message lisible au lieu d'une trace technique."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        Church = cls.env['church.church']
        cls.church = Church.create({'name': 'Église A'})
        cls.other = Church.create({'name': 'Église B'})
        cls.ev1 = cls.env['church.evangelist'].create({
            'name': 'Ev Un', 'phone': '+225 07 00 00 01', 'church_id': cls.church.id})
        cls.ev2 = cls.env['church.evangelist'].create({
            'name': 'Ev Deux', 'phone': '+225 07 00 00 02', 'church_id': cls.church.id})
        cls.manager = cls.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 00 09', 'role': 'manager', 'church_id': cls.church.id})
        cls.cell = cls.env['church.prayer.cell'].create({'name': 'Cellule 1', 'church_id': cls.church.id})
        cls.cell2 = cls.env['church.prayer.cell'].create({'name': 'Cellule 2', 'church_id': cls.church.id})
        cls.leader = cls.env['church.mobile.user'].create({
            'name': 'Chef cellule', 'phone': '+225 07 00 00 08', 'role': 'cell_leader',
            'church_id': cls.church.id, 'prayer_cell_id': cls.cell.id})

        def member(church, name, **vals):
            return cls.env['church.member'].create({
                'name': name, 'first_name': 'T', 'gender': 'female', 'church_id': church.id, **vals})
        cls.m1 = member(cls.church, 'Aka')
        cls.m2 = member(cls.church, 'Bamba')
        cls.stranger = member(cls.other, 'Etrangere')
        cls.f2 = cls.env['church.followup'].create({
            'church_id': cls.church.id, 'evangelist_id': cls.ev2.id, 'member_id': cls.m2.id})

        cls.pins = {}
        for account in (cls.ev1.mobile_user_id, cls.ev2.mobile_user_id, cls.manager, cls.leader):
            cls.pins[account.id] = account._issue_pin()

    # ─── Outils ───────────────────────────────────────────────────────

    def _rpc(self, path, **params):
        payload = {'jsonrpc': '2.0', 'method': 'call', 'params': params}
        resp = self.url_open(path, data=json.dumps(payload).encode(),
                             headers={'Content-Type': 'application/json'})
        body = resp.json()
        self.assertNotIn('error', body, "Une trace technique a fui : %s" % body.get('error'))
        return body['result']

    def _login(self, account, phone=None):
        res = self._rpc('/api/church/auth/login', phone=phone or account.phone, pin=self.pins[account.id])
        self.assertEqual(res['status'], 'success', res)
        return {'user_id': res['user']['id'], 'token': res['token']}

    def _as(self, account, path, **params):
        return self._rpc(path, **self._login(account), **params)

    # ─── Authentification ─────────────────────────────────────────────

    def test_routes_refuse_calls_without_session(self):
        res = self._rpc('/api/church/pastors', church_id=self.church.id)
        self.assertEqual(res['code'], 'auth_required')
        res = self._rpc('/api/church/pastors')
        self.assertEqual(res['code'], 'auth_required')

    def test_pin_and_token_are_never_stored_in_clear(self):
        account = self.ev1.mobile_user_id
        self.assertNotIn('pin', account._fields)
        self.assertTrue(account.sudo().pin_hash.startswith('$pbkdf2-sha512$'))
        session = self._login(account)
        self.assertNotEqual(account.sudo().token_hash, session['token'])
        for fname in ('pin_hash', 'token_hash'):
            self.assertEqual(account._fields[fname].groups, 'base.group_system')

    def test_login_ignores_phone_formatting(self):
        self._login(self.ev1.mobile_user_id, phone='+2250700 0001')

    def test_unknown_phone_and_wrong_pin_answer_alike(self):
        unknown = self._rpc('/api/church/auth/login', phone='+225 01 99 99 99', pin='000000')
        wrong = self._rpc('/api/church/auth/login', phone=self.ev1.mobile_user_id.phone, pin='000000')
        self.assertEqual(unknown['message'], wrong['message'])

    def test_failed_attempts_lock_phone_from_this_address_only(self):
        account = self.ev1.mobile_user_id
        for _i in range(6):
            self._rpc('/api/church/auth/login', phone=account.phone, pin='000000')
        res = self._rpc('/api/church/auth/login', phone=account.phone, pin=self.pins[account.id])
        self.assertEqual(res['status'], 'error', "Le bon PIN doit attendre la fin du blocage")
        # Un autre compte n'est pas touché par les échecs du premier.
        self._login(self.ev2.mobile_user_id)

    def test_expired_session_is_refused(self):
        session = self._login(self.ev1.mobile_user_id)
        self.ev1.mobile_user_id.sudo().token_expiry = fields.Datetime.now() - timedelta(minutes=1)
        res = self._rpc('/api/church/dashboard', **session)
        self.assertEqual(res['code'], 'auth_required')

    def test_deactivated_account_loses_its_session(self):
        session = self._login(self.ev1.mobile_user_id)
        self.ev1.mobile_user_id.active = False
        self.assertEqual(self._rpc('/api/church/dashboard', **session)['code'], 'auth_required')

    def test_new_pin_closes_session(self):
        account = self.ev1.mobile_user_id
        session = self._login(account)
        account._issue_pin()
        self.assertEqual(self._rpc('/api/church/dashboard', **session)['code'], 'auth_required')

    # ─── Rôles ────────────────────────────────────────────────────────

    def test_evangelist_cannot_touch_someone_elses_followup(self):
        ev1 = self.ev1.mobile_user_id
        for path, extra in (('/api/church/followup/detail', {}),
                            ('/api/church/followup/week/save', {'week_number': 1}),
                            ('/api/church/followup/action', {'action': 'abandon'})):
            res = self._as(ev1, path, followup_id=self.f2.id, **extra)
            self.assertEqual(res['status'], 'error', path)
        self.assertEqual(self.f2.state, 'in_progress')
        listed = self._as(ev1, '/api/church/followups')['followups']
        self.assertNotIn(self.f2.id, [f['id'] for f in listed])

    def test_owner_evangelist_can_report_on_own_followup(self):
        res = self._as(self.ev2.mobile_user_id, '/api/church/followup/week/save',
                       followup_id=self.f2.id, week_number=1, sunday_attendance=True, call_made='true')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(res['week']['score'], 5)

    def test_evangelist_cannot_change_member_status_or_cell(self):
        res = self._as(self.ev2.mobile_user_id, '/api/church/member/update', member_id=self.m2.id,
                       member_type='integrated', prayer_cell_id=self.cell.id, profession='Couturière')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(self.m2.member_type, 'in_followup')
        self.assertFalse(self.m2.prayer_cell_id)
        self.assertEqual(self.m2.profession, 'Couturière')

    def test_cell_leader_points_only_own_cell(self):
        res = self._as(self.leader, '/api/church/attendance/cell/save',
                       prayer_cell_id=self.cell2.id, member_ids=[self.m1.id])
        self.assertEqual(res['status'], 'error')
        self.assertFalse(self.env['church.attendance.cell'].search([('prayer_cell_id', '=', self.cell2.id)]))

    def test_cell_leader_sees_no_followups(self):
        self.assertEqual(self._as(self.leader, '/api/church/followups')['code'], 'forbidden')

    # ─── Cloisonnement par église ─────────────────────────────────────

    def test_links_to_another_church_are_refused(self):
        res = self._as(self.manager, '/api/church/member/create',
                       name='Intrus', first_name='T', gender='male', mentor_id=self.stranger.id)
        self.assertEqual(res['status'], 'error')
        self.assertFalse(self.env['church.member'].search([('name', '=', 'Intrus')]))

    def test_attendance_for_another_church_is_refused(self):
        res = self._as(self.manager, '/api/church/attendance/sunday/save',
                       member_ids=[self.stranger.id], date='2026-10-11')
        self.assertEqual(res['status'], 'error')
        self.assertFalse(self.env['church.attendance.sunday'].search([('member_id', '=', self.stranger.id)]))

    # ─── Validation et messages ───────────────────────────────────────

    def test_invalid_inputs_get_readable_messages(self):
        ev2 = self.ev2.mobile_user_id
        res = self._as(ev2, '/api/church/followup/week/save', followup_id=self.f2.id, week_number='abc')
        self.assertEqual(res['code'], 'invalid')
        self.assertIn('numéro de semaine', res['message'])
        res = self._as(ev2, '/api/church/member/update', member_id=self.m2.id, date_of_birth='11/10/2026')
        self.assertEqual(res['code'], 'invalid')
        self.assertIn('AAAA-MM-JJ', res['message'])
        res = self._as(ev2, '/api/church/followup/week/save', followup_id=self.f2.id,
                       week_number=1, spiritual_state='divin')
        self.assertEqual(res['code'], 'invalid')

    def test_business_refusal_keeps_its_message(self):
        res = self._as(self.manager, '/api/church/followup/create',
                       member_id=self.m2.id, evangelist_id=self.ev1.id)
        self.assertEqual(res['code'], 'refused')
        self.assertIn('suivi actif existe déjà', res['message'])

    def test_followup_duration_sent_by_the_app_is_kept(self):
        res = self._as(self.ev1.mobile_user_id, '/api/church/followup/create',
                       member_id=self.m1.id, duration_weeks=8)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(res['followup']['duration_weeks'], 8)

    # ─── Durée de suivi (phase B) ─────────────────────────────────────

    def test_to_assign_lists_waiting_people_with_their_proposal(self):
        self.m1.write({'planned_followup_weeks': 9})
        res = self._as(self.manager, '/api/church/followups/to_assign')
        rows = {m['id']: m for m in res['members']}
        self.assertIn(self.m1.id, rows)
        self.assertNotIn(self.m2.id, rows, "Déjà en suivi")
        self.assertEqual(rows[self.m1.id]['proposed_followup_weeks'], 9)
        self.assertEqual(self._as(self.ev1.mobile_user_id, '/api/church/followups/to_assign')['code'], 'forbidden')

    def test_followup_without_duration_takes_the_proposal(self):
        self.church.default_followup_weeks = 7
        res = self._as(self.ev1.mobile_user_id, '/api/church/followup/create', member_id=self.m1.id)
        self.assertEqual((res['followup']['duration_weeks'], res['followup']['duration_origin']), (7, 'church'))

    def test_extend_with_chosen_weeks(self):
        res = self._as(self.ev2.mobile_user_id, '/api/church/followup/action',
                       followup_id=self.f2.id, action='extend', weeks=3)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(self.f2.duration_weeks, 7)
        res = self._as(self.ev2.mobile_user_id, '/api/church/followup/action',
                       followup_id=self.f2.id, action='extend', weeks=40)
        self.assertEqual(res['code'], 'refused')

    def test_only_managers_change_the_church_default(self):
        res = self._as(self.ev1.mobile_user_id, '/api/church/settings', default_followup_weeks=9)
        self.assertEqual(res['code'], 'forbidden')
        res = self._as(self.manager, '/api/church/settings', default_followup_weeks=9)
        self.assertEqual(res['settings']['default_followup_weeks'], 9)

    # ─── Seuil d'intégration (phase C) ────────────────────────────────

    def test_integrate_below_threshold_through_api(self):
        self.f2.start_date = fields.Date.today() - timedelta(weeks=4)
        params = dict(followup_id=self.f2.id, action='integrate',
                      target_cell_id=self.cell.id, target_age_group_id=self.env['church.age.group'].create({
                          'name': 'G', 'church_id': self.church.id, 'group_type': 'youth', 'gender': 'mixed'}).id)
        ev2 = self.ev2.mobile_user_id
        detail = self._as(ev2, '/api/church/followup/detail', followup_id=self.f2.id)['followup']
        self.assertTrue(detail['below_threshold'])
        res = self._as(ev2, '/api/church/followup/action', **params)
        self.assertEqual(res['code'], 'refused')
        self.assertIn('justification', res['message'])
        res = self._as(ev2, '/api/church/followup/action', justification='Malade 3 semaines', **params)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(self.f2.integration_justification, 'Malade 3 semaines')

    # ─── Liste « À faire » (phase D) ──────────────────────────────────

    def test_todo_route_answers_each_role(self):
        res = self._as(self.manager, '/api/church/todo')
        self.assertEqual(res['status'], 'success', res)
        self.assertIn(self.m1.id, [i.get('member_id') for i in res['items'] if i['kind'] == 'to_assign'])
        self.assertEqual(self._as(self.leader, '/api/church/todo')['count'], 0)
