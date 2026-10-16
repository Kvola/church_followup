from odoo import api, fields, models, _
from odoo.exceptions import UserError

from .church_tools import check_same_church


class ChurchPrayerCell(models.Model):
    _name = 'church.prayer.cell'
    _description = 'Cellule de prière'
    _inherit = ['mail.thread', 'church.leader.mixin']
    _leader_role = 'cell_leader'
    _leader_link_field = 'prayer_cell_id'
    _order = 'name'

    name = fields.Char(string='Nom de la cellule', required=True, tracking=True)
    church_id = fields.Many2one('equipment.church', string='Église', required=True, ondelete='restrict')
    district_ids = fields.Many2many('church.district', string='Quartiers couverts')

    # Horaire
    meeting_day = fields.Selection([
        ('monday', 'Lundi'),
        ('tuesday', 'Mardi'),
        ('wednesday', 'Mercredi'),
        ('thursday', 'Jeudi'),
        ('friday', 'Vendredi'),
        ('saturday', 'Samedi'),
        ('sunday', 'Dimanche'),
    ], string='Jour de réunion', default='friday')
    meeting_time = fields.Char(string='Heure de réunion', default='19:00')
    meeting_location = fields.Char(string='Lieu de réunion')

    # Membres
    member_ids = fields.One2many('church.member', 'prayer_cell_id', string='Membres')
    member_count = fields.Integer(compute='_compute_member_count', store=True, string='Nombre de membres')

    active = fields.Boolean(default=True)
    notes = fields.Text(string='Notes')

    @api.constrains('church_id', 'district_ids')
    def _check_same_church(self):
        check_same_church(self, ['district_ids'])

    @api.depends('member_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)

    def action_view_members(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Membres de la cellule'),
            'res_model': 'church.member',
            'view_mode': 'list,form',
            'domain': [('prayer_cell_id', '=', self.id)],
        }
