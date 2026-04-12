from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchAttendanceSunday(models.Model):
    _name = 'church.attendance.sunday'
    _description = 'Présence au culte du dimanche'
    _order = 'date desc'

    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge', ondelete='set null')
    member_id = fields.Many2one('church.member', string='Membre', required=True, ondelete='cascade')
    date = fields.Date(string='Date du culte', required=True, default=fields.Date.today)
    present = fields.Boolean(string='Présent', default=True)
    notes = fields.Text(string='Notes')

    _constraints = [
        models.Constraint(
            'UNIQUE(member_id, date)',
            'La présence de ce membre est déjà enregistrée pour cette date.',
        ),
    ]

    @api.onchange('member_id')
    def _onchange_member_id(self):
        if self.member_id:
            self.church_id = self.member_id.church_id
            self.age_group_id = self.member_id.age_group_id
