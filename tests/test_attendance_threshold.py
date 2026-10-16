from datetime import date

from dateutil.relativedelta import relativedelta

from odoo.exceptions import UserError
from odoo import fields
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestAttendanceThreshold(TransactionCase):
    """Phase C : le pointage du culte alimente les rapports, et l'intégration
    sous le seuil de présence exige une justification écrite."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['church.church'].create({'name': 'Église', 'integration_min_attendance': 75})
        cls.ev = cls.env['church.evangelist'].create({'name': 'Ev', 'church_id': cls.church.id})
        cls.cell = cls.env['church.prayer.cell'].create({'name': 'C', 'church_id': cls.church.id})
        cls.group = cls.env['church.age.group'].create({
            'name': 'G', 'church_id': cls.church.id, 'group_type': 'youth', 'gender': 'mixed'})
        cls.member = cls.env['church.member'].create({
            'name': 'N', 'first_name': 'P', 'gender': 'male', 'church_id': cls.church.id})
        # Suivi de 4 semaines commencé il y a 4 semaines : tout est écoulé.
        cls.start = fields.Date.context_today(cls.env.user) - relativedelta(weeks=4)
        cls.followup = cls.env['church.followup'].create({
            'church_id': cls.church.id, 'evangelist_id': cls.ev.id, 'member_id': cls.member.id,
            'start_date': cls.start, 'duration_weeks': 4,
            'target_cell_id': cls.cell.id, 'target_age_group_id': cls.group.id,
        })

    def _attend(self, week_number):
        return self.env['church.attendance.sunday'].create({
            'church_id': self.church.id, 'member_id': self.member.id,
            'date': self.start + relativedelta(weeks=week_number - 1, days=2),
        })

    def _report(self, week_number, **vals):
        return self.env['church.followup.week'].create({
            'followup_id': self.followup.id, 'week_number': week_number, **vals})

    # ─── Pointage → rapport ───────────────────────────────────────────

    def test_report_written_after_roll_call_is_ticked(self):
        self._attend(1)
        week = self._report(1, sunday_attendance=False)
        self.assertTrue(week.roll_call_present)
        self.assertTrue(week.sunday_attendance, "Le pointage fait foi")
        self.assertEqual(week.score, 3)

    def test_roll_call_after_report_ticks_it(self):
        week = self._report(2)
        self.assertFalse(week.sunday_attendance)
        self._attend(2)
        self.assertTrue(week.sunday_attendance)

    def test_evangelist_cannot_untick_a_roll_call(self):
        self._attend(1)
        week = self._report(1)
        week.sunday_attendance = False
        self.assertTrue(week.sunday_attendance)

    def test_roll_call_outside_the_followup_is_ignored(self):
        self.env['church.attendance.sunday'].create({
            'church_id': self.church.id, 'member_id': self.member.id,
            'date': self.start - relativedelta(days=3)})
        self.assertFalse(self._report(1).sunday_attendance)

    def test_roll_call_counts_even_without_a_report(self):
        for n in (1, 2, 3):
            self._attend(n)
        self.assertEqual((self.followup.attendance_weeks, self.followup.elapsed_weeks), (3, 4))
        self.assertEqual(self.followup.attendance_rate, 75)
        self.assertFalse(self.followup.below_threshold)

    # ─── Seuil d'intégration ──────────────────────────────────────────

    def test_integration_below_threshold_requires_justification(self):
        self._attend(1)
        self._report(2, sunday_attendance=True)  # 2 semaines sur 4 = 50 %
        self.assertTrue(self.followup.below_threshold)
        with self.assertRaises(UserError) as err:
            self.followup.action_integrate()
        self.assertIn('2 semaine(s) sur 4', str(err.exception))
        self.assertEqual(self.followup.state, 'in_progress')

        self.followup.integration_justification = 'Vient au culte du soir, non pointé.'
        self.followup.action_integrate()
        self.assertEqual(self.followup.state, 'integrated')
        self.assertTrue(self.followup.message_ids.filtered(lambda m: 'non pointé' in (m.body or '')))

    def test_integration_above_threshold_needs_nothing(self):
        for n in (1, 2, 3, 4):
            self._attend(n)
        self.followup.action_integrate()
        self.assertEqual(self.member.member_type, 'integrated')

    def test_threshold_zero_disables_the_check(self):
        self.church.integration_min_attendance = 0
        self.assertFalse(self.followup.below_threshold)
        self.followup.action_integrate()
        self.assertEqual(self.followup.state, 'integrated')

    def test_rate_uses_elapsed_weeks_only(self):
        young = self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id,
            'member_id': self.env['church.member'].create({
                'name': 'J', 'first_name': 'J', 'gender': 'female', 'church_id': self.church.id}).id,
            'start_date': fields.Date.context_today(self.env.user), 'duration_weeks': 8,
        })
        self.env['church.attendance.sunday'].create({
            'church_id': self.church.id, 'member_id': young.member_id.id, 'date': fields.Date.context_today(self.env.user)})
        self.assertEqual((young.elapsed_weeks, young.attendance_rate), (1, 100))
