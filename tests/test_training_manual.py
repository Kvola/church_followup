"""Le manuel de formation : ses modules complets, ses captures, ses corrigés.

Un module sans « Vous devez voir » laisse le participant sans repère ; une
question sans corrigé laisse le formateur sans réponse. Rien ne le signale à
l'écran : ces tests si.
"""
import os
import re

from lxml import html

from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestTrainingManual(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.app = cls.env.ref('church_followup.mobile_app_suivi_evangelisation')
        cls.source = cls.env.ref('church_followup.training_manual_content').arch

    def test_the_page_is_public(self):
        response = self.url_open('/apps/suivi-evangelisation/formation')
        self.assertEqual(response.status_code, 200)
        self.assertIn('Manuel de formation', response.text)
        self.assertIn('Télécharger le manuel en PDF', response.text)
        self.assertNotIn('PIN', response.text)

    def test_every_module_has_its_five_parts(self):
        tree = html.fromstring(self.source)
        modules = tree.xpath('//div[@class="module"]')
        self.assertEqual(len(modules), 7)
        for module in modules:
            title = module.xpath('h2')[0].text_content()
            text = module.text_content()
            for part in ('Objectifs', 'Démonstration', 'Vous devez voir', 'Contrôle', 'Note du formateur'):
                self.assertIn(part, text, "%s : il manque « %s »" % (title, part))

    def test_there_is_one_answer_per_question(self):
        tree = html.fromstring(self.source)
        questions = [len(ol.xpath('li')) for ol in tree.xpath('//ol[@class="questions"]')]
        answers = [len(ol.xpath('li')) for ol in tree.xpath('//ol[@class="reponses"]')]
        self.assertEqual(questions, answers, "Chaque module a autant de corrigés que de questions")

    def test_every_screenshot_exists(self):
        paths = re.findall(r'''t-set="chemin"\s+t-value="'([^']+)'"''', self.source)
        paths += re.findall(r"help_image\('([^']+)'\)", self.source)
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.assertGreater(len(paths), 8)
        for path in paths:
            self.assertTrue(os.path.exists(os.path.join(root, path.split('/', 1)[1])), path)

    def test_the_pdf_embeds_its_screenshots(self):
        pdf, _type = self.env.ref('church_followup.action_report_training_manual').with_context(
            force_report_rendering=True)._render_qweb_pdf(
            'church_followup.action_report_training_manual', res_ids=self.app.ids)
        self.assertTrue(pdf.startswith(b'%PDF'))
        self.assertGreater(pdf.count(b'/Subtype /Image') + pdf.count(b'/Subtype/Image'), 8)
