from odoo import api, fields, models, _


class ChurchChurch(models.Model):
    _name = 'church.church'
    _description = 'Église'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom de l\'église', required=True, tracking=True)
    code = fields.Char(string='Code', copy=False)
    address = fields.Text(string='Adresse')
    city = fields.Char(string='Ville')
    country_id = fields.Many2one('res.country', string='Pays')
    phone = fields.Char(string='Téléphone')
    email = fields.Char(string='Email')
    pastor_name = fields.Char(string='Nom du pasteur')
    active = fields.Boolean(default=True)

    # Relations
    district_ids = fields.One2many('church.district', 'church_id', string='Quartiers')
    member_ids = fields.One2many('church.member', 'church_id', string='Membres')
    evangelist_ids = fields.One2many('church.evangelist', 'church_id', string='Évangélistes')
    prayer_cell_ids = fields.One2many('church.prayer.cell', 'church_id', string='Cellules de prière')
    age_group_ids = fields.One2many('church.age.group', 'church_id', string='Groupes d\'âge')
    mobile_user_ids = fields.One2many('church.mobile.user', 'church_id', string='Utilisateurs mobiles')

    # Computed
    member_count = fields.Integer(compute='_compute_counts', store=True, string='Nombre de membres')
    evangelist_count = fields.Integer(compute='_compute_counts', store=True, string='Nombre d\'évangélistes')
    cell_count = fields.Integer(compute='_compute_counts', store=True, string='Nombre de cellules')
    age_group_count = fields.Integer(compute='_compute_counts', store=True, string='Nombre de groupes')
    followup_active_count = fields.Integer(compute='_compute_followup_active_count', string='Suivis actifs')

    _sql_constraints = [
        ('unique_code', 'UNIQUE(code)', 'Le code de l\'église doit être unique.'),
    ]

    @api.depends('member_ids', 'evangelist_ids', 'prayer_cell_ids', 'age_group_ids')
    def _compute_counts(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)
            rec.evangelist_count = len(rec.evangelist_ids)
            rec.cell_count = len(rec.prayer_cell_ids)
            rec.age_group_count = len(rec.age_group_ids)

    def _compute_followup_active_count(self):
        followup_model = self.env['church.followup']
        for rec in self:
            rec.followup_active_count = followup_model.search_count([
                ('church_id', '=', rec.id),
                ('state', 'in', ('in_progress', 'extended')),
            ])

    def action_view_members(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Membres'),
            'res_model': 'church.member',
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id)],
        }

    def action_view_evangelists(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Évangélistes'),
            'res_model': 'church.evangelist',
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id)],
        }

    def action_view_cells(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Cellules de prière'),
            'res_model': 'church.prayer.cell',
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id)],
        }

    def action_view_age_groups(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Groupes d\'âge'),
            'res_model': 'church.age.group',
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id)],
        }

    def action_view_active_followups(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Suivis actifs'),
            'res_model': 'church.followup',
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id), ('state', 'in', ('in_progress', 'extended'))],
        }
