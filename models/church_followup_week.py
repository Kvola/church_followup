from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchFollowupWeek(models.Model):
    _name = 'church.followup.week'
    _description = 'Rapport hebdomadaire de suivi'
    _order = 'week_number'

    followup_id = fields.Many2one('church.followup', string='Suivi', required=True, ondelete='cascade')
    church_id = fields.Many2one(related='followup_id.church_id', store=True)
    week_number = fields.Integer(string='Semaine N°', required=True)
    date = fields.Date(string='Date du rapport', default=fields.Date.today)

    # Indicateurs de suivi
    sunday_attendance = fields.Boolean(
        string='Présence au culte',
        help="Cochée d'office quand la personne a été pointée présente au culte "
             "pendant cette semaine du suivi ; l'évangéliste peut aussi la cocher.",
    )
    roll_call_present = fields.Boolean(
        string='Pointé(e) au culte', compute='_compute_roll_call_present',
        help="Une présence au culte est enregistrée pendant cette semaine du suivi.",
    )
    call_made = fields.Boolean(string='Appel effectué')
    visit_made = fields.Boolean(string='Visite effectuée')
    spiritual_state = fields.Selection([
        ('excellent', 'Excellent'),
        ('good', 'Bien'),
        ('average', 'Moyen'),
        ('poor', 'Faible'),
        ('critical', 'Critique'),
    ], string='État spirituel')

    notes = fields.Text(string='Notes / Observations')

    # Score calculé
    score = fields.Integer(compute='_compute_score', store=True, string='Score')

    _followup_week_uniq = models.Constraint(
        'UNIQUE(followup_id, week_number)',
        'Un rapport pour cette semaine existe déjà.',
    )

    @api.depends('followup_id.start_date', 'followup_id.member_id', 'week_number')
    def _compute_roll_call_present(self):
        for rec in self:
            rec.roll_call_present = bool(rec.followup_id and rec.week_number and
                                         rec.followup_id._roll_call_dates(rec.week_number))

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records._apply_roll_call()
        return records

    def write(self, vals):
        res = super().write(vals)
        if {'sunday_attendance', 'week_number', 'followup_id'} & set(vals):
            self._apply_roll_call()
        return res

    def _apply_roll_call(self):
        """Le pointage fait foi : une présence pointée coche la semaine."""
        to_check = self.filtered(lambda w: not w.sunday_attendance and w.roll_call_present)
        if to_check:
            super(ChurchFollowupWeek, to_check).write({'sunday_attendance': True})

    @api.constrains('week_number')
    def _check_week_number(self):
        for rec in self:
            if rec.week_number < 1:
                raise ValidationError(_('Le numéro de semaine doit être supérieur à 0.'))
            if rec.followup_id and rec.week_number > rec.followup_id.duration_weeks:
                raise ValidationError(
                    _('Le numéro de semaine (%s) dépasse la durée du suivi (%s semaines).')
                    % (rec.week_number, rec.followup_id.duration_weeks)
                )

    @api.depends('sunday_attendance', 'call_made', 'visit_made', 'spiritual_state')
    def _compute_score(self):
        state_scores = {
            'excellent': 5,
            'good': 4,
            'average': 3,
            'poor': 2,
            'critical': 1,
            False: 0,
        }
        for rec in self:
            score = 0
            if rec.sunday_attendance:
                score += 3
            if rec.call_made:
                score += 2
            if rec.visit_made:
                score += 3
            score += state_scores.get(rec.spiritual_state, 0)
            rec.score = score
