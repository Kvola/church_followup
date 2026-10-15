from odoo.exceptions import ValidationError
from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestFollowupDuration(TransactionCase):
    """Phase B : la durée d'un suivi suit une chaîne claire — choix de
    l'évangéliste, sinon durée prévue pour la personne (événement ou
    responsable), sinon réglage de l'église."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['church.church'].create({'name': 'Église', 'default_followup_weeks': 6})
        cls.ev = cls.env['church.evangelist'].create({'name': 'Ev', 'church_id': cls.church.id})
        cls.ev2 = cls.env['church.evangelist'].create({'name': 'Ev2', 'church_id': cls.church.id})

    def _member(self, **vals):
        return self.env['church.member'].create({
            'name': 'N', 'first_name': 'P', 'gender': 'male', 'church_id': self.church.id, **vals})

    def _followup(self, member, **vals):
        return self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id, 'member_id': member.id, **vals})

    def test_church_default_applies_when_nothing_else(self):
        member = self._member()
        self.assertEqual((member.proposed_followup_weeks, member.proposed_followup_origin), (6, 'church'))
        f = self._followup(member)
        self.assertEqual((f.duration_weeks, f.duration_origin), (6, 'church'))

    def test_planned_duration_wins_over_church(self):
        member = self._member(planned_followup_weeks=10, planned_followup_origin='event')
        f = self._followup(member)
        self.assertEqual((f.duration_weeks, f.duration_origin), (10, 'event'))

    def test_evangelist_choice_wins_and_is_recorded(self):
        member = self._member(planned_followup_weeks=10, planned_followup_origin='event')
        f = self._followup(member, duration_weeks=3)
        self.assertEqual((f.duration_weeks, f.duration_origin), (3, 'manual'))

    def test_manual_edit_of_planned_duration_is_labelled_manual(self):
        member = self._member(planned_followup_weeks=10, planned_followup_origin='event')
        member.planned_followup_weeks = 8
        self.assertEqual(member.planned_followup_origin, 'manual')
        member.planned_followup_weeks = 0
        self.assertEqual(member.proposed_followup_origin, 'church')

    def test_bounds(self):
        with self.assertRaises(ValidationError):
            self.church.default_followup_weeks = 0
        with self.assertRaises(ValidationError):
            self._member(planned_followup_weeks=27)
        with self.assertRaises(ValidationError):
            self._followup(self._member(), duration_weeks=27)

    def test_extension_uses_chosen_weeks_then_church_default(self):
        f = self._followup(self._member(), duration_weeks=4)
        f.action_extend(weeks=2)
        self.assertEqual((f.duration_weeks, f.state), (6, 'extended'))
        f.action_extend()
        self.assertEqual(f.duration_weeks, 12)
        with self.assertRaises(ValidationError):
            f.action_extend(weeks=27)

    def test_total_duration_capped_at_one_year(self):
        f = self._followup(self._member(), duration_weeks=26)
        f.action_extend(weeks=26)
        with self.assertRaises(ValidationError):
            f.action_extend(weeks=1)

    def test_transfer_keeps_duration_and_origin(self):
        f = self._followup(self._member(planned_followup_weeks=10, planned_followup_origin='event'))
        f.action_extend(weeks=20)  # 30 semaines : au-delà d'un départ normal
        f.transferred_to_id = self.ev2
        f.action_transfer()
        new = self.env['church.followup'].search([('evangelist_id', '=', self.ev2.id)])
        self.assertEqual((new.duration_weeks, new.duration_origin), (30, 'event'))

    def test_assign_wizard_batch_keeps_each_proposal(self):
        a = self._member(planned_followup_weeks=10, planned_followup_origin='event')
        b = self._member()
        wizard = self.env['church.followup.assign'].with_context(default_member_ids=(a | b).ids).create({
            'evangelist_id': self.ev.id})
        self.assertFalse(wizard.duration_weeks, "En lot, pas de durée unique imposée")
        wizard.action_confirm()
        weeks = {f.member_id: f.duration_weeks for f in (a | b).mapped(
            lambda m: self.env['church.followup'].search([('member_id', '=', m.id)]))}
        self.assertEqual(weeks, {a: 10, b: 6})
        self.assertEqual(set((a | b).mapped('member_type')), {'in_followup'})

    def test_assign_wizard_single_prefills_and_allows_override(self):
        member = self._member(planned_followup_weeks=10, planned_followup_origin='event')
        wizard = self.env['church.followup.assign'].with_context(default_member_ids=member.ids).create({
            'evangelist_id': self.ev.id})
        self.assertEqual(wizard.duration_weeks, 10)
        wizard.duration_weeks = 5
        wizard.action_confirm()
        f = self.env['church.followup'].search([('member_id', '=', member.id)])
        self.assertEqual((f.duration_weeks, f.duration_origin), (5, 'manual'))
