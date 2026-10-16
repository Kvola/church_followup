"""Le guide utilisateur se dégrade en silence : ces tests le gardent.

Un gabarit renommé, et la page répond « momentanément indisponible » ; une
capture supprimée, et il reste un cadre vide. Rien ne lève d'erreur.

`HttpCase`, pas `TransactionCase` : un rendu PDF réel depuis une transaction
ouverte fige la suite (wkhtmltopdf rappelle le serveur, qui attend la
transaction).
"""
import os
import re

from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestUserGuide(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.app = cls.env.ref('church_followup.mobile_app_suivi_evangelisation')

    def test_the_app_points_to_an_existing_guide(self):
        # Des chaînes : seule une résolution prouve qu'elles visent quelque chose.
        self.assertTrue(self.env.ref(self.app.guide_template_xmlid, raise_if_not_found=False))
        self.assertTrue(self.env.ref(self.app.guide_report_xmlid, raise_if_not_found=False))
        self.assertEqual(self.app.guide_link, '/apps/suivi-evangelisation/guide')

    def test_guide_is_readable_without_an_account_and_speaks_like_the_screens(self):
        response = self.url_open('/apps/suivi-evangelisation/guide')
        self.assertEqual(response.status_code, 200)
        body = response.text
        # Les mots du guide sont ceux de l'écran.
        for label in ('Recevoir un code', 'Renvoyer le code', "Changer d'église", 'À attribuer',
                      'Présence au culte', 'Appel effectué', 'Visite effectuée', 'Oui, elle tient',
                      'Elle ne vient plus', 'Jamais connecté', 'Fermer les sessions', 'Inviter',
                      'A déménagé', 'Fidèle affermi(e)', 'Rapport de semaine', 'Envoyer un code de connexion'):
            self.assertIn(label, body, "Le guide ne cite pas « %s »" % label)
        self.assertNotIn('PIN', body, "Il n'y a plus de PIN : le guide ne doit pas en parler")

    def test_every_screenshot_of_the_guide_exists(self):
        source = self.env.ref('church_followup.user_guide_content').arch
        paths = re.findall(r'''t-set="chemin"\s+t-value="'([^']+)'"''', source)
        paths += re.findall(r"help_image\('([^']+)'\)", source)
        self.assertGreater(len(paths), 10)
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        for path in paths:
            self.assertTrue(path.startswith('church_followup/'), path)
            self.assertTrue(os.path.exists(os.path.join(root, path.split('/', 1)[1])),
                            "Capture absente : %s (relancer scripts/sync_training_shots.sh)" % path)

    def test_the_printed_guide_embeds_its_screenshots(self):
        # Sans force_report_rendering, --test-enable ne produit aucun PDF et le
        # test serait vert sans rien vérifier.
        pdf, _type = self.env.ref('church_followup.action_report_user_guide').with_context(
            force_report_rendering=True)._render_qweb_pdf(
            'church_followup.action_report_user_guide', res_ids=self.app.ids)
        self.assertTrue(pdf.startswith(b'%PDF'))
        images = pdf.count(b'/Subtype /Image') + pdf.count(b'/Subtype/Image')
        self.assertGreater(images, 10, "Le PDF doit porter ses captures, pas les chercher")
