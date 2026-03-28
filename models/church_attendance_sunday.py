from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


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

    @api.constrains('member_id', 'date')
    def _check_attendance_unique(self):
        for rec in self:
            duplicate = self.search_count([
                ('member_id', '=', rec.member_id.id),
                ('date', '=', rec.date),
                ('id', '!=', rec.id),
            ])
            if duplicate:
                raise ValidationError(_('La présence de ce membre est déjà enregistrée pour cette date.'))
