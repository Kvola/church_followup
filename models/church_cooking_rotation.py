from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError

from .church_tools import check_same_church


class ChurchCookingRotation(models.Model):
    _name = 'church.cooking.rotation'
    _description = 'Rotation cuisine des cellules'
    _order = 'date'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule responsable', required=True, ondelete='restrict')
    date = fields.Date(string='Date', required=True)
    description = fields.Char(string='Description', default='Cuisine pour l\'église')
    state = fields.Selection([
        ('planned', 'Planifié'),
        ('done', 'Effectué'),
        ('cancelled', 'Annulé'),
    ], string='État', default='planned')
    notes = fields.Text(string='Notes')

    _church_date_uniq = models.Constraint(
        'UNIQUE(church_id, date)',
        'Une rotation est déjà planifiée pour cette date.',
    )

    @api.constrains('church_id', 'prayer_cell_id')
    def _check_same_church(self):
        check_same_church(self, ['prayer_cell_id'])

    def action_done(self):
        for rec in self:
            if rec.state != 'planned':
                raise UserError(_('Seules les rotations planifiées peuvent être marquées comme effectuées.'))
            rec.state = 'done'

    def action_cancel(self):
        for rec in self:
            if rec.state == 'done':
                raise UserError(_('Impossible d\'annuler une rotation déjà effectuée.'))
            rec.state = 'cancelled'
