"""La version navigateur de Suivi Évangélisation, servie sur /suivi-evangelisation.

Pour les iPhone (aucun APK à ouvrir) et pour le travail de bureau : relire les
suivis, attribuer, inviter, devant un écran large. Tout le savoir — la politique
de sécurité de contenu sans laquelle la page reste blanche, le repli sur
`index.html` — vit dans `FlutterPwaMixin` de `mobile_app_release`.
"""
from odoo import http

from odoo.addons.mobile_app_release.controllers.pwa_serving import FlutterPwaMixin


class SuiviEvangelisationPwa(http.Controller, FlutterPwaMixin):
    pwa_bundle = 'church_followup/static/suivi_app'

    #: Identique au `--base-href` de scripts/build_pwa.sh et au `scope` du
    #: manifeste : désaccordés, page blanche sans message.
    pwa_root = '/suivi-evangelisation'

    @http.route(
        ['/suivi-evangelisation', '/suivi-evangelisation/', '/suivi-evangelisation/<path:chemin>'],
        # Hors plan du site : la page à indexer est /apps/suivi-evangelisation.
        type='http', auth='public', csrf=False, sitemap=False,
    )
    def app(self, chemin='', **kwargs):
        return self._serve_pwa(chemin)
