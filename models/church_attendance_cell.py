from odoo import api, fields, model, models, _
from odoo.exceptions import ValidationError


class ChurchAttendanceCell(models.Model):
    _name = 'church.attendance.cell'
    _description = 'Présence à la cellule de prière'
    _order = 'date desc'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule de prière', required=True, ondelete='cascade')
    member_id = fields.Many2one('church.member', string='Membre', required=True, ondelete='cascade')
    date = fields.Date(string='Date de la cellule', required=True, default=fields.Date.today)
    present = fields.Boolean(string='Présent', default=True)
    notes = fields.Text(string='Notes')

    _constraints = [
        model.Constraint(
            'UNIQUE(member_id, prayer_cell_id, date)',
            'La présence de ce membre est déjà enregistrée pour cette date.',
        ),
    ]

    @api.onchange('member_id')
    def _onchange_member_id(self):
        if self.member_id:
            self.church_id = self.member_id.church_id
            self.prayer_cell_id = self.member_id.prayer_cell_id
