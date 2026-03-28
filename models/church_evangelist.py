from odoo import api, fields, models, _


class ChurchEvangelist(models.Model):
    _name = 'church.evangelist'
    _description = 'Évangéliste'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    phone = fields.Char(string='Téléphone', tracking=True)
    email = fields.Char(string='Email')
    photo = fields.Binary(string='Photo')
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte mobile', readonly=True)
    active = fields.Boolean(default=True)

    # Suivi
    followup_ids = fields.One2many('church.followup', 'evangelist_id', string='Suivis')
    active_followup_count = fields.Integer(compute='_compute_followup_stats', string='Suivis actifs')
    total_followup_count = fields.Integer(compute='_compute_followup_stats', string='Total suivis')
    integrated_count = fields.Integer(compute='_compute_followup_stats', string='Intégrés')
    integration_rate = fields.Float(compute='_compute_followup_stats', string='Taux d\'intégration (%)')

    @api.depends('followup_ids', 'followup_ids.state')
    def _compute_followup_stats(self):
        for rec in self:
            followups = rec.followup_ids
            rec.active_followup_count = len(followups.filtered(lambda f: f.state == 'in_progress'))
            rec.total_followup_count = len(followups)
            rec.integrated_count = len(followups.filtered(lambda f: f.state == 'integrated'))
            completed = len(followups.filtered(lambda f: f.state in ('integrated', 'abandoned')))
            rec.integration_rate = (rec.integrated_count / completed * 100) if completed else 0.0

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        for rec in records:
            if not rec.phone:
                continue
            # Créer automatiquement le compte mobile
            mobile_user = self.env['church.mobile.user'].create({
                'name': rec.name,
                'phone': rec.phone,
                'role': 'evangelist',
                'church_id': rec.church_id.id,
                'evangelist_id': rec.id,
            })
            rec.mobile_user_id = mobile_user.id
        return records

    def action_view_followups(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Suivis'),
            'res_model': 'church.followup',
            'view_mode': 'list,form',
            'domain': [('evangelist_id', '=', self.id)],
        }
