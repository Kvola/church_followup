from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError
from dateutil.relativedelta import relativedelta

from .church_tools import (
    ACTIVE_FOLLOWUP_STATES, FOLLOWUP_ORIGINS, MAX_FOLLOWUP_WEEKS, MAX_PROPOSED_WEEKS, check_same_church, check_weeks,
)


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
    duration_weeks = fields.Integer(
        string='Durée (semaines)', tracking=True,
        help="Proposée à l'ouverture (événement d'origine, sinon réglage de l'église), "
             "modifiable par l'évangéliste ; augmentée à chaque prolongation.",
    )
    duration_origin = fields.Selection(
        FOLLOWUP_ORIGINS, string='Origine de la durée', readonly=True,
        help="D'où vient la durée initiale du suivi.",
    )

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
    # Appui à la décision d'intégrer
    elapsed_weeks = fields.Integer(string='Semaines écoulées', compute='_compute_attendance')
    attendance_weeks = fields.Integer(string='Semaines de présence au culte', compute='_compute_attendance')
    attendance_rate = fields.Integer(string='Présence au culte (%)', compute='_compute_attendance')
    attendance_threshold = fields.Integer(related='church_id.integration_min_attendance',
                                          string='Seuil de présence (%)')
    below_threshold = fields.Boolean(string='Sous le seuil', compute='_compute_attendance')
    average_score = fields.Float(string='Score moyen', compute='_compute_attendance', digits=(4, 1))
    integration_justification = fields.Text(
        string="Justification de l'intégration", tracking=True,
        help="Exigée pour intégrer une personne dont la présence au culte est sous le seuil de l'église.",
    )
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
        check_weeks(self, 'duration_weeks', MAX_FOLLOWUP_WEEKS)

    @api.onchange('member_id')
    def _onchange_member_id(self):
        if self.member_id:
            self.church_id = self.member_id.church_id
            self.duration_weeks = self.member_id.proposed_followup_weeks

    @api.model
    def _apply_proposed_duration(self, vals, member):
        """Durée initiale : celle demandée, sinon celle proposée pour la personne.

        Une durée demandée qui diffère de la proposition devient « choix » ; une
        origine déjà fournie (transfert) est conservée telle quelle.
        """
        proposed = member.proposed_followup_weeks if member else 0
        proposed_origin = member.proposed_followup_origin if member else 'church'
        if not vals.get('duration_weeks'):
            vals['duration_weeks'] = proposed or 4
            vals.setdefault('duration_origin', proposed_origin)
        else:
            if vals['duration_weeks'] > MAX_PROPOSED_WEEKS and not vals.get('duration_origin'):
                raise ValidationError(_(
                    'Un suivi ne peut pas démarrer sur plus de %s semaines ; '
                    'prolongez-le ensuite si nécessaire.') % MAX_PROPOSED_WEEKS)
            vals.setdefault('duration_origin',
                            proposed_origin if vals['duration_weeks'] == proposed else 'manual')

    @api.depends('start_date', 'duration_weeks')
    def _compute_end_date(self):
        for rec in self:
            if rec.start_date and rec.duration_weeks:
                rec.end_date = rec.start_date + relativedelta(weeks=rec.duration_weeks)
            else:
                rec.end_date = False

    # ─── Calendrier des semaines ──────────────────────────────────────

    def _week_bounds(self, week_number):
        """(premier jour, dernier jour) de la semaine n° ``week_number`` du suivi."""
        self.ensure_one()
        start = self.start_date + relativedelta(weeks=week_number - 1)
        return start, start + relativedelta(days=6)

    def _week_number_of(self, day):
        """N° de la semaine du suivi qui contient ``day`` (0 si hors période)."""
        self.ensure_one()
        if not self.start_date or not day or day < self.start_date:
            return 0
        number = (day - self.start_date).days // 7 + 1
        return number if number <= self.duration_weeks else 0

    def _roll_call_dates(self, week_number):
        """Dates de présence au culte pointées pendant cette semaine du suivi."""
        self.ensure_one()
        if not self.start_date or not self.member_id:
            return []
        first, last = self._week_bounds(week_number)
        return self.env['church.attendance.sunday'].sudo().search([
            ('member_id', '=', self.member_id.id), ('present', '=', True),
            ('date', '>=', first), ('date', '<=', last),
        ]).mapped('date')

    @api.depends('start_date', 'duration_weeks', 'week_ids.sunday_attendance', 'week_ids.score',
                 'church_id.integration_min_attendance')
    def _compute_attendance(self):
        today = fields.Date.context_today(self)
        for rec in self:
            elapsed = 0
            if rec.start_date and today >= rec.start_date:
                elapsed = min(rec.duration_weeks, (today - rec.start_date).days // 7 + 1)
            # Une semaine compte si son rapport la coche OU si un pointage y tombe,
            # même quand aucun rapport n'a encore été rédigé.
            present_weeks = set(rec.week_ids.filtered(
                lambda w: w.sunday_attendance and w.week_number <= elapsed).mapped('week_number'))
            if elapsed and rec.member_id:
                attendances = self.env['church.attendance.sunday'].sudo().search([
                    ('member_id', '=', rec.member_id.id), ('present', '=', True),
                    ('date', '>=', rec.start_date),
                    ('date', '<', rec.start_date + relativedelta(weeks=elapsed)),
                ])
                present_weeks |= {rec._week_number_of(a.date) for a in attendances} - {0}
            present = len(present_weeks)
            rec.elapsed_weeks = elapsed
            rec.attendance_weeks = present
            rec.attendance_rate = round(present * 100 / elapsed) if elapsed else 0
            threshold = rec.church_id.integration_min_attendance
            rec.below_threshold = bool(threshold) and rec.attendance_rate < threshold
            rec.average_score = (sum(rec.week_ids.mapped('score')) / len(rec.week_ids)) if rec.week_ids else 0.0

    @api.depends('week_ids')
    def _compute_week_count(self):
        for rec in self:
            rec.week_count = len(rec.week_ids)

    @api.model_create_multi
    def create(self, vals_list):
        Member = self.env['church.member']
        for vals in vals_list:
            if vals.get('name', 'Nouveau') == 'Nouveau':
                vals['name'] = self.env['ir.sequence'].next_by_code('church.followup') or 'Nouveau'
            self._apply_proposed_duration(vals, Member.browse(vals.get('member_id')))
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
            justification = (rec.integration_justification or '').strip()
            if rec.below_threshold and not justification:
                raise UserError(_(
                    "Présence au culte : %(present)s semaine(s) sur %(elapsed)s (%(rate)s %%), "
                    "sous le seuil de %(threshold)s %% fixé par l'église. Pour intégrer quand même, "
                    "écrivez une justification ; sinon, prolongez le suivi.",
                    present=rec.attendance_weeks, elapsed=rec.elapsed_weeks,
                    rate=rec.attendance_rate, threshold=rec.attendance_threshold,
                ))
            if rec.below_threshold:
                rec.message_post(body=_(
                    "Intégration sous le seuil de présence (%(rate)s %% pour %(threshold)s %%). "
                    "Justification : %(text)s",
                    rate=rec.attendance_rate, threshold=rec.attendance_threshold, text=justification,
                ))
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

    def action_extend(self, weeks=None):
        """Prolonge le suivi du nombre de semaines choisi (par défaut : le réglage de l'église)."""
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être prolongés.'))
            added = weeks or rec.church_id.default_followup_weeks or 4
            if not 1 <= added <= MAX_PROPOSED_WEEKS:
                raise ValidationError(
                    _('Une prolongation va de 1 à %s semaines.') % MAX_PROPOSED_WEEKS)
            rec.write({
                'duration_weeks': rec.duration_weeks + added,
                'state': 'extended',
                'end_notice_sent': False,
            })
            rec.message_post(body=_('Suivi prolongé de %(added)s semaines (total : %(total)s semaines)',
                                    added=added, total=rec.duration_weeks))

    def action_open_extend_wizard(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Prolonger le suivi'),
            'res_model': 'church.followup.extend',
            'view_mode': 'form',
            'target': 'new',
            'context': {'default_followup_id': self.id},
        }

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
                'duration_origin': rec.duration_origin,
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
