from datetime import date

from odoo.exceptions import UserError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestInterruption(TransactionCase):
    """Phase E : interrompre exige un motif, la personne garde un statut à part,
    son suivi peut reprendre et tout son parcours reste lisible."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['church.church'].create({'name': 'Église'})
        cls.ev = cls.env['church.evangelist'].create({'name': 'Ev', 'church_id': cls.church.id})
        cls.ev2 = cls.env['church.evangelist'].create({'name': 'Ev2', 'church_id': cls.church.id})
        cls.member = cls.env['church.member'].create({
            'name': 'N', 'first_name': 'P', 'gender': 'male', 'church_id': cls.church.id})

    def _followup(self, evangelist=None):
        return self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': (evangelist or self.ev).id,
            'member_id': self.member.id, 'start_date': date(2026, 9, 1)})

    def test_reason_is_required(self):
        f = self._followup()
        with self.assertRaises(UserError):
            f.action_abandon()
        with self.assertRaises(UserError):
            f.action_abandon(reason='other')  # « Autre » sans précision
        self.assertEqual(f.state, 'in_progress')

    def test_interruption_keeps_a_distinct_status_and_its_reason(self):
        f = self._followup()
        f.action_abandon(reason='moved', note='Parti à Bouaké')
        self.assertEqual(self.member.member_type, 'interrupted', "Plus confondu avec une nouvelle personne")
        self.assertEqual((f.state, f.abandon_reason, f.abandon_note), ('abandoned', 'moved', 'Parti à Bouaké'))
        self.assertTrue(f.abandon_date)

    def test_interrupted_person_is_not_in_the_to_assign_list(self):
        self._followup().action_abandon(reason='unreachable')
        new_people = self.env['church.member'].search([('member_type', '=', 'new'),
                                                       ('church_id', '=', self.church.id)])
        self.assertNotIn(self.member, new_people)

    def test_resume_links_to_the_interrupted_followup(self):
        first = self._followup()
        first.action_abandon(reason='unreachable')
        wizard = self.env['church.followup.assign'].with_context(
            default_member_ids=self.member.ids).create({'evangelist_id': self.ev2.id})
        wizard.action_confirm()
        second = self.member.last_followup_id
        self.assertNotEqual(second, first)
        self.assertEqual(second.previous_followup_id, first)
        self.assertEqual(self.member.member_type, 'in_followup')
        self.assertEqual(self.member.followup_ids, first | second, "Le parcours garde les deux suivis")

    def test_abandon_wizard(self):
        f = self._followup()
        self.env['church.followup.abandon'].create({
            'followup_id': f.id, 'reason': 'other_church'}).action_confirm()
        self.assertEqual(f.abandon_reason, 'other_church')

    def test_integration_rate_still_counts_interruptions(self):
        self._followup().action_abandon(reason='not_interested')
        self.assertEqual(self.ev.integration_rate, 0.0)
        self.assertEqual(self.ev.active_followup_count, 0)
