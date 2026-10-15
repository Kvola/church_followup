from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError
from dateutil.relativedelta import relativedelta

from .church_tools import ACTIVE_FOLLOWUP_STATES, check_same_church


class ChurchFollowup(models.Model):
    _name = 'church.followup'
    _description = 'Suivi d\'évangélisation'
    _inherit = ['mail.thread']
    _order = 'create_date desc'

    name = fields.Char(string='Référence', readonly=True, copy=False, default='Nouveau')
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste', required=True, tracking=True)
    member_id = fields.Many2one('church.member', string='Personne suivie', required=True, tracking=True)

    start_date = fields.Date(string='Date de début', default=fields.Date.today, required=True)
    end_date = fields.Date(string='Date de fin prévue', compute='_compute_end_date', store=True)
    duration_weeks = fields.Integer(string='Durée (semaines)', default=4)

    state = fields.Selection([
        ('in_progress', 'En cours'),
        ('integrated', 'Intégré(e)'),
        ('abandoned', 'Abandonné(e)'),
        ('extended', 'Prolongé(e)'),
        ('transferred', 'Transféré(e)'),
    ], string='État', default='in_progress', tracking=True, index=True)

    # Résultat
    transferred_to_id = fields.Many2one('church.evangelist', string='Transféré à', ondelete='set null')
    target_cell_id = fields.Many2one('church.prayer.cell', string='Cellule cible', ondelete='set null')
    target_age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge cible', ondelete='set null')

    # Rapports hebdomadaires
    week_ids = fields.One2many('church.followup.week', 'followup_id', string='Rapports hebdomadaires')
    week_count = fields.Integer(compute='_compute_week_count', string='Semaines complétées')

    notes = fields.Text(string='Notes')
    end_notice_sent = fields.Boolean(
        string='Fin de période signalée', copy=False,
        help="Le message de fin de période a été posté ; remis à zéro quand le suivi est prolongé.",
    )

    @api.constrains('church_id', 'member_id', 'evangelist_id', 'transferred_to_id',
                    'target_cell_id', 'target_age_group_id')
    def _check_same_church(self):
        check_same_church(self, ['member_id', 'evangelist_id', 'transferred_to_id',
                                 'target_cell_id', 'target_age_group_id'])

    @api.constrains('member_id', 'state')
    def _check_single_active_followup(self):
        active = self.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)
        if not active:
            return
        groups = self._read_group(
            [('member_id', 'in', active.member_id.ids), ('state', 'in', ACTIVE_FOLLOWUP_STATES)],
            groupby=['member_id'], aggregates=['__count'],
        )
        for member, count in groups:
            if count > 1:
                raise ValidationError(
                    _('Un suivi actif existe déjà pour %s.') % member.display_name
                )

    @api.constrains('duration_weeks')
    def _check_duration_weeks(self):
        for rec in self:
            if rec.duration_weeks < 1:
                raise ValidationError(_('La durée du suivi doit être d\'au moins une semaine.'))

    @api.depends('start_date', 'duration_weeks')
    def _compute_end_date(self):
        for rec in self:
            if rec.start_date and rec.duration_weeks:
                rec.end_date = rec.start_date + relativedelta(weeks=rec.duration_weeks)
            else:
                rec.end_date = False

    @api.depends('week_ids')
    def _compute_week_count(self):
        for rec in self:
            rec.week_count = len(rec.week_ids)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', 'Nouveau') == 'Nouveau':
                vals['name'] = self.env['ir.sequence'].next_by_code('church.followup') or 'Nouveau'
        records = super().create(vals_list)
        # L'unicité du suivi actif est gardée par _check_single_active_followup.
        records.filtered(
            lambda f: f.state in ACTIVE_FOLLOWUP_STATES
        ).member_id.write({'member_type': 'in_followup'})
        return records

    def action_integrate(self):
        """Intégrer la personne dans l'église."""
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être intégrés.'))
            if not rec.target_cell_id or not rec.target_age_group_id:
                raise ValidationError(_('Veuillez sélectionner une cellule de prière et un groupe d\'âge.'))
            rec.state = 'integrated'
            rec.member_id.write({
                'member_type': 'integrated',
                'prayer_cell_id': rec.target_cell_id.id,
                'age_group_id': rec.target_age_group_id.id,
                'integration_date': fields.Date.today(),
            })

    def action_abandon(self):
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être abandonnés.'))
            rec.state = 'abandoned'
            rec.member_id.write({'member_type': 'new'})

    def action_extend(self):
        """Prolonger le suivi de 4 semaines supplémentaires."""
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être prolongés.'))
            rec.write({
                'duration_weeks': rec.duration_weeks + 4,
                'state': 'extended',
                'end_notice_sent': False,
            })
            rec.message_post(body=_('Suivi prolongé de 4 semaines (total: %s semaines)') % rec.duration_weeks)

    def action_transfer(self):
        """Transférer à un autre évangéliste."""
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être transférés.'))
            if not rec.transferred_to_id:
                raise ValidationError(_('Veuillez sélectionner l\'évangéliste destinataire.'))
            if rec.transferred_to_id == rec.evangelist_id:
                raise ValidationError(_('Impossible de transférer à la même personne.'))
            rec.state = 'transferred'
            # Créer un nouveau suivi pour le nouvel évangéliste
            self.create({
                'church_id': rec.church_id.id,
                'evangelist_id': rec.transferred_to_id.id,
                'member_id': rec.member_id.id,
                'start_date': fields.Date.today(),
                'duration_weeks': rec.duration_weeks,
            })

    @api.model
    def _cron_send_reminders(self):
        """Envoie des rappels aux évangélistes pour les suivis actifs."""
        active_followups = self.search([('state', 'in', ACTIVE_FOLLOWUP_STATES)])
        for followup in active_followups:
            # Les rappels seront gérés via l'API mobile (notifications push)
            pass

    @api.model
    def _cron_check_followup_end(self):
        """Signale une seule fois chaque suivi actif arrivé à terme."""
        today = fields.Date.today()
        expired = self.search([
            ('state', 'in', ACTIVE_FOLLOWUP_STATES),
            ('end_date', '<=', today),
            ('end_notice_sent', '=', False),
        ])
        for followup in expired:
            followup.message_post(
                body=_('La période de suivi est terminée. Veuillez prendre une décision.')
            )
        expired.write({'end_notice_sent': True})
