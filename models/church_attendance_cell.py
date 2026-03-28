from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchAttendanceCell(models.Model):
    _name = 'church.attendance.cell'
    _description = 'Présence à la cellule de prière'
    _order = 'date desc'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule de prière', required=True)
    member_id = fields.Many2one('church.member', string='Membre', required=True)
    date = fields.Date(string='Date de la cellule', required=True, default=fields.Date.today)
    present = fields.Boolean(string='Présent', default=True)
    notes = fields.Text(string='Notes')

    @api.constrains('member_id', 'date', 'prayer_cell_id')
    def _check_attendance_unique(self):
        for rec in self:
            duplicate = self.search_count([
                ('member_id', '=', rec.member_id.id),
                ('date', '=', rec.date),
                ('prayer_cell_id', '=', rec.prayer_cell_id.id),
                ('id', '!=', rec.id),
            ])
            if duplicate:
                raise ValidationError(_('La présence de ce membre est déjà enregistrée pour cette date.'))
