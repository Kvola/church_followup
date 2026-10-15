from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

from .church_tools import (
    ACTIVE_FOLLOWUP_STATES, DEFAULT_FOLLOWUP_WEEKS, MAX_PROPOSED_WEEKS, check_weeks,
)


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
    pastor_name = fields.Char(
        string='Pasteur principal', compute='_compute_pastor_name',
        store=True, readonly=True,
    )
    active = fields.Boolean(default=True)
    default_followup_weeks = fields.Integer(
        string='Durée de suivi par défaut (semaines)', default=DEFAULT_FOLLOWUP_WEEKS,
        help="Durée proposée pour suivre une nouvelle personne, quand ni un événement "
             "ni l'évangéliste n'en fixent une autre.",
    )

    # Relations
    pastor_ids = fields.One2many('church.pastor', 'church_id', string='Pasteurs')
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
    pastor_count = fields.Integer(compute='_compute_counts', store=True, string='Nombre de pasteurs')
    followup_active_count = fields.Integer(compute='_compute_followup_active_count', string='Suivis actifs')

    _code_uniq = models.Constraint(
        'UNIQUE(code)',
        'Le code de l\'église doit être unique.',
    )

    integration_min_attendance = fields.Integer(
        string="Présence minimale au culte pour intégrer (%)", default=75,
        help="Part des semaines écoulées du suivi où la personne est venue au culte. "
             "En dessous, l'intégration reste possible mais demande une justification "
             "écrite. 0 : aucun seuil.",
    )

    @api.constrains('integration_min_attendance')
    def _check_integration_min_attendance(self):
        for rec in self:
            if not 0 <= rec.integration_min_attendance <= 100:
                raise ValidationError(_('Le seuil de présence est un pourcentage entre 0 et 100.'))

    @api.constrains('default_followup_weeks')
    def _check_default_followup_weeks(self):
        check_weeks(self, 'default_followup_weeks', MAX_PROPOSED_WEEKS)

    @api.depends('pastor_ids', 'pastor_ids.pastor_type', 'pastor_ids.name', 'pastor_ids.active')
    def _compute_pastor_name(self):
        for rec in self:
            principal = rec.pastor_ids.filtered(
                lambda p: p.pastor_type == 'principal' and p.active
            )
            rec.pastor_name = principal[:1].name if principal else ''

    @api.depends('member_ids', 'evangelist_ids', 'prayer_cell_ids', 'age_group_ids', 'pastor_ids')
    def _compute_counts(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)
            rec.evangelist_count = len(rec.evangelist_ids)
            rec.cell_count = len(rec.prayer_cell_ids)
            rec.age_group_count = len(rec.age_group_ids)
            rec.pastor_count = len(rec.pastor_ids)

    def _compute_followup_active_count(self):
        followup_model = self.env['church.followup']
        for rec in self:
            rec.followup_active_count = followup_model.search_count([
                ('church_id', '=', rec.id),
                ('state', 'in', ACTIVE_FOLLOWUP_STATES),
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
            'domain': [('church_id', '=', self.id), ('state', 'in', ACTIVE_FOLLOWUP_STATES)],
        }

    def action_view_pastors(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Pasteurs'),
            'res_model': 'church.pastor',
            'view_mode': 'list,kanban,form',
            'domain': [('church_id', '=', self.id)],
        }
