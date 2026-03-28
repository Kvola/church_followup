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
    sunday_attendance = fields.Boolean(string='Présence au culte')
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

    @api.constrains('followup_id', 'week_number')
    def _check_week_unique(self):
        for rec in self:
            duplicate = self.search_count([
                ('followup_id', '=', rec.followup_id.id),
                ('week_number', '=', rec.week_number),
                ('id', '!=', rec.id),
            ])
            if duplicate:
                raise ValidationError(_('Un rapport pour la semaine %s existe déjà.') % rec.week_number)
