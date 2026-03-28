from odoo import api, fields, models, _


class ChurchAttendanceSunday(models.Model):
    _name = 'church.attendance.sunday'
    _description = 'Présence au culte du dimanche'
    _order = 'date desc'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge', required=True)
    member_id = fields.Many2one('church.member', string='Membre', required=True)
    date = fields.Date(string='Date du culte', required=True, default=fields.Date.today)
    present = fields.Boolean(string='Présent', default=True)
    notes = fields.Text(string='Notes')

    _sql_constraints = [
        ('attendance_sunday_uniq', 'UNIQUE(member_id, date)',
         'La présence de ce membre est déjà enregistrée pour cette date.'),
    ]
