"""La version navigateur, servie par Odoo sur /suivi-evangelisation.

Chacune de ces vérifications casse la PWA EN SILENCE quand elle est fausse :
une page blanche, sans la moindre erreur visible.
"""
import json

from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestSuiviPwa(HttpCase):

    def test_the_app_is_served_at_its_address(self):
        page = self.url_open('/suivi-evangelisation')
        self.assertEqual(page.status_code, 200)
        self.assertIn('<title>Suivi Évangélisation</title>', page.text)

    def test_the_bundle_knows_where_it_lives(self):
        self.assertIn('<base href="/suivi-evangelisation/"', self.url_open('/suivi-evangelisation/').text)

    def test_an_inner_route_falls_back_on_the_app(self):
        page = self.url_open('/suivi-evangelisation/suivis/12')
        self.assertEqual(page.status_code, 200)
        self.assertIn('<base href="/suivi-evangelisation/"', page.text)

    def test_the_content_policy_lets_the_app_load(self):
        policy = self.url_open('/suivi-evangelisation').headers.get('Content-Security-Policy', '')
        self.assertIn("'wasm-unsafe-eval'", policy)
        self.assertIn('fcm.googleapis.com', policy, "Sans elle, l'abonnement aux notifications échoue en silence")
        self.assertNotIn("default-src 'none'", policy)

    def test_the_installed_app_carries_its_identity_and_scope(self):
        manifest = json.loads(self.url_open('/suivi-evangelisation/manifest.json').text)
        self.assertEqual(manifest['short_name'], 'Suivi Évangélisation')
        self.assertEqual(manifest['scope'], '/suivi-evangelisation/')
        self.assertEqual(manifest['start_url'], '/suivi-evangelisation/')
        icon = self.url_open('/suivi-evangelisation/icons/Icon-192.png')
        self.assertEqual(icon.status_code, 200)

    def test_the_bundle_calls_no_hard_coded_server(self):
        script = self.url_open('/suivi-evangelisation/main.dart.js')
        self.assertEqual(script.status_code, 200)
        for host in ('localhost:8069', 'iyf.ebng.world'):
            self.assertNotIn(host, script.text, "Sur le web, les adresses restent relatives")

    def test_the_catalogue_offers_the_browser_version(self):
        app = self.env.ref('church_followup.mobile_app_suivi_evangelisation')
        self.assertEqual(app.pwa_url, '/suivi-evangelisation')
        page = self.url_open('/apps/suivi-evangelisation')
        self.assertIn('/suivi-evangelisation', page.text)

    def test_the_service_worker_template_never_ships(self):
        """Le gabarit porte des marqueurs (__FCM_…) : servi tel quel, il ferait
        s'abonner les navigateurs à une app Firebase inexistante."""
        page = self.url_open('/suivi-evangelisation/firebase-messaging-sw.template.js')
        self.assertNotIn('__FCM_', page.text)

    def test_the_page_carries_its_install_and_push_relays(self):
        page = self.url_open('/suivi-evangelisation/').text
        for relay in ('suiviPromptInstall', 'suiviIsStandalone', 'suiviWebPushToken'):
            self.assertIn(relay, page, "Relais absent : la banderole ou les notifications se tairaient")
