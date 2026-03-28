from odoo import api, fields, models, _


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

    _sql_constraints = [
        ('attendance_cell_uniq', 'UNIQUE(member_id, date, prayer_cell_id)',
         'La présence de ce membre est déjà enregistrée pour cette date.'),
    ]
