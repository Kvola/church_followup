from datetime import date

from dateutil.relativedelta import relativedelta

from odoo import fields
from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestEstablishment(TransactionCase):
    """Phase F : après l'intégration, deux contrôles (3 et 6 mois) font le
    « Fidèle affermi(e) » ; un défavorable se rattrape, deux de suite proposent
    de rouvrir un suivi."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['equipment.church'].create({'name': 'Église', 'integration_min_attendance': 0})
        cls.ev = cls.env['church.evangelist'].create({'name': 'Ev', 'church_id': cls.church.id})
        cls.cell = cls.env['church.prayer.cell'].create({'name': 'Cellule', 'church_id': cls.church.id})
        cls.group = cls.env['church.age.group'].create({
            'name': 'G', 'church_id': cls.church.id, 'group_type': 'youth', 'gender': 'mixed'})
        cls.leader = cls.env['church.mobile.user'].create({
            'name': 'Chef', 'phone': '+225 07 00 00 08', 'role': 'cell_leader',
            'church_id': cls.church.id, 'prayer_cell_id': cls.cell.id})
        cls.manager = cls.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 00 09', 'role': 'manager', 'church_id': cls.church.id})

    def _integrated(self, name='Intégrée', cell=True):
        member = self.env['church.member'].create({
            'name': name, 'first_name': 'P', 'gender': 'female', 'church_id': self.church.id})
        followup = self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id, 'member_id': member.id,
            'target_cell_id': self.cell.id if cell else False, 'target_age_group_id': self.group.id})
        if not cell:
            followup.target_cell_id = self.env['church.prayer.cell'].create({
                'name': 'Sans responsable', 'church_id': self.church.id})
        followup.action_integrate()
        return member

    def _checkpoint(self, member, milestone):
        return member.checkpoint_ids.filtered(lambda c: c.milestone == milestone and c.state == 'planned')

    def test_integration_plans_two_checkpoints(self):
        member = self._integrated()
        today = fields.Date.context_today(self.church)
        self.assertEqual(sorted(member.checkpoint_ids.mapped('due_date')),
                         [today + relativedelta(months=3), today + relativedelta(months=6)])

    def test_two_favorable_checkpoints_make_an_established_member(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('favorable')
        self.assertEqual(member.member_type, 'integrated')
        self._checkpoint(member, '6m').action_record('favorable')
        self.assertEqual(member.member_type, 'established')
        self.assertEqual(member.established_date, fields.Date.context_today(self.church))

    def test_unfavorable_plans_a_catchup_one_month_later(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('unfavorable', notes='Absente depuis 5 semaines')
        catchup = self._checkpoint(member, '3m')
        self.assertTrue(catchup.is_catchup)
        self.assertEqual(catchup.due_date, fields.Date.context_today(self.church) + relativedelta(months=1))
        self.assertFalse(member.reopen_suggested, "Un seul défavorable : on rattrape d'abord")

    def test_two_unfavorable_in_a_row_suggest_reopening(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('unfavorable')
        self._checkpoint(member, '3m').action_record('unfavorable')
        self.assertTrue(member.reopen_suggested)
        items = self.manager._todo_items()
        self.assertIn(member.id, [i['member_id'] for i in items if i['kind'] == 'reopen_suggested'])

    def test_favorable_catchup_clears_the_suggestion_and_counts(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('unfavorable')
        self._checkpoint(member, '3m').action_record('unfavorable')
        self._checkpoint(member, '3m').action_record('favorable')
        self.assertFalse(member.reopen_suggested)
        self._checkpoint(member, '6m').action_record('favorable')
        self.assertEqual(member.member_type, 'established')

    def test_reopening_a_followup_cancels_pending_checkpoints(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('unfavorable')
        self._checkpoint(member, '3m').action_record('unfavorable')
        self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id, 'member_id': member.id})
        self.assertFalse(member.checkpoint_ids.filtered(lambda c: c.state == 'planned'))
        self.assertFalse(member.reopen_suggested)
        self.assertEqual(member.member_type, 'in_followup')

    def test_a_checkpoint_is_recorded_once(self):
        checkpoint = self._checkpoint(self._integrated(), '3m')
        checkpoint.action_record('favorable')
        with self.assertRaises(UserError):
            checkpoint.action_record('unfavorable')

    def test_cell_leader_does_due_checkpoints_of_his_cell(self):
        member = self._integrated()
        later = fields.Date.context_today(self.church) + relativedelta(months=3)
        items = self.leader._todo_items(later)
        self.assertEqual([i['member_id'] for i in items if i['kind'] == 'checkpoint_due'], [member.id])
        self.assertNotIn('checkpoint_due', [i['kind'] for i in self.leader._todo_items(fields.Date.context_today(self.church))],
                         "Pas avant l'échéance")
        self.assertNotIn('checkpoint_due', [i['kind'] for i in self.manager._todo_items(later)],
                         "Le responsable n'intervient qu'à défaut de responsable de cellule")

    def test_manager_does_checkpoints_when_the_cell_has_no_leader(self):
        member = self._integrated(cell=False)
        later = fields.Date.context_today(self.church) + relativedelta(months=3)
        self.assertIn(member.id, [i['member_id'] for i in self.manager._todo_items(later)
                                  if i['kind'] == 'checkpoint_due'])
        self.assertIn('contrôle(s) à faire', self.manager._todo_summary(self.manager._todo_items(later)))

    def test_corrected_integration_date_replans_pending_checkpoints(self):
        member = self._integrated()
        self._checkpoint(member, '3m').action_record('unfavorable')  # crée un rattrapage
        catchup = self._checkpoint(member, '3m')
        catchup_due = catchup.due_date
        member.integration_date = date(2026, 1, 10)
        self.assertEqual(self._checkpoint(member, '6m').due_date, date(2026, 7, 10))
        self.assertEqual(catchup.due_date, catchup_due, "Le rattrapage garde son échéance")
