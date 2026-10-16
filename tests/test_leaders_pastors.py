from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestLeadersPastors(TransactionCase):
    """Phase G : un responsable remplacé perd son accès ; les pasteurs
    sont ceux de l'annuaire ; un sexe inconnu n'est jamais inventé."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['equipment.church'].create({'name': 'Église'})
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

    # ─── Pasteurs : ceux de l'annuaire du réseau ──────────────────────

    def _pastor(self, name, phone, function='pastor', **vals):
        return self.env['equipment.pastor'].create({
            'name': name, 'phone': phone, 'function': function, 'church_id': self.church.id, **vals})

    def test_titular_pastors_come_from_the_directory(self):
        self._pastor('Kouadio Emmanuel', '+225 07 00 00 51')
        self._pastor('Gnahoré Samuel', '+225 07 00 00 52')
        self._pastor('Bamba Ruth', '+225 07 00 00 53', function='missionary')
        self._pastor('Ancien Pasteur', '+225 07 00 00 54', active=False)
        self.assertEqual(self.church.pastor_name, 'Gnahoré Samuel, Kouadio Emmanuel',
                         "Les titulaires actifs, sans missionnaire ni pasteur parti")

    def test_a_pastor_transferred_elsewhere_leaves_the_church(self):
        pastor = self._pastor('Kouadio Emmanuel', '+225 07 00 00 51')
        other = self.env['equipment.church'].create({'name': 'Église Ailleurs'})
        pastor.church_id = other
        self.assertFalse(self.church.pastor_name)
        self.assertEqual(other.pastor_name, 'Kouadio Emmanuel')

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
