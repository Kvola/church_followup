from datetime import date

from dateutil.relativedelta import relativedelta

from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestTodo(TransactionCase):
    """Phase D : la liste « À faire » de l'évangéliste et du responsable."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['equipment.church'].create({'name': 'Église'})
        cls.ev = cls.env['church.evangelist'].create({
            'name': 'Ev', 'phone': '+225 07 00 00 01', 'church_id': cls.church.id})
        cls.ev_account = cls.ev.mobile_user_id
        cls.manager = cls.env['church.mobile.user'].create({
            'name': 'Resp', 'phone': '+225 07 00 00 09', 'role': 'manager', 'church_id': cls.church.id})
        cls.today = date(2026, 10, 15)  # un jeudi

    def _member(self, name):
        return self.env['church.member'].create({
            'name': name, 'first_name': 'P', 'gender': 'male', 'church_id': self.church.id})

    def _followup(self, start, weeks=4):
        return self.env['church.followup'].create({
            'church_id': self.church.id, 'evangelist_id': self.ev.id,
            'member_id': self._member('Suivi %s' % start).id, 'start_date': start, 'duration_weeks': weeks})

    def test_report_overdue_only_after_grace_period(self):
        # Semaine 1 : du 1er au 7 octobre ; en retard à partir du 11 (7 + 3 jours).
        f = self._followup(date(2026, 10, 1))
        self.assertEqual(f._overdue_report_weeks(date(2026, 10, 10)), [])
        self.assertEqual(f._overdue_report_weeks(date(2026, 10, 11)), [1])
        self.env['church.followup.week'].create({'followup_id': f.id, 'week_number': 1})
        self.assertEqual(f._overdue_report_weeks(date(2026, 10, 11)), [])

    def test_evangelist_todo_lists_decisions_and_late_reports(self):
        due = self._followup(self.today - relativedelta(weeks=4))
        self._followup(self.today - relativedelta(days=20))
        items = self.ev_account._todo_items(self.today)
        kinds = [i['kind'] for i in items]
        self.assertEqual(kinds[0], 'decision_due', "Le plus urgent d'abord")
        self.assertEqual(items[0]['followup_id'], due.id)
        self.assertIn('report_overdue', kinds)
        self.assertNotIn('to_assign', kinds, "Attribuer est l'affaire du responsable")

    def test_closed_followups_ask_nothing(self):
        f = self._followup(self.today - relativedelta(weeks=4))
        f.action_abandon(reason='unreachable')
        self.assertEqual(self.ev_account._todo_items(self.today), [])

    def test_manager_todo_lists_people_to_assign_and_late_evangelists(self):
        waiting = self._member('Attend')
        self._followup(self.today - relativedelta(days=20))
        items = self.manager._todo_items(self.today)
        kinds = {i['kind'] for i in items}
        self.assertIn('to_assign', kinds)
        self.assertIn(waiting.id, [i.get('member_id') for i in items if i['kind'] == 'to_assign'])
        late = [i for i in items if i['kind'] == 'evangelist_late']
        self.assertEqual(late[0]['evangelist_id'], self.ev.id)

    def test_summary_is_one_line(self):
        self._followup(self.today - relativedelta(weeks=4))
        summary = self.ev_account._todo_summary(self.ev_account._todo_items(self.today))
        self.assertIn('1\u00a0décision(s) à prendre', summary)
        self.assertNotIn('\n', summary)

    def test_cell_leader_without_followups_has_no_followup_tasks(self):
        cell = self.env['church.prayer.cell'].create({'name': 'C', 'church_id': self.church.id})
        leader = self.env['church.mobile.user'].create({
            'name': 'L', 'phone': '+225 07 00 00 07', 'role': 'cell_leader',
            'church_id': self.church.id, 'prayer_cell_id': cell.id})
        self.assertEqual(leader._todo_items(self.today), [])
