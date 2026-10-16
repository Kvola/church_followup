import json
from datetime import timedelta
from unittest.mock import patch

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
        Church = cls.env['equipment.church']
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

    # ─── Outils ───────────────────────────────────────────────────────

    def _rpc(self, path, token=None, **params):
        payload = {'jsonrpc': '2.0', 'method': 'call', 'params': params}
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer %s' % token
        resp = self.url_open(path, data=json.dumps(payload).encode(), headers=headers)
        body = resp.json()
        self.assertNotIn('error', body, "Une trace technique a fui : %s" % body.get('error'))
        return body['result']

    def _login(self, account):
        """Une session ouverte sans passer par le code (le parcours du code a ses tests)."""
        return {'token': account._open_session('test')}

    def _as(self, account, path, **params):
        return self._rpc(path, **self._login(account), **params)

    def _otp(self, identifier):
        """Demande un code et le rend, comme le ferait le téléphone qui le reçoit."""
        self.env['ir.config_parameter'].sudo().set_param('church_followup.otp_debug_return', '1')
        with patch.object(type(self.env['otp.code']), '_send', lambda *a, **k: None):
            res = self._rpc('/api/church/auth/request_otp', identifier=identifier)
        self.assertEqual(res['status'], 'success', res)
        return res

    def _sign_in(self, identifier, **params):
        code = self._otp(identifier)['debug_otp']
        return self._rpc('/api/church/auth/verify_otp', identifier=identifier, code=code, **params)

    # ─── Authentification par code (otp_auth) ─────────────────────────

    def test_routes_refuse_calls_without_session(self):
        res = self._rpc('/api/church/pastors', church_id=self.church.id)
        self.assertEqual(res['code'], 'auth_required')
        res = self._rpc('/api/church/pastors', token='x' * 43)
        self.assertEqual(res['code'], 'auth_required')

    def test_code_signs_in_whatever_the_phone_formatting(self):
        res = self._sign_in('+2250700 0001', device_label='Tecno')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(res['user']['id'], self.ev1.mobile_user_id.id)
        session = self.env['church.mobile.session'].search([('mobile_user_id', '=', self.ev1.mobile_user_id.id)])
        self.assertEqual(session.device_label, 'Tecno')
        self.assertNotEqual(session.token_hash, res['token'], "Le jeton n'est jamais stocké en clair")
        self.assertEqual(self._rpc('/api/church/dashboard', token=res['token'])['status'], 'success')

    def test_code_can_be_received_by_email(self):
        self.manager.email = ' Resp@Exemple.CI '
        self.assertEqual(self.manager.email, 'resp@exemple.ci')
        res = self._sign_in('resp@exemple.ci')
        self.assertEqual(res['user']['id'], self.manager.id)

    def test_unknown_identifier_gets_the_same_answer_and_no_code(self):
        unknown = self._otp('+225 01 99 99 99 99')
        known = self._otp(self.ev2.mobile_user_id.phone)
        self.assertEqual(unknown['message'], known['message'])
        self.assertNotIn('debug_otp', unknown, "Aucun code n'est émis pour un numéro inconnu")
        self.assertIn('debug_otp', known)

    def test_wrong_code_is_refused_and_code_is_single_use(self):
        identifier = self.ev1.mobile_user_id.phone
        code = self._otp(identifier)['debug_otp']
        wrong = '000000' if code != '000000' else '111111'
        res = self._rpc('/api/church/auth/verify_otp', identifier=identifier, code=wrong)
        self.assertEqual(res['code'], 'auth_failed')
        self.assertEqual(self._rpc('/api/church/auth/verify_otp', identifier=identifier, code=code)['status'],
                         'success')
        again = self._rpc('/api/church/auth/verify_otp', identifier=identifier, code=code)
        self.assertEqual(again['code'], 'auth_failed', "Un code ne sert qu'une fois")

    def test_requests_for_one_number_are_throttled(self):
        identifier = self.ev2.mobile_user_id.phone
        for _i in range(3):
            self._otp(identifier)
        res = self._rpc('/api/church/auth/request_otp', identifier=identifier)
        self.assertEqual(res['code'], 'rate_limited')

    def test_one_enters_one_s_own_church_and_stays_there(self):
        """Hors administrateur, on entre dans son église et l'on n'en change pas."""
        elsewhere = self.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 00 09', 'role': 'evangelist', 'church_id': self.other.id})
        res = self._sign_in(self.manager.phone)
        self.assertEqual([a['id'] for a in res['accounts']], [res['user']['id']],
                         "Aucune autre église n'est proposée")
        self.assertFalse(res['user']['can_change_church'])
        target = elsewhere if res['user']['id'] == self.manager.id else self.manager
        refused = self._rpc('/api/church/auth/switch', token=res['token'], account_id=target.id)
        self.assertEqual(refused['code'], 'forbidden')
        refused = self._rpc('/api/church/auth/set_church', token=res['token'], church_id=self.other.id)
        self.assertEqual(refused['code'], 'forbidden')

    def test_only_the_administrator_changes_church(self):
        admin = self.env['church.mobile.user'].create({
            'name': 'Admin', 'phone': '+225 07 00 00 77', 'role': 'super_admin'})
        res = self._sign_in(admin.phone)
        self.assertTrue(res['user']['can_change_church'])
        token = res['token']
        chosen = self._rpc('/api/church/auth/set_church', token=token, church_id=self.other.id)
        self.assertEqual(chosen['status'], 'success', chosen)
        self.assertEqual(chosen['user']['church_id'], self.other.id)
        members = self._rpc('/api/church/members', token=token)['members']
        self.assertEqual({m['id'] for m in members}, {self.stranger.id},
                         "L'administrateur voit l'église qu'il a choisie")
        back = self._rpc('/api/church/auth/set_church', token=token, church_id=0)
        self.assertTrue(back['user']['is_multi_church'])
        unknown = self._rpc('/api/church/auth/set_church', token=token, church_id=999999)
        self.assertEqual(unknown['code'], 'invalid')

    def _pastor(self, phone, church):
        return self.env['equipment.pastor'].create({
            'name': 'Pasteur Yao', 'phone': phone, 'church_id': church.id,
            'country_id': self.env.ref('base.ci').id})

    def test_pastor_enters_the_church_he_is_assigned_to(self):
        pastor = self._pastor('0700000055', self.church)
        res = self._sign_in('+225 0700000055')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(res['user']['church_id'], self.church.id)
        self.assertEqual(res['user']['role'], 'manager')
        self.assertTrue(res['user']['is_pastor'])
        self.assertEqual(res['user']['role_label'], 'Pasteur', "Il se lit pasteur, avec les droits d'un responsable")
        account = self.env['church.mobile.user'].browse(res['user']['id'])
        self.assertEqual(account.pastor_id, pastor)
        # Muté : à la connexion suivante, il entre dans la nouvelle église.
        pastor.church_id = self.other
        # Second code tout de suite : on lève le délai anti-renvoi de 60 s.
        self.env['otp.code'].sudo().search([]).write({'sent_at': False})
        again = self._sign_in('+225 0700000055')
        self.assertEqual(again['user']['id'], account.id)
        self.assertEqual(again['user']['church_id'], self.other.id)

    def test_pastor_lands_in_his_church_even_with_another_account(self):
        """Évangéliste ailleurs, pasteur ici : c'est l'église du pasteur qui s'ouvre."""
        self.env['church.mobile.user'].create({
            'name': 'Pasteur Yao', 'phone': '+225 07 00 00 66', 'role': 'evangelist',
            'church_id': self.other.id})
        self._pastor('0700000066', self.church)
        res = self._sign_in('+225 0700000066')
        self.assertEqual(res['user']['church_id'], self.church.id)
        self.assertEqual(res['user']['role'], 'manager')

    def test_inactive_pastor_no_longer_enters(self):
        pastor = self._pastor('0700000044', self.church)
        self.assertEqual(self._sign_in('+225 0700000044')['status'], 'success')
        pastor.active = False
        res = self._otp('+225 0700000044')
        self.assertNotIn('debug_otp', res, "Plus pasteur, plus de code")

    def test_expired_session_is_refused(self):
        session = self._login(self.ev1.mobile_user_id)
        self.ev1.mobile_user_id.session_ids.sudo().write({'expires_at': fields.Datetime.now() - timedelta(minutes=1)})
        res = self._rpc('/api/church/dashboard', **session)
        self.assertEqual(res['code'], 'auth_required')

    def test_deactivated_account_loses_its_session(self):
        session = self._login(self.ev1.mobile_user_id)
        self.ev1.mobile_user_id.active = False
        self.assertEqual(self._rpc('/api/church/dashboard', **session)['code'], 'auth_required')

    def test_logout_closes_only_this_phone(self):
        account = self.ev1.mobile_user_id
        first, second = self._login(account), self._login(account)
        self.assertEqual(self._rpc('/api/church/auth/logout', **first)['status'], 'success')
        self.assertEqual(self._rpc('/api/church/dashboard', **first)['code'], 'auth_required')
        self.assertEqual(self._rpc('/api/church/dashboard', **second)['status'], 'success')

    def test_invitation_carries_no_secret(self):
        message = self.ev1.mobile_user_id.get_invitation_message()
        self.assertIn('/apps/suivi-evangelisation', message)
        self.assertIn(self.ev1.mobile_user_id.phone, message)
        self.assertNotIn('PIN', message)

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

    # ─── Interruption et parcours (phase E) ───────────────────────────

    def test_abandon_through_api_requires_reason_and_shows_in_journey(self):
        ev2 = self.ev2.mobile_user_id
        res = self._as(ev2, '/api/church/followup/action', followup_id=self.f2.id, action='abandon')
        self.assertEqual(res['code'], 'refused')
        res = self._as(ev2, '/api/church/followup/action', followup_id=self.f2.id, action='abandon',
                       reason='unreachable', note='Numéro coupé')
        self.assertEqual(res['status'], 'success', res)
        listing = self._as(self.manager, '/api/church/followups/to_assign')
        interrupted = {m['id']: m for m in listing['interrupted']}
        self.assertEqual(interrupted[self.m2.id]['abandon_reason'], 'unreachable')
        journey = self._as(self.manager, '/api/church/member/detail', member_id=self.m2.id)['member']['journey']
        self.assertEqual([(j['state'], j['abandon_note']) for j in journey], [('abandoned', 'Numéro coupé')])

    # ─── Points de contrôle (phase F) ─────────────────────────────────

    def test_cell_leader_records_checkpoints_of_own_cell_only(self):
        self.church.integration_min_attendance = 0
        group = self.env['church.age.group'].create({
            'name': 'G', 'church_id': self.church.id, 'group_type': 'youth', 'gender': 'mixed'})
        f2 = self.f2
        f2.write({'target_cell_id': self.cell.id, 'target_age_group_id': group.id})
        f2.action_integrate()
        mine = self.m2.checkpoint_ids.filtered(lambda c: c.milestone == '3m')
        listing = self._as(self.leader, '/api/church/checkpoints')['checkpoints']
        self.assertEqual([c['id'] for c in listing if c['member_id'] == self.m2.id], self.m2.checkpoint_ids.ids)

        res = self._as(self.leader, '/api/church/checkpoint/save', checkpoint_id=mine.id,
                       result='favorable', baptism_date='2026-12-06', notes='Assidue')
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(str(self.m2.baptism_date), '2026-12-06')

        self.m2.prayer_cell_id = self.cell2
        other = self.m2.checkpoint_ids.filtered(lambda c: c.milestone == '6m')
        res = self._as(self.leader, '/api/church/checkpoint/save', checkpoint_id=other.id, result='favorable')
        self.assertEqual(res['status'], 'error', "Une autre cellule que la sienne")
        self.assertEqual(self._as(self.ev1.mobile_user_id, '/api/church/checkpoints')['code'], 'forbidden')

    # ─── Responsables et pasteurs (phase G) ───────────────────────────

    def test_replacing_cell_leader_through_api(self):
        old_session = self._login(self.leader)
        res = self._as(self.manager, '/api/church/cell_leader/create', prayer_cell_id=self.cell.id,
                       name='Nouveau Chef', phone='+225 07 00 00 31')
        self.assertEqual(res['status'], 'success', res)
        self.assertIn('Nouveau Chef', res['invitation'])
        self.assertEqual(self._rpc('/api/church/dashboard', **old_session)['code'], 'auth_required',
                         "L'ancien responsable n'a plus accès")
        self.assertEqual(self.cell.mobile_user_id.phone_key, '22507000031')

    def test_adding_a_church_reuses_the_directory(self):
        admin = self.env['church.mobile.user'].create({
            'name': 'Admin', 'phone': '+225 07 00 00 99', 'role': 'super_admin'})
        known = self.env['equipment.church'].create({'name': 'Église BNG Angré'})
        self.assertFalse(known.followup_enabled)
        res = self._as(admin, '/api/church/churches/create', name='EGLISE  b.n.g   ANGRE')
        self.assertEqual(res['church']['id'], known.id, "Même église écrite autrement : reprise, pas doublée")
        self.assertTrue(known.followup_enabled)
        listed = [c['id'] for c in self._as(admin, '/api/church/churches')['churches']]
        self.assertIn(known.id, listed)
        found = self._as(admin, '/api/church/churches/directory', query='Angré')['churches']
        self.assertNotIn(known.id, [c['id'] for c in found], "Déjà dans le suivi : plus proposée")

    def test_pastors_are_read_from_the_directory(self):
        self.env['equipment.pastor'].create({
            'name': 'Kouadio Emmanuel', 'phone': '+225 07 00 00 61', 'church_id': self.church.id})
        res = self._as(self.manager, '/api/church/pastors')
        self.assertEqual([(p['name'], p['is_titular']) for p in res['pastors']], [('Kouadio Emmanuel', True)])

    # ─── Comptes créés depuis l'app : toujours rattachés (phase H) ────

    def _admin(self):
        admin = self.env['church.mobile.user'].create({
            'name': 'Admin', 'phone': '+225 07 00 00 98', 'role': 'super_admin', 'church_id': self.church.id})
        return admin

    def test_created_evangelist_account_gets_its_evangelist_record(self):
        admin = self._admin()
        res = self._as(admin, '/api/church/admin/create_user', name='Nouvel Ev', phone='+225 07 00 00 41',
                       role='evangelist')
        self.assertEqual(res['status'], 'success', res)
        account = self.env['church.mobile.user'].browse(res['user']['id'])
        self.assertTrue(account.evangelist_id, "Sans fiche, il ne pourrait ouvrir aucun suivi")
        self.assertEqual(account.evangelist_id.church_id, self.church)
        created = self._as(account, '/api/church/followup/create', member_id=self.m1.id)
        self.assertEqual(created['status'], 'success', created)

    def test_cell_leader_account_requires_its_cell_and_replaces_the_previous_one(self):
        admin = self._admin()
        res = self._as(admin, '/api/church/admin/create_user', name='Chef', phone='+225 07 00 00 42',
                       role='cell_leader')
        self.assertEqual(res['code'], 'invalid')
        old_session = self._login(self.leader)
        res = self._as(admin, '/api/church/admin/create_user', name='Chef', phone='+225 07 00 00 42',
                       role='cell_leader', prayer_cell_id=self.cell.id)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual(self.cell.mobile_user_id.id, res['user']['id'])
        self.assertTrue(res['user']['invitation'])
        self.assertEqual(self._rpc('/api/church/dashboard', **old_session)['code'], 'auth_required')

    def test_role_change_requires_the_matching_link(self):
        admin = self._admin()
        manager2 = self.env['church.mobile.user'].create({
            'name': 'Resp 2', 'phone': '+225 07 00 00 43', 'role': 'manager', 'church_id': self.church.id})
        res = self._as(admin, '/api/church/admin/update_user', target_user_id=manager2.id, role='cell_leader')
        self.assertEqual(res['code'], 'invalid')
        self.assertEqual(manager2.role, 'manager')
        res = self._as(admin, '/api/church/admin/update_user', target_user_id=manager2.id, role='cell_leader',
                       prayer_cell_id=self.cell2.id)
        self.assertEqual(res['status'], 'success', res)
        self.assertEqual((manager2.prayer_cell_id, self.cell2.mobile_user_id), (self.cell2, manager2))
        res = self._as(admin, '/api/church/admin/update_user', target_user_id=manager2.id, role='evangelist')
        self.assertEqual(res['status'], 'success', res)
        self.assertTrue(manager2.evangelist_id)

    def test_report_and_lists_carry_what_the_app_reads(self):
        report = self._as(self.manager, '/api/church/report/followup', evangelist_id=self.ev2.id)['report']
        self.assertIn('extended', report['evangelist'])
        self.assertEqual(report['followups'][0]['duration_weeks'], self.f2.duration_weeks)
        listing = self._as(self.manager, '/api/church/followups')['followups']
        self.assertIn('average_score', listing[0])
        login = self._sign_in(self.leader.phone)
        self.assertEqual(login['user']['prayer_cell_name'], self.cell.name)
