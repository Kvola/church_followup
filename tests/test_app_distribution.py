import base64
import io
import json
import zipfile

from odoo.tests import tagged
from odoo.tests.common import HttpCase


def _fake_apk():
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.writestr('AndroidManifest.xml', b'<manifest/>')
        archive.writestr('classes.dex', b'dex\n035\x00')
    return base64.b64encode(buffer.getvalue())


@tagged('post_install', '-at_install')
class TestAppDistribution(HttpCase):
    """L'application de suivi se télécharge sur /apps/suivi-evangelisation et
    annonce elle-même ses nouvelles versions."""

    def _latest(self, current_version):
        payload = {'jsonrpc': '2.0', 'method': 'call', 'params': {'current_version': current_version}}
        resp = self.url_open('/api/mobile/v1/apps/suivi-evangelisation/latest',
                             data=json.dumps(payload).encode(),
                             headers={'Content-Type': 'application/json'})
        return resp.json()['result']

    def test_app_is_declared_with_its_public_page(self):
        app = self.env.ref('church_followup.mobile_app_suivi_evangelisation')
        self.assertEqual(app.slug, 'suivi-evangelisation')
        self.assertTrue(app.icon)
        self.assertEqual(self.url_open('/apps/suivi-evangelisation').status_code, 200)

    def test_published_release_is_announced_to_older_installs(self):
        app = self.env.ref('church_followup.mobile_app_suivi_evangelisation')
        self.assertFalse(self._latest('2.2.0+3')['update_available'], "Rien de publié : rien à annoncer")
        release = self.env['mobile.app.release'].create({
            'app_id': app.id, 'version': '2.3.0+4',
            'apk_file': _fake_apk(), 'apk_filename': 'suivi.apk',
        })
        release.action_publish()
        answer = self._latest('2.2.0+3')
        self.assertTrue(answer['update_available'])
        self.assertEqual(answer['latest_version'], '2.3.0+4')
        self.assertTrue(answer['download_url'].endswith('/apps/suivi-evangelisation/download'))
        self.assertFalse(self._latest('2.3.0+4')['update_available'])

    def test_church_super_admin_can_publish(self):
        admin_group = self.env.ref('church_followup.group_church_admin')
        publisher = self.env.ref('mobile_app_release.group_app_publisher')
        self.assertIn(publisher, admin_group.all_implied_ids)
