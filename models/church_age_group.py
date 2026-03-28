from odoo import api, fields, models, _


class ChurchAgeGroup(models.Model):
    _name = 'church.age.group'
    _description = 'Groupe d\'âge'
    _inherit = ['mail.thread']
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
    age_range_id = fields.Many2one('church.age.range', string='Tranche d\'âge',
                                    help='Applicable pour les groupes de mariés')

    # Responsable
    leader_name = fields.Char(string='Responsable')
    leader_phone = fields.Char(string='Téléphone du responsable')
    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte mobile responsable', readonly=True)

    # Membres
    member_ids = fields.One2many('church.member', 'age_group_id', string='Membres')
    member_count = fields.Integer(compute='_compute_member_count', string='Nombre de membres')

    active = fields.Boolean(default=True)
    notes = fields.Text(string='Notes')

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

    def action_create_leader_account(self):
        """Créer un compte mobile pour le responsable de groupe d'âge."""
        self.ensure_one()
        if self.mobile_user_id:
            return
        if not self.leader_phone:
            return
        mobile_user = self.env['church.mobile.user'].create({
            'name': self.leader_name or self.name,
            'phone': self.leader_phone,
            'role': 'group_leader',
            'church_id': self.church_id.id,
            'age_group_id': self.id,
        })
        self.mobile_user_id = mobile_user.id
