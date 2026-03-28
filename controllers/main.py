from odoo import http


class ChurchFollowupController(http.Controller):

    @http.route('/church_followup', type='http', auth='public', website=True)
    def index(self, **kwargs):
        return http.request.render('church_followup.index', {})
