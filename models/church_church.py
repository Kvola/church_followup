from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

from .church_tools import (
    ACTIVE_FOLLOWUP_STATES, DEFAULT_FOLLOWUP_WEEKS, MAX_PROPOSED_WEEKS, check_weeks,
)


class EquipmentChurch(models.Model):
    """L'église de l'annuaire partagé (church_core), vue par le suivi.

    Le suivi ne tient plus sa propre liste d'églises ni de pasteurs : il ajoute
    à l'église de l'annuaire ce qui lui est propre — réglages, cellules,
    membres — et lit les pasteurs titulaires de bng_equipment_loan. Une église
    créée, renommée ou fusionnée dans l'annuaire l'est donc aussi ici.
    """
    _inherit = 'equipment.church'

    followup_enabled = fields.Boolean(
        string="Suivi d'évangélisation", default=False, tracking=True,
        help="L'église utilise le suivi des nouvelles personnes. Seules ces églises "
             "apparaissent dans l'application de suivi ; les autres restent dans "
             "l'annuaire du réseau.",
    )
    pastor_name = fields.Char(
        string='Pasteurs titulaires (noms)', compute='_compute_pastor_name',
        help="Les pasteurs titulaires actifs de l'annuaire.",
    )
    default_followup_weeks = fields.Integer(
        string='Durée de suivi par défaut (semaines)', default=DEFAULT_FOLLOWUP_WEEKS,
        help="Durée proposée pour suivre une nouvelle personne, quand ni un événement "
             "ni l'évangéliste n'en fixent une autre.",
    )
    integration_min_attendance = fields.Integer(
        string="Présence minimale au culte pour intégrer (%)", default=75,
        help="Part des semaines écoulées du suivi où la personne est venue au culte. "
             "En dessous, l'intégration reste possible mais demande une justification "
             "écrite. 0 : aucun seuil.",
    )

    # Relations
    district_ids = fields.One2many('church.district', 'church_id', string='Quartiers')
    member_ids = fields.One2many('church.member', 'church_id', string='Membres')
    evangelist_ids = fields.One2many('church.evangelist', 'church_id', string='Évangélistes')
    prayer_cell_ids = fields.One2many('church.prayer.cell', 'church_id', string='Cellules de prière')
    age_group_ids = fields.One2many('church.age.group', 'church_id', string='Groupes d\'âge')
    mobile_user_ids = fields.One2many('church.mobile.user', 'church_id', string='Utilisateurs mobiles')

    # Computed
    member_count = fields.Integer(compute='_compute_followup_counts', store=True, string='Nombre de membres')
    evangelist_count = fields.Integer(compute='_compute_followup_counts', store=True, string='Nombre d\'évangélistes')
    cell_count = fields.Integer(compute='_compute_followup_counts', store=True, string='Nombre de cellules')
    age_group_count = fields.Integer(compute='_compute_followup_counts', store=True, string='Nombre de groupes')
    followup_active_count = fields.Integer(compute='_compute_followup_active_count', string='Suivis actifs')

    @api.constrains('integration_min_attendance')
    def _check_integration_min_attendance(self):
        for rec in self:
            if not 0 <= rec.integration_min_attendance <= 100:
                raise ValidationError(_('Le seuil de présence est un pourcentage entre 0 et 100.'))

    @api.constrains('default_followup_weeks')
    def _check_default_followup_weeks(self):
        check_weeks(self, 'default_followup_weeks', MAX_PROPOSED_WEEKS)

    def _compute_pastor_name(self):
        for rec in self:
            rec.pastor_name = ', '.join(rec.titular_pastor_ids.mapped('name'))

    @api.depends('member_ids', 'evangelist_ids', 'prayer_cell_ids', 'age_group_ids')
    def _compute_followup_counts(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)
            rec.evangelist_count = len(rec.evangelist_ids)
            rec.cell_count = len(rec.prayer_cell_ids)
            rec.age_group_count = len(rec.age_group_ids)

    def _compute_followup_active_count(self):
        data = dict(self.env['church.followup']._read_group(
            [('church_id', 'in', self.ids), ('state', 'in', ACTIVE_FOLLOWUP_STATES)],
            ['church_id'], ['__count']))
        for rec in self:
            rec.followup_active_count = data.get(rec, 0)

    def _enable_followup(self):
        """L'église entre dans le suivi dès qu'on y suit quelqu'un ou qu'on y ouvre un compte."""
        self.filtered(lambda c: not c.followup_enabled).sudo().write({'followup_enabled': True})

    # ─── Fusion de doublons (church_core) ─────────────────────────────

    def _merge_absorb_into(self, survivor):
        """Ce que le report en SQL du socle ferait buter sur une unicité du suivi.

        Un même numéro a un compte dans les deux églises : on garde celui de
        l'église conservée. Deux rotations de cuisine le même jour : on garde
        aussi la sienne. Tout le reste — membres, suivis, cellules — est reporté
        par le socle.
        """
        journal = []
        if self.followup_enabled and not survivor.followup_enabled:
            survivor.followup_enabled = True
        Account = self.env['church.mobile.user'].sudo().with_context(active_test=False)
        kept = set(Account.search([('church_id', '=', survivor.id)]).mapped('phone_key'))
        twins = Account.search([('church_id', '=', self.id), ('phone_key', 'in', list(kept))])
        if twins:
            journal.append(_("  • %(count)s compte(s) mobile(s) en double retiré(s) : %(names)s",
                             count=len(twins), names=', '.join(twins.mapped('name'))))
            twins.unlink()
        Rotation = self.env['church.cooking.rotation'].sudo()
        days = Rotation.search([('church_id', '=', survivor.id)]).mapped('date')
        clashes = Rotation.search([('church_id', '=', self.id), ('date', 'in', days)])
        if clashes:
            journal.append(_("  • %s rotation(s) de cuisine du même jour retirée(s)", len(clashes)))
            clashes.unlink()
        return journal + super()._merge_absorb_into(survivor)

    # ─── Actions ──────────────────────────────────────────────────────

    def _followup_action(self, name, model, domain=None):
        return {
            'type': 'ir.actions.act_window',
            'name': name,
            'res_model': model,
            'view_mode': 'list,form',
            'domain': [('church_id', '=', self.id)] + (domain or []),
            'context': {'default_church_id': self.id},
        }

    def action_view_members(self):
        return self._followup_action(_('Membres'), 'church.member')

    def action_view_evangelists(self):
        return self._followup_action(_('Évangélistes'), 'church.evangelist')

    def action_view_cells(self):
        return self._followup_action(_('Cellules de prière'), 'church.prayer.cell')

    def action_view_age_groups(self):
        return self._followup_action(_("Groupes d'âge"), 'church.age.group')

    def action_view_active_followups(self):
        return self._followup_action(_('Suivis actifs'), 'church.followup',
                                     [('state', 'in', ACTIVE_FOLLOWUP_STATES)])
