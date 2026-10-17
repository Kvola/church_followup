from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestCellFollowup(TransactionCase):
    """Un ancien membre est suivi par une cellule de prière, une nouvelle
    personne par un évangéliste — jamais l'inverse, jamais personne."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.env.company.country_id = cls.env.ref('base.ci')
        cls.church = cls.env['equipment.church'].create({'name': 'Église A', 'followup_enabled': True})
        Cell = cls.env['church.prayer.cell']
        cls.cell = Cell.create({'name': 'Cellule Riviera', 'church_id': cls.church.id,
                                'leader_name': 'Fatou', 'leader_phone': '+225 07 00 05 05 05'})
        cls.cell.action_create_leader_account()
        cls.cell2 = Cell.create({'name': 'Cellule Château', 'church_id': cls.church.id,
                                 'leader_name': 'Eric', 'leader_phone': '+225 07 00 06 06 06'})
        cls.cell2.action_create_leader_account()
        cls.lonely = Cell.create({'name': 'Cellule sans responsable', 'church_id': cls.church.id})
        cls.group = cls.env['church.age.group'].create({
            'name': 'Mariés', 'church_id': cls.church.id, 'group_type': 'married', 'gender': 'mixed'})
        cls.ev = cls.env['church.evangelist'].create({
            'name': 'Awa', 'phone': '+225 07 00 01 01 01', 'church_id': cls.church.id})
        Member = cls.env['church.member']
        cls.old = Member.create({'name': 'YAO', 'first_name': 'Marc', 'church_id': cls.church.id,
                                 'person_profile': 'old_member', 'member_type': 'integrated',
                                 'prayer_cell_id': cls.cell.id})
        cls.new = Member.create({'name': 'BAMBA', 'first_name': 'Ali', 'church_id': cls.church.id})
        cls.Followup = cls.env['church.followup']

    def _follow(self, member, **vals):
        return self.Followup.create(dict({'church_id': self.church.id, 'member_id': member.id}, **vals))

    def test_old_member_is_followed_by_his_own_cell(self):
        followup = self._follow(self.old)
        self.assertEqual(followup.prayer_cell_id, self.cell, "Sa cellule, par défaut")
        self.assertEqual((followup.followed_by, followup.followed_by_name), ('cell', 'Cellule Riviera'))
        self.assertFalse(followup.evangelist_id)
        self.assertEqual(followup.target_cell_id, self.cell, "Au terme, il revient dans la cellule qui l'a suivi")
        other = self._follow(self.new, evangelist_id=self.ev.id)
        self.assertEqual((other.followed_by, other.followed_by_name), ('evangelist', 'Awa'))

    def test_profile_decides_who_follows(self):
        with self.assertRaises(ValidationError) as refused:
            self._follow(self.old, evangelist_id=self.ev.id)
        self.assertIn('ancien membre', str(refused.exception))
        with self.assertRaises(ValidationError) as refused:
            self._follow(self.new, prayer_cell_id=self.cell.id)
        self.assertIn('nouvelle personne', str(refused.exception))
        with self.assertRaises(ValidationError):
            self._follow(self.new)

    def test_old_member_without_cell_needs_one_chosen(self):
        self.old.prayer_cell_id = False
        with self.assertRaises(UserError) as refused:
            self._follow(self.old)
        self.assertIn('sans cellule', str(refused.exception))
        self.assertEqual(self._follow(self.old, prayer_cell_id=self.cell2.id).prayer_cell_id, self.cell2)

    def test_a_cell_without_reachable_leader_cannot_follow(self):
        with self.assertRaises(UserError) as refused:
            self._follow(self.old, prayer_cell_id=self.lonely.id)
        self.assertIn('ouvrez d\'abord le compte', str(refused.exception))
        followup = self._follow(self.old)
        with self.assertRaises(UserError):
            followup.prayer_cell_id = self.lonely

    def test_transfer_to_another_cell(self):
        followup = self._follow(self.old)
        followup.transferred_to_cell_id = self.cell
        with self.assertRaises(ValidationError):
            followup.action_transfer()
        followup.transferred_to_cell_id = self.cell2
        followup.action_transfer()
        self.assertEqual(followup.state, 'transferred')
        current = self.old.followup_ids.filtered(lambda f: f.state == 'in_progress')
        self.assertEqual(current.prayer_cell_id, self.cell2)
        self.assertEqual(current.target_cell_id, self.cell2)

    def test_cell_attendance_ticks_the_weekly_report(self):
        followup = self._follow(self.old, start_date='2026-10-05')
        week = self.env['church.followup.week'].create({'followup_id': followup.id, 'week_number': 1})
        self.assertFalse(week.cell_attendance)
        self.env['church.attendance.cell'].create({
            'church_id': self.church.id, 'prayer_cell_id': self.cell.id, 'member_id': self.old.id,
            'date': '2026-10-09'})
        self.assertTrue(week.cell_attendance, "Le pointage de la cellule coche la semaine")
        # Pointée avant que le rapport existe : la semaine naît cochée.
        self.env['church.attendance.cell'].create({
            'church_id': self.church.id, 'prayer_cell_id': self.cell.id, 'member_id': self.old.id,
            'date': '2026-10-16'})
        week2 = self.env['church.followup.week'].create({'followup_id': followup.id, 'week_number': 2})
        self.assertTrue(week2.cell_attendance)

    def test_profile_cannot_change_under_a_running_followup(self):
        followup = self._follow(self.new, evangelist_id=self.ev.id)
        with self.assertRaises(UserError):
            self.new.person_profile = 'old_member'
        followup.action_abandon('moved')
        self.new.person_profile = 'old_member'
        self.assertEqual(self.new.person_profile, 'old_member', "Sans suivi en cours, on corrige")

    def test_integration_of_an_old_member(self):
        followup = self._follow(self.old)
        followup.target_age_group_id = self.group
        followup.integration_justification = 'Revenu fidèlement'
        followup.action_integrate()
        self.assertEqual((self.old.member_type, self.old.prayer_cell_id), ('integrated', self.cell))
        self.assertEqual(self.old.person_profile, 'old_member')

    def test_assign_wizard_confides_each_to_the_right_follower(self):
        wizard = self.env['church.followup.assign'].create({
            'member_ids': [(6, 0, (self.old | self.new).ids)], 'evangelist_id': self.ev.id})
        wizard.action_confirm()
        self.assertEqual(self.old.followup_ids.prayer_cell_id, self.cell)
        self.assertEqual(self.new.followup_ids.evangelist_id, self.ev)

    def test_assign_wizard_confides_no_one_until_everyone_has_a_follower(self):
        self.old.prayer_cell_id = False
        wizard = self.env['church.followup.assign'].create({
            'member_ids': [(6, 0, (self.old | self.new).ids)]})
        with self.assertRaises(UserError) as refused:
            wizard.action_confirm()
        text = str(refused.exception)
        self.assertIn('YAO Marc (ancien membre sans cellule', text)
        self.assertIn('BAMBA Ali (nouvelle personne', text)
        self.assertFalse((self.old | self.new).followup_ids)

    def test_manager_todo_survives_cell_followups(self):
        manager = self.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 09 09 09', 'role': 'manager', 'church_id': self.church.id})
        self._follow(self.old, start_date='2026-01-05')
        items = manager._todo_items()
        self.assertFalse([i for i in items if i['kind'] == 'evangelist_late' and not i.get('evangelist_id')])
