from psycopg2 import IntegrityError

from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged
from odoo.tools import mute_logger


@tagged('post_install', '-at_install')
class TestLeadersPastors(TransactionCase):
    """Phase G : un responsable remplacé perd son accès ; le pasteur principal
    se désigne explicitement ; un sexe inconnu n'est jamais inventé."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['church.church'].create({'name': 'Église'})
        cls.cell = cls.env['church.prayer.cell'].create({
            'name': 'Cellule', 'church_id': cls.church.id,
            'leader_name': 'Ancien Chef', 'leader_phone': '+225 07 00 00 11'})

    # ─── Responsables ─────────────────────────────────────────────────

    def test_changing_leader_revokes_the_old_account(self):
        old = self.cell.action_create_leader_account()
        old._issue_pin()
        old._open_session()
        self.cell.write({'leader_name': 'Nouveau Chef', 'leader_phone': '+225 07 00 00 12'})
        self.assertFalse(old.active)
        self.assertFalse(old.prayer_cell_id)
        self.assertFalse(old.sudo().token_hash, "Sa session tombe")
        self.assertFalse(self.cell.mobile_user_id)
        new = self.cell.action_create_leader_account()
        self.assertNotEqual(new, old)
        self.assertEqual((new.name, new.phone_key, new.prayer_cell_id), ('Nouveau Chef', '22507000012', self.cell))

    def test_same_leader_keeps_account_and_follows_renaming(self):
        account = self.cell.action_create_leader_account()
        self.cell.write({'leader_name': 'Chef Renommé', 'leader_phone': '+2250700 0011'})
        self.assertEqual(self.cell.mobile_user_id, account)
        self.assertTrue(account.active)
        self.assertEqual(account.name, 'Chef Renommé')

    def test_former_leader_coming_back_gets_his_account_back(self):
        old = self.cell.action_create_leader_account()
        self.cell.leader_phone = '+225 07 00 00 12'
        self.cell.action_create_leader_account()
        self.cell.leader_phone = '+225 07 00 00 11'
        self.assertEqual(self.cell.action_create_leader_account(), old)
        self.assertTrue(old.active)

    def test_number_already_used_by_another_role_is_refused(self):
        evangelist = self.env['church.evangelist'].create({
            'name': 'Ev', 'phone': '+225 07 00 00 13', 'church_id': self.church.id})
        self.cell.leader_phone = '+225 07 00 00 13'
        with self.assertRaises(UserError):
            self.cell.action_create_leader_account()
        self.assertTrue(evangelist.mobile_user_id.active)

    def test_age_group_shares_the_same_rules(self):
        group = self.env['church.age.group'].create({
            'name': 'Jeunes', 'church_id': self.church.id, 'group_type': 'youth', 'gender': 'mixed',
            'leader_phone': '+225 07 00 00 21'})
        old = group.action_create_leader_account()
        self.assertEqual((old.role, old.age_group_id), ('group_leader', group))
        group.leader_phone = '+225 07 00 00 22'
        self.assertFalse(old.active)

    # ─── Pasteur principal ────────────────────────────────────────────

    def _pastor(self, name, pastor_type='assistant', **vals):
        return self.env['church.pastor'].create({
            'name': name, 'pastor_type': pastor_type, 'church_id': self.church.id, **vals})

    def test_a_second_principal_is_refused_by_the_database(self):
        self._pastor('P1', 'principal')
        with mute_logger('odoo.sql_db'), self.assertRaises(IntegrityError), self.cr.savepoint():
            self._pastor('P2', 'principal')

    def test_set_principal_demotes_the_current_one(self):
        p1 = self._pastor('P1', 'principal')
        p2 = self._pastor('P2')
        p2.action_set_principal()
        self.assertEqual((p1.pastor_type, p2.pastor_type), ('assistant', 'principal'))
        self.assertEqual(self.church.pastor_name, 'P2')

    def test_reactivating_a_former_principal_cannot_make_two(self):
        old = self._pastor('Ancien', 'principal')
        old.active = False
        old.flush_recordset()
        self._pastor('Actuel', 'principal')
        with mute_logger('odoo.sql_db'), self.assertRaises(IntegrityError), self.cr.savepoint():
            old.active = True
            old.flush_recordset()

    def test_archived_pastor_cannot_be_designated(self):
        p = self._pastor('Archivé', active=False)
        with self.assertRaises(UserError):
            p.action_set_principal()

    # ─── Sexe non renseigné ───────────────────────────────────────────

    def test_unknown_gender_is_flagged_not_invented(self):
        member = self.env['church.member'].create({
            'name': 'Sans', 'first_name': 'Sexe', 'church_id': self.church.id})
        self.assertFalse(member.gender)
        self.assertTrue(member.to_complete)
        manager = self.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 00 09', 'role': 'manager', 'church_id': self.church.id})
        self.assertIn('to_complete', [i['kind'] for i in manager._todo_items()])
        member.gender = 'female'
        self.assertFalse(member.to_complete)
