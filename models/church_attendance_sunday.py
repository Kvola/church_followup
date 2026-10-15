from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

from .church_tools import check_same_church


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

    _member_date_uniq = models.Constraint(
        'UNIQUE(member_id, date)',
        'La présence de ce membre est déjà enregistrée pour cette date.',
    )

    @api.constrains('church_id', 'member_id', 'age_group_id')
    def _check_same_church(self):
        check_same_church(self, ['member_id', 'age_group_id'])

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records._report_to_followups()
        return records

    def write(self, vals):
        res = super().write(vals)
        if {'present', 'date', 'member_id'} & set(vals):
            self._report_to_followups()
        return res

    def _report_to_followups(self):
        """Coche la présence dans le rapport de la semaine de suivi correspondante."""
        present = self.filtered('present')
        if not present:
            return
        followups = self.env['church.followup'].search([('member_id', 'in', present.member_id.ids)])
        for att in present:
            for followup in followups.filtered(lambda f: f.member_id == att.member_id):
                week_number = followup._week_number_of(att.date)
                if not week_number:
                    continue
                week = followup.week_ids.filtered(lambda w: w.week_number == week_number)
                if week and not week.sunday_attendance:
                    week.write({'sunday_attendance': True})

    @api.onchange('member_id')
    def _onchange_member_id(self):
        if self.member_id:
            self.church_id = self.member_id.church_id
            self.age_group_id = self.member_id.age_group_id
