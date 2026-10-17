from odoo import api, fields, models, _
from odoo.exceptions import UserError

from ..models.church_tools import ABANDON_REASONS, MAX_PROPOSED_WEEKS


class ChurchFollowupAssign(models.TransientModel):
    """Ouvre le suivi d'une ou plusieurs personnes.

    Une nouvelle personne est confiée à l'évangéliste choisi ; un ancien membre,
    à la cellule choisie, sinon à sa propre cellule. Sans durée saisie, chacune
    garde la durée proposée pour elle (événement d'origine, sinon réglage de
    l'église).
    """
    _name = 'church.followup.assign'
    _description = 'Ouvrir un suivi'

    member_ids = fields.Many2many('church.member', string='Personnes', required=True)
    church_id = fields.Many2one('equipment.church', compute='_compute_church_id')
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste',
                                    domain="[('church_id', '=', church_id)]",
                                    help="Pour les nouvelles personnes.")
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule de prière',
                                     domain="[('church_id', '=', church_id)]",
                                     help="Pour les anciens membres. Vide : la cellule de chacun.")
    has_new = fields.Boolean(compute='_compute_church_id')
    has_old = fields.Boolean(compute='_compute_church_id')
    duration_weeks = fields.Integer(
        string='Durée (semaines)',
        help="Laisser vide pour appliquer à chacun la durée proposée pour lui.",
    )
    proposal_summary = fields.Text(string='Durées proposées', compute='_compute_church_id')

    @api.depends('member_ids')
    def _compute_church_id(self):
        for rec in self:
            churches = rec.member_ids.church_id
            rec.church_id = churches if len(churches) == 1 else False
            rec.has_old = any(m.person_profile == 'old_member' for m in rec.member_ids)
            rec.has_new = any(m.person_profile != 'old_member' for m in rec.member_ids)
            rec.proposal_summary = '\n'.join(
                '%s : %s' % (m.display_name, m.proposed_followup_label) for m in rec.member_ids[:20])

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        members = self.env['church.member'].browse(self.env.context.get('default_member_ids') or [])
        if len(members) == 1 and 'duration_weeks' in fields_list:
            res['duration_weeks'] = members.proposed_followup_weeks
        return res

    def action_confirm(self):
        self.ensure_one()
        if len(self.member_ids.church_id) > 1:
            raise UserError(_('Choisissez des personnes d\'une même église.'))
        if self.duration_weeks and not 1 <= self.duration_weeks <= MAX_PROPOSED_WEEKS:
            raise UserError(_('La durée va de 1 à %s semaines.') % MAX_PROPOSED_WEEKS)
        vals_list, missing = [], []
        for member in self.member_ids:
            vals = {'church_id': member.church_id.id, 'member_id': member.id}
            if member.person_profile == 'old_member':
                cell = self.prayer_cell_id or member.prayer_cell_id
                if not cell:
                    missing.append(_("%s (ancien membre sans cellule : choisissez une cellule)")
                                   % member.display_name)
                    continue
                vals['prayer_cell_id'] = cell.id
            else:
                if not self.evangelist_id:
                    missing.append(_("%s (nouvelle personne : choisissez un évangéliste)")
                                   % member.display_name)
                    continue
                vals['evangelist_id'] = self.evangelist_id.id
            if self.duration_weeks:
                vals['duration_weeks'] = self.duration_weeks
            vals_list.append(vals)
        if missing:
            raise UserError(_("Personne n'est confié tant que chacun n'a pas qui le suit :\n%s")
                            % '\n'.join(missing))
        followups = self.env['church.followup'].create(vals_list)
        if len(followups) == 1:
            return {'type': 'ir.actions.act_window', 'res_model': 'church.followup',
                    'res_id': followups.id, 'view_mode': 'form'}
        return {'type': 'ir.actions.act_window', 'name': _('Suivis ouverts'),
                'res_model': 'church.followup', 'view_mode': 'list,form',
                'domain': [('id', 'in', followups.ids)]}


class ChurchFollowupExtend(models.TransientModel):
    _name = 'church.followup.extend'
    _description = 'Prolonger un suivi'

    followup_id = fields.Many2one('church.followup', required=True, readonly=True)
    current_weeks = fields.Integer(related='followup_id.duration_weeks', string='Durée actuelle')
    weeks = fields.Integer(string='Semaines à ajouter', required=True,
                           default=lambda self: self._default_weeks())

    def _default_weeks(self):
        followup = self.env['church.followup'].browse(self.env.context.get('default_followup_id'))
        return followup.church_id.default_followup_weeks or 4

    def action_confirm(self):
        self.ensure_one()
        self.followup_id.action_extend(weeks=self.weeks)
        return {'type': 'ir.actions.act_window_close'}


class ChurchFollowupAbandon(models.TransientModel):
    _name = 'church.followup.abandon'
    _description = 'Interrompre un suivi'

    followup_id = fields.Many2one('church.followup', required=True, readonly=True)
    reason = fields.Selection(ABANDON_REASONS, string='Motif', required=True)
    note = fields.Text(string='Précisions', help="Obligatoires pour « Autre raison ».")

    def action_confirm(self):
        self.ensure_one()
        self.followup_id.action_abandon(reason=self.reason, note=self.note)
        return {'type': 'ir.actions.act_window_close'}
