"""Le manuel de formation, servi comme le guide : une page, et le même texte en PDF.

Il réutilise la page de guide de `mobile_app_release` (son titre est
réglable) : deux pages de mise en forme seraient deux pages à tenir à jour.
"""
from odoo import http
from odoo.http import request

APP_XMLID = 'church_followup.mobile_app_suivi_evangelisation'
MANUAL_TEMPLATE = 'church_followup.training_manual_content'
MANUAL_REPORT = 'church_followup.action_report_training_manual'


class ChurchFollowupTraining(http.Controller):

    def _app(self):
        return request.env.ref(APP_XMLID, raise_if_not_found=False)

    @http.route('/apps/suivi-evangelisation/formation', type='http', auth='public',
                website=False, sitemap=False)
    def training_manual(self, **kwargs):
        app = self._app()
        if not app:
            return request.not_found()
        return request.render('mobile_app_release.app_guide_page', {
            'app': app.sudo(),
            'guide_template': MANUAL_TEMPLATE,
            'doc_title': 'Manuel de formation',
            'pdf_url': '/apps/suivi-evangelisation/formation.pdf',
            'pdf_label': 'Télécharger le manuel en PDF',
        })

    @http.route('/apps/suivi-evangelisation/formation.pdf', type='http', auth='public',
                website=False, sitemap=False)
    def training_manual_pdf(self, **kwargs):
        app = self._app()
        if not app:
            return request.not_found()
        pdf, _type = request.env['ir.actions.report'].sudo()._render_qweb_pdf(
            MANUAL_REPORT, res_ids=app.ids)
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="manuel-formation-suivi-evangelisation.pdf"'),
        ])
