"""L'import Excel depuis le back-office : le même moteur que l'application."""
import base64

from odoo import _, fields, models

from ..models.church_import import IMPORT_KINDS


class ChurchImportWizard(models.TransientModel):
    _name = 'church.import.wizard'
    _description = "Importer un fichier Excel du suivi"

    church_id = fields.Many2one('equipment.church', string='Église', required=True,
                                domain=[('followup_enabled', '=', True)])
    kind = fields.Selection(IMPORT_KINDS, string='Import', required=True)
    file = fields.Binary(string='Fichier (.xlsx)')
    filename = fields.Char(string='Nom du fichier')
    state = fields.Selection([('draft', 'À importer'), ('done', 'Importé'), ('refused', 'Refusé')],
                             default='draft')
    result_message = fields.Char(string='Résultat', readonly=True)
    result_errors = fields.Text(string='Erreurs', readonly=True)
    result_warnings = fields.Text(string='Remarques', readonly=True)

    def _reopen(self):
        return {'type': 'ir.actions.act_window', 'res_model': self._name, 'res_id': self.id,
                'view_mode': 'form', 'target': 'new', 'name': _('Importer un fichier')}

    def action_download_template(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_url', 'target': 'self',
            'url': '/church_followup/import/template?kind=%s&church_id=%d' % (self.kind, self.church_id.id),
        }

    def action_import(self):
        self.ensure_one()
        if not self.file:
            self.write({'state': 'refused', 'result_message': _("Choisissez d'abord un fichier."),
                        'result_errors': False, 'result_warnings': False})
            return self._reopen()
        result = self.env['church.import']._run(
            self.kind, self.church_id, base64.b64decode(self.file), self.filename)
        self.write({
            'state': 'done' if result['ok'] else 'refused',
            'result_message': result['message'],
            'result_errors': '\n'.join(result['errors']) or False,
            'result_warnings': '\n'.join(result['warnings']) or False,
        })
        return self._reopen()

    def action_retry(self):
        self.write({'state': 'draft', 'file': False, 'filename': False, 'result_message': False,
                    'result_errors': False, 'result_warnings': False})
        return self._reopen()
