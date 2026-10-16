from datetime import date

from dateutil.relativedelta import relativedelta
from psycopg2 import IntegrityError

from odoo.exceptions import ValidationError
from odoo import fields
from odoo.tests.common import TransactionCase, tagged
from odoo.tools import mute_logger


@tagged('post_install', '-at_install')
class TestChurchIntegrity(TransactionCase):
    """Phase 1 : unicité réelle en base, cloisonnement par église, suivi prolongé
    toujours actif, âge à jour, fin de période signalée une seule fois."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['equipment.church'].create({'name': 'Église A', 'code': 'A'})
        cls.other = cls.env['equipment.church'].create({'name': 'Église B', 'code': 'B'})
        cls.member = cls._member(cls.church, 'Kouassi')
        cls.stranger = cls._member(cls.other, 'Yao')
        cls.evangelist = cls.env['church.evangelist'].create({
            'name': 'Ev A', 'church_id': cls.church.id,
        })

    @classmethod
    def _member(cls, church, name, **vals):
        return cls.env['church.member'].create({
            'name': name, 'first_name': 'Test', 'gender': 'male',
            'church_id': church.id, **vals,
        })

    def _followup(self, member=None, **vals):
        return self.env['church.followup'].create({
            'church_id': self.church.id,
            'evangelist_id': self.evangelist.id,
            'member_id': (member or self.member).id,
            **vals,
        })

    # ── Unicité en base ────────────────────────────────────────────────

    def _assert_unique(self, model, vals):
        self.env[model].create(vals)
        with mute_logger('odoo.sql_db'), self.assertRaises(IntegrityError), self.cr.savepoint():
            self.env[model].create(vals)

    def test_unique_constraints_exist_in_database(self):
        expected = {
            ('church_mobile_user', 'church_mobile_user_phone_church_uniq'),
            ('church_followup_week', 'church_followup_week_followup_week_uniq'),
            ('church_attendance_sunday', 'church_attendance_sunday_member_date_uniq'),
            ('church_attendance_cell', 'church_attendance_cell_member_cell_date_uniq'),
            ('church_cooking_rotation', 'church_cooking_rotation_church_date_uniq'),
        }
        self.env.cr.execute("""
            SELECT conrelid::regclass::text, conname FROM pg_constraint
             WHERE contype = 'u' AND (conrelid::regclass::text, conname) IN %s
        """, [tuple(expected)])
        self.assertEqual(set(self.env.cr.fetchall()), expected)

    # ── Église de l'annuaire partagé ───────────────────────────────────

    def test_deleting_a_church_never_erases_its_followup(self):
        with mute_logger('odoo.sql_db'), self.assertRaises(IntegrityError), self.cr.savepoint():
            self.church.unlink()
            self.env.flush_all()

    def test_church_enters_followup_with_its_first_member(self):
        fresh = self.env['equipment.church'].create({'name': 'Église Neuve'})
        self.assertFalse(fresh.followup_enabled)
        self._member(fresh, 'Premier')
        self.assertTrue(fresh.followup_enabled)

    def test_merging_duplicate_churches_keeps_one_account_per_number(self):
        Account = self.env['church.mobile.user']
        kept = Account.create({'name': 'Resp', 'phone': '+225 07 00 00 41', 'role': 'manager',
                               'church_id': self.church.id})
        twin = Account.create({'name': 'Resp bis', 'phone': '+22507000041', 'role': 'manager',
                               'church_id': self.other.id})
        alone = Account.create({'name': 'Autre', 'phone': '+225 07 00 00 42', 'role': 'evangelist',
                                'church_id': self.other.id})
        journal = self.other._merge_absorb_into(self.church)
        self.assertFalse(twin.exists(), "Le compte en double de l'église absorbée est retiré")
        self.assertEqual(kept.church_id, self.church)
        self.assertEqual(alone.church_id, self.church, "Les autres comptes suivent l'église conservée")
        self.assertEqual(self.stranger.church_id, self.church, "Les membres aussi")
        self.assertTrue(any('compte' in line for line in journal))

    def test_sunday_attendance_unique(self):
        self._assert_unique('church.attendance.sunday', {
            'church_id': self.church.id, 'member_id': self.member.id, 'date': '2026-10-11',
        })

    def test_week_report_unique(self):
        followup = self._followup()
        self._assert_unique('church.followup.week', {'followup_id': followup.id, 'week_number': 1})

    # ── Cloisonnement par église ───────────────────────────────────────

    def test_followup_rejects_member_of_other_church(self):
        with self.assertRaises(ValidationError):
            self._followup(member=self.stranger)

    def test_member_rejects_mentor_of_other_church(self):
        with self.assertRaises(ValidationError):
            self._member(self.church, 'Intrus', mentor_id=self.stranger.id)

    def test_attendance_rejects_member_of_other_church(self):
        with self.assertRaises(ValidationError):
            self.env['church.attendance.sunday'].create({
                'church_id': self.church.id, 'member_id': self.stranger.id,
            })

    def test_cell_rejects_district_of_other_church(self):
        district = self.env['church.district'].create({'name': 'Q', 'church_id': self.other.id})
        with self.assertRaises(ValidationError):
            self.env['church.prayer.cell'].create({
                'name': 'C', 'church_id': self.church.id, 'district_ids': [(4, district.id)],
            })

    # ── Un seul suivi actif ────────────────────────────────────────────

    def test_batch_create_cannot_open_two_active_followups(self):
        vals = {'church_id': self.church.id, 'evangelist_id': self.evangelist.id,
                'member_id': self.member.id}
        with self.assertRaises(ValidationError):
            self.env['church.followup'].create([vals, vals])

    def test_extended_followup_blocks_a_new_one(self):
        self._followup().action_extend()
        with self.assertRaises(ValidationError):
            self._followup()

    def test_transfer_keeps_a_single_active_followup(self):
        other_ev = self.env['church.evangelist'].create({'name': 'Ev 2', 'church_id': self.church.id})
        followup = self._followup()
        followup.transferred_to_id = other_ev
        followup.action_transfer()
        active = self.env['church.followup'].search([
            ('member_id', '=', self.member.id), ('state', 'in', ('in_progress', 'extended')),
        ])
        self.assertEqual(active.evangelist_id, other_ev)

    def test_duration_must_be_positive(self):
        # 0 = « pas de durée choisie » : la durée proposée s'applique.
        self.assertEqual(self._followup(duration_weeks=0).duration_weeks, 4)
        with self.assertRaises(ValidationError):
            self._followup(member=self._member(self.church, 'Négatif'), duration_weeks=-1)

    # ── Prolongé = actif ───────────────────────────────────────────────

    def test_extended_followup_counts_as_active(self):
        self._followup().action_extend()
        self.assertEqual(self.evangelist.active_followup_count, 1)
        self.assertEqual(self.church.followup_active_count, 1)

    # ── Fin de période signalée une fois ───────────────────────────────

    def test_end_notice_posted_once_and_again_after_extension(self):
        followup = self._followup(start_date=fields.Date.context_today(self.env.user) - relativedelta(weeks=5))
        Followup = self.env['church.followup']
        before = len(followup.message_ids)
        Followup._cron_check_followup_end()
        Followup._cron_check_followup_end()
        self.assertEqual(len(followup.message_ids) - before, 1)

        followup.write({'start_date': fields.Date.context_today(self.env.user) - relativedelta(weeks=9)})
        followup.action_extend()  # 4 + 4 = 8 semaines, toujours échu
        before = len(followup.message_ids)
        Followup._cron_check_followup_end()
        notices = followup.message_ids[:len(followup.message_ids) - before]
        self.assertEqual(len(notices.filtered(lambda m: 'terminée' in (m.body or ''))), 1)

    # ── Âge à jour ─────────────────────────────────────────────────────

    def test_cron_refreshes_stale_age(self):
        member = self._member(self.church, 'Âge', date_of_birth=date.today() - relativedelta(years=30))
        self.assertEqual(member.age, 30)
        # Simule une valeur stockée un an plus tôt (l'anniversaire est passé depuis)
        self.env.cr.execute("UPDATE church_member SET age = 29 WHERE id = %s", [member.id])
        member.invalidate_recordset(['age'])
        self.env['church.member']._cron_refresh_age()
        member.invalidate_recordset(['age'])
        self.assertEqual(member.age, 30)
