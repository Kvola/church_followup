from odoo.tests.common import TransactionCase, tagged


@tagged('post_install', '-at_install')
class TestChurchPartnerLink(TransactionCase):
    """La personne évangélisée est adossée au contact `res.partner` commun."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, tracking_disable=True))
        cls.church = cls.env['church.church'].create({'name': 'Église Test'})

    def test_church_member_links_partner(self):
        m = self.env['church.member'].create({
            'name': 'Konan', 'first_name': 'Yao', 'gender': 'male',
            'church_id': self.church.id, 'email': 'konan.yao@test.com',
        })
        self.assertTrue(m.partner_id, "Un contact doit être créé et lié")
        self.assertEqual(m.partner_id.church_member_count, 1)
        self.assertIn(m, m.partner_id.church_member_ids)

    def test_reuses_existing_partner_by_email(self):
        existing = self.env['res.partner'].create({
            'name': 'Déjà Là', 'email': 'reuse.church@test.com',
        })
        m = self.env['church.member'].create({
            'name': 'Aka', 'first_name': 'Marie', 'gender': 'female',
            'church_id': self.church.id, 'email': 'reuse.church@test.com',
        })
        self.assertEqual(m.partner_id, existing)

    def test_reuses_existing_partner_by_phone(self):
        existing = self.env['res.partner'].create({
            'name': 'Tel Connu', 'phone': '+2250700000040',
        })
        m = self.env['church.member'].create({
            'name': 'Bla', 'first_name': 'Jean', 'gender': 'male',
            'church_id': self.church.id, 'phone': '+2250700000040',
        })
        self.assertEqual(m.partner_id, existing)
