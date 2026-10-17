from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError
from dateutil.relativedelta import relativedelta

from .church_tools import (
    ABANDON_REASONS, ACTIVE_FOLLOWUP_STATES, FOLLOWUP_ORIGINS, MAX_FOLLOWUP_WEEKS, MAX_PROPOSED_WEEKS, check_same_church, check_weeks,
)


#: Qui suit la personne : un évangéliste pour une nouvelle personne, une cellule
#: de prière (son responsable) pour un ancien membre qu'on reprend en suivi.
FOLLOWERS = [
    ('evangelist', 'Un évangéliste'),
    ('cell', 'Une cellule de prière'),
]


def expected_follower(member):
    """Qui doit suivre cette personne, selon son profil."""
    return 'cell' if member.person_profile == 'old_member' else 'evangelist'


class ChurchFollowup(models.Model):
    _name = 'church.followup'
    _description = 'Suivi d\'évangélisation'
    _inherit = ['mail.thread']
    _order = 'create_date desc'

    name = fields.Char(string='Référence', readonly=True, copy=False, default='Nouveau')
    church_id = fields.Many2one('equipment.church', string='Église', required=True, ondelete='restrict')
    evangelist_id = fields.Many2one(
        'church.evangelist', string='Évangéliste', tracking=True, index=True,
        help="Suit une nouvelle personne.")
    prayer_cell_id = fields.Many2one(
        'church.prayer.cell', string='Cellule qui suit', tracking=True, index=True, ondelete='restrict',
        help="Suit un ancien membre : son responsable rédige les rapports et décide au terme.")
    followed_by = fields.Selection(
        FOLLOWERS, string='Suivi par', compute='_compute_followed_by', store=True, index=True)
    followed_by_name = fields.Char(string='Suivi par (nom)', compute='_compute_followed_by', store=True)
    member_id = fields.Many2one('church.member', string='Personne suivie', required=True, tracking=True)
    person_profile = fields.Selection(
        related='member_id.person_profile', store=True, string='Profil',
        help="Nouvelle personne ou ancien membre repris en suivi.")

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
        # Dans l'ordre du parcours : la barre d'état les affiche ainsi.
        ('in_progress', 'En cours'),
        ('extended', 'Prolongé(e)'),
        ('integrated', 'Intégré(e)'),
        ('abandoned', 'Interrompu(e)'),
        ('transferred', 'Transféré(e)'),
    ], string='État', default='in_progress', tracking=True, index=True)

    # Résultat
    transferred_to_id = fields.Many2one('church.evangelist', string='Transféré à', ondelete='set null')
    transferred_to_cell_id = fields.Many2one('church.prayer.cell', string='Transféré à la cellule',
                                             ondelete='set null')
    target_cell_id = fields.Many2one('church.prayer.cell', string='Cellule cible', ondelete='set null')
    target_age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge cible', ondelete='set null')

    # Rapports hebdomadaires
    week_ids = fields.One2many('church.followup.week', 'followup_id', string='Rapports hebdomadaires')
    week_count = fields.Integer(compute='_compute_week_count', string='Semaines complétées')

    notes = fields.Text(string='Notes')
    # Abandon et reprise
    abandon_reason = fields.Selection(ABANDON_REASONS, string="Motif de l'interruption",
                                      tracking=True, readonly=True)
    abandon_note = fields.Text(string="Précisions sur l'interruption", tracking=True, readonly=True)
    abandon_date = fields.Date(string='Interrompu le', readonly=True)
    previous_followup_id = fields.Many2one(
        'church.followup', string='Reprend le suivi', readonly=True, ondelete='set null',
        help="Suivi interrompu dont celui-ci est la reprise.")

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

    @api.constrains('church_id', 'member_id', 'evangelist_id', 'prayer_cell_id', 'transferred_to_id',
                    'transferred_to_cell_id', 'target_cell_id', 'target_age_group_id')
    def _check_same_church(self):
        check_same_church(self, ['member_id', 'evangelist_id', 'prayer_cell_id', 'transferred_to_id',
                                 'transferred_to_cell_id', 'target_cell_id', 'target_age_group_id'])

    @api.depends('evangelist_id', 'prayer_cell_id')
    def _compute_followed_by(self):
        for rec in self:
            rec.followed_by = 'cell' if rec.prayer_cell_id else ('evangelist' if rec.evangelist_id else False)
            rec.followed_by_name = rec.prayer_cell_id.name or rec.evangelist_id.name or False

    @api.constrains('evangelist_id', 'prayer_cell_id', 'member_id', 'state')
    def _check_follower(self):
        """Une nouvelle personne est suivie par un évangéliste, un ancien membre par
        une cellule — jamais les deux, jamais personne. Seuls les suivis en cours
        sont tenus : un suivi terminé garde l'histoire telle qu'elle a été."""
        for rec in self.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES):
            name = rec.member_id.display_name
            if expected_follower(rec.member_id) == 'cell':
                if rec.evangelist_id or not rec.prayer_cell_id:
                    raise ValidationError(_(
                        "%s est un ancien membre : son suivi se confie à une cellule de prière, "
                        "pas à un évangéliste.") % name)
            elif rec.prayer_cell_id or not rec.evangelist_id:
                raise ValidationError(_(
                    "%s est une nouvelle personne : son suivi se confie à un évangéliste, "
                    "pas à une cellule de prière.") % name)

    @api.model
    def _check_cell_can_follow(self, cell):
        """Une cellule sans responsable joignable ne peut pas suivre : personne ne
        rédigerait les rapports, personne ne serait relancé."""
        if cell and not cell._leader_accounts():
            raise UserError(_(
                "La cellule « %s » n'a pas de responsable qui puisse se connecter : ouvrez d'abord "
                "le compte de son responsable (fiche de la cellule).") % cell.name)

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

    def _cell_roll_call_dates(self, week_number):
        """Dates de présence en cellule pointées pendant cette semaine du suivi."""
        self.ensure_one()
        if not self.start_date or not self.member_id:
            return []
        first, last = self._week_bounds(week_number)
        return self.env['church.attendance.cell'].sudo().search([
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
            member = Member.browse(vals.get('member_id'))
            # Un ancien membre est confié à sa propre cellule, sauf autre choix.
            if member and expected_follower(member) == 'cell' and not vals.get('evangelist_id'):
                vals.setdefault('prayer_cell_id', member.prayer_cell_id.id or False)
                if not vals.get('prayer_cell_id'):
                    raise UserError(_(
                        "%s est un ancien membre sans cellule : choisissez la cellule de prière "
                        "qui le suivra.") % member.display_name)
            if vals.get('prayer_cell_id'):
                cell = self.env['church.prayer.cell'].browse(vals['prayer_cell_id'])
                self._check_cell_can_follow(cell)
                # Au terme, on intègre d'abord dans la cellule qui a suivi.
                vals.setdefault('target_cell_id', cell.id)
            self._apply_proposed_duration(vals, member)
            # Une reprise garde le lien avec le suivi interrompu.
            if member and member.member_type == 'interrupted' and 'previous_followup_id' not in vals:
                previous = self.search([('member_id', '=', member.id), ('state', '=', 'abandoned')],
                                       order='abandon_date desc, id desc', limit=1)
                vals['previous_followup_id'] = previous.id or False
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
                'integration_date': fields.Date.context_today(rec),
            })

    def action_abandon(self, reason=None, note=None):
        """Interrompt le suivi. Le motif est obligatoire : il distingue plus tard
        une personne injoignable d'une personne partie dans une autre église."""
        if reason not in dict(ABANDON_REASONS):
            raise UserError(_("Indiquez le motif de l'interruption du suivi."))
        note = (note or '').strip()
        if reason == 'other' and not note:
            raise UserError(_("Précisez la raison de l'interruption."))
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être interrompus.'))
            rec.write({
                'state': 'abandoned',
                'abandon_reason': reason,
                'abandon_note': note or False,
                'abandon_date': fields.Date.context_today(rec),
            })
            rec.member_id.write({'member_type': 'interrupted'})

    def action_open_abandon_wizard(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _('Interrompre le suivi'),
            'res_model': 'church.followup.abandon',
            'view_mode': 'form',
            'target': 'new',
            'context': {'default_followup_id': self.id},
        }

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

    def write(self, vals):
        if vals.get('prayer_cell_id'):
            self._check_cell_can_follow(self.env['church.prayer.cell'].browse(vals['prayer_cell_id']))
        return super().write(vals)

    def action_transfer(self):
        """Transférer à un autre évangéliste, ou — ancien membre — à une autre cellule."""
        for rec in self:
            if rec.state not in ACTIVE_FOLLOWUP_STATES:
                raise UserError(_('Seuls les suivis en cours peuvent être transférés.'))
            if rec.followed_by == 'cell':
                target = rec.transferred_to_cell_id
                if not target:
                    raise ValidationError(_('Veuillez sélectionner la cellule destinataire.'))
                if target == rec.prayer_cell_id:
                    raise ValidationError(_('Choisissez une autre cellule que celle qui suit déjà.'))
                follower = {'prayer_cell_id': target.id, 'target_cell_id': target.id}
            else:
                if not rec.transferred_to_id:
                    raise ValidationError(_('Veuillez sélectionner l\'évangéliste destinataire.'))
                if rec.transferred_to_id == rec.evangelist_id:
                    raise ValidationError(_('Impossible de transférer à la même personne.'))
                follower = {'evangelist_id': rec.transferred_to_id.id}
            rec.state = 'transferred'
            # Un nouveau suivi, pour le nouvel évangéliste ou la nouvelle cellule.
            self.create(dict(follower, **{
                'church_id': rec.church_id.id,
                'member_id': rec.member_id.id,
                'start_date': fields.Date.today(),
                'duration_weeks': rec.duration_weeks,
                'duration_origin': rec.duration_origin,
            }))

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
        expired._notify_period_end()
