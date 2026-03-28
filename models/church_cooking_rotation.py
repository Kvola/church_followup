from odoo import api, fields, models, _


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

    _sql_constraints = [
        ('rotation_date_church_uniq', 'UNIQUE(church_id, date)',
         'Une rotation est déjà planifiée pour cette date.'),
    ]
