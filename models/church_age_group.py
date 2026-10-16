from odoo import api, fields, models, _
from odoo.exceptions import UserError

from .church_tools import check_same_church


class ChurchAgeGroup(models.Model):
    _name = 'church.age.group'
    _description = 'Groupe d\'âge'
    _inherit = ['mail.thread', 'church.leader.mixin']
    _leader_role = 'group_leader'
    _leader_link_field = 'age_group_id'
    _order = 'name'

    name = fields.Char(string='Nom du groupe', required=True, tracking=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    group_type = fields.Selection([
        ('married', 'Mariés'),
        ('youth', 'Jeunes'),
        ('college', 'Collégiens'),
        ('highschool', 'Lycéens'),
        ('children', 'Enfants'),
    ], string='Type de groupe', required=True)
    gender = fields.Selection([
        ('male', 'Hommes'),
        ('female', 'Femmes'),
        ('mixed', 'Mixte'),
    ], string='Sexe', required=True)
    age_range_id = fields.Many2one('church.age.range', string='Tranche d\'âge', ondelete='set null',
                                    help='Applicable pour les groupes de mariés')

    # Responsable

    # Membres
    member_ids = fields.One2many('church.member', 'age_group_id', string='Membres')
    member_count = fields.Integer(compute='_compute_member_count', string='Nombre de membres')

    active = fields.Boolean(default=True)
    notes = fields.Text(string='Notes')

    @api.constrains('church_id', 'age_range_id')
    def _check_same_church(self):
        check_same_church(self, ['age_range_id'])

    @api.depends('member_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)

    def action_view_members(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Membres du groupe'),
            'res_model': 'church.member',
            'view_mode': 'list,form',
            'domain': [('age_group_id', '=', self.id)],
        }
