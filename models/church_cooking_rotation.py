from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchCookingRotation(models.Model):
    _name = 'church.cooking.rotation'
    _description = 'Rotation cuisine des cellules'
    _order = 'date'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule responsable', required=True)
    date = fields.Date(string='Date', required=True)
    description = fields.Char(string='Description', default='Cuisine pour l\'église')
    state = fields.Selection([
        ('planned', 'Planifié'),
        ('done', 'Effectué'),
        ('cancelled', 'Annulé'),
    ], string='État', default='planned')
    notes = fields.Text(string='Notes')

    @api.constrains('church_id', 'date')
    def _check_rotation_unique(self):
        for rec in self:
            duplicate = self.search_count([
                ('church_id', '=', rec.church_id.id),
                ('date', '=', rec.date),
                ('id', '!=', rec.id),
            ])
            if duplicate:
                raise ValidationError(_('Une rotation est déjà planifiée pour cette date.'))
