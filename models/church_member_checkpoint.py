from dateutil.relativedelta import relativedelta

from odoo import api, fields, models, _
from odoo.exceptions import UserError

from .church_tools import check_same_church

MILESTONES = [('3m', 'À 3 mois'), ('6m', 'À 6 mois')]
MILESTONE_MONTHS = {'3m': 3, '6m': 6}
CATCHUP_MONTHS = 1


class ChurchMemberCheckpoint(models.Model):
    """Point de contrôle après l'intégration : la personne est-elle restée ?

    Deux jalons, à 3 et 6 mois. Un contrôle défavorable alerte le responsable et
    planifie un rattrapage du même jalon un mois plus tard ; deux défavorables
    de suite proposent de rouvrir un suivi. Les deux jalons satisfaits, la
    personne devient « Fidèle affermi(e) ».
    """
    _name = 'church.member.checkpoint'
    _description = "Point de contrôle après l'intégration"
    _inherit = ['mail.thread']
    _order = 'due_date, id'

    member_id = fields.Many2one('church.member', string='Personne', required=True,
                                ondelete='cascade', index=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    prayer_cell_id = fields.Many2one(related='member_id.prayer_cell_id', string='Cellule', store=True)
    milestone = fields.Selection(MILESTONES, string='Jalon', required=True)
    is_catchup = fields.Boolean(string='Rattrapage', readonly=True)
    due_date = fields.Date(string='Prévu le', required=True)
    state = fields.Selection([
        ('planned', 'À faire'),
        ('done', 'Fait'),
        ('cancelled', 'Annulé'),
    ], string='État', default='planned', required=True, tracking=True)
    result = fields.Selection([
        ('favorable', 'Favorable — la personne tient'),
        ('unfavorable', 'Défavorable — la personne ne vient plus'),
    ], string='Résultat', tracking=True)
    done_date = fields.Date(string='Fait le', readonly=True)
    done_by = fields.Char(string='Fait par', readonly=True)
    notes = fields.Text(string='Observations')

    # Ce que le contrôleur a sous les yeux en remplissant le contrôle.
    service_count = fields.Integer(string='Cultes (90 derniers jours)', compute='_compute_presence')
    cell_count = fields.Integer(string='Cellules (90 derniers jours)', compute='_compute_presence')

    @api.constrains('church_id', 'member_id')
    def _check_same_church(self):
        check_same_church(self, ['member_id'])

    @api.depends('member_id')
    def _compute_presence(self):
        since = fields.Date.context_today(self) - relativedelta(days=90)
        Sunday = self.env['church.attendance.sunday'].sudo()
        Cell = self.env['church.attendance.cell'].sudo()
        for rec in self:
            domain = [('member_id', '=', rec.member_id.id), ('present', '=', True), ('date', '>=', since)]
            rec.service_count = Sunday.search_count(domain) if rec.member_id else 0
            rec.cell_count = Cell.search_count(domain) if rec.member_id else 0

    def _compute_display_name(self):
        labels = dict(MILESTONES)
        for rec in self:
            rec.display_name = _('%(member)s — contrôle %(milestone)s%(catchup)s',
                                 member=rec.member_id.display_name,
                                 milestone=labels.get(rec.milestone, '').lower(),
                                 catchup=_(' (rattrapage)') if rec.is_catchup else '')

    # ─── Planification ────────────────────────────────────────────────

    @api.model
    def _plan_after_integration(self, member, integration_date):
        """Planifie les jalons à 3 et 6 mois ; annule ce qui restait d'avant."""
        self.search([('member_id', '=', member.id), ('state', '=', 'planned')]).write(
            {'state': 'cancelled'})
        return self.create([{
            'member_id': member.id,
            'church_id': member.church_id.id,
            'milestone': milestone,
            'due_date': integration_date + relativedelta(months=MILESTONE_MONTHS[milestone]),
        } for milestone, _label in MILESTONES])

    # ─── Résultat ─────────────────────────────────────────────────────

    def action_record(self, result, notes=None, done_by=None):
        """Enregistre le résultat et en tire les conséquences."""
        if result not in ('favorable', 'unfavorable'):
            raise UserError(_('Indiquez si le contrôle est favorable ou défavorable.'))
        for rec in self:
            if rec.state != 'planned':
                raise UserError(_('Ce contrôle a déjà été fait ou annulé.'))
            rec.write({
                'state': 'done',
                'result': result,
                'notes': notes or rec.notes,
                'done_date': fields.Date.context_today(rec),
                'done_by': done_by or self.env.user.name,
            })
            if result == 'favorable':
                rec.member_id._update_establishment()
            else:
                rec._handle_unfavorable()

    def action_record_favorable(self):
        self.action_record('favorable')

    def action_record_unfavorable(self):
        self.action_record('unfavorable')

    def _handle_unfavorable(self):
        self.ensure_one()
        previous = self.search([
            ('member_id', '=', self.member_id.id), ('milestone', '=', self.milestone),
            ('state', '=', 'done'), ('id', '!=', self.id),
        ], order='done_date desc, id desc', limit=1)
        twice = previous.result == 'unfavorable'
        catchup = self.create({
            'member_id': self.member_id.id,
            'church_id': self.church_id.id,
            'milestone': self.milestone,
            'is_catchup': True,
            'due_date': fields.Date.context_today(self) + relativedelta(months=CATCHUP_MONTHS),
        })
        if twice:
            self.member_id.reopen_suggested = True
        self.member_id.message_post(body=_(
            "Contrôle %(milestone)s défavorable. Rattrapage prévu le %(date)s.%(reopen)s",
            milestone=dict(MILESTONES)[self.milestone].lower(),
            date=catchup.due_date.strftime('%d/%m/%Y'),
            reopen=_(" Deuxième contrôle défavorable de suite : rouvrir un suivi est proposé.") if twice else '',
        ))
        self._notify_unfavorable(twice)

    def _notify_unfavorable(self, reopen_suggested):
        """Point d'accroche des alertes (voir church_followup_notify)."""

    # ─── Qui contrôle ─────────────────────────────────────────────────

    def _assessors(self):
        """Le responsable de la cellule de la personne ; à défaut, les responsables de l'église."""
        self.ensure_one()
        Users = self.env['church.mobile.user'].sudo()
        leaders = Users.search([('role', '=', 'cell_leader'), ('active', '=', True),
                                ('prayer_cell_id', '=', self.member_id.prayer_cell_id.id)]) \
            if self.member_id.prayer_cell_id else Users
        return leaders or Users.search([('role', '=', 'manager'), ('active', '=', True),
                                        ('church_id', '=', self.church_id.id)])


class ChurchMember(models.Model):
    _inherit = 'church.member'

    checkpoint_ids = fields.One2many('church.member.checkpoint', 'member_id', string='Points de contrôle')
    established_date = fields.Date(string='Affermi(e) le', readonly=True, tracking=True)
    reopen_suggested = fields.Boolean(
        string='Rouvrir un suivi ?', tracking=True,
        help="Deux contrôles défavorables de suite : rouvrir un suivi est proposé.")

    def write(self, vals):
        res = super().write(vals)
        if vals.get('integration_date'):
            # Une date d'intégration corrigée (saisie après coup) replanifie les
            # jalons encore à faire ; un rattrapage garde sa propre échéance.
            for rec in self:
                for checkpoint in rec.checkpoint_ids.filtered(
                        lambda c: c.state == 'planned' and not c.is_catchup):
                    checkpoint.due_date = rec.integration_date + relativedelta(
                        months=MILESTONE_MONTHS[checkpoint.milestone])
        return res

    def _update_establishment(self):
        """Appelé après un contrôle favorable : il lève la proposition de rouvrir
        un suivi ; les deux jalons satisfaits, la personne est affermie."""
        for rec in self:
            vals = {'reopen_suggested': False}
            done = rec.checkpoint_ids.filtered(lambda c: c.state == 'done' and c.result == 'favorable')
            if {'3m', '6m'} <= set(done.mapped('milestone')) and rec.member_type == 'integrated':
                vals.update(member_type='established', established_date=fields.Date.context_today(rec))
            rec.write(vals)


class ChurchFollowup(models.Model):
    _inherit = 'church.followup'

    def action_integrate(self):
        res = super().action_integrate()
        Checkpoint = self.env['church.member.checkpoint'].sudo()
        for rec in self.filtered(lambda f: f.state == 'integrated'):
            Checkpoint._plan_after_integration(rec.member_id, rec.member_id.integration_date
                                               or fields.Date.context_today(rec))
        return res

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        # Un nouveau suivi remplace l'affermissement en cours : ses contrôles tombent.
        members = records.member_id
        self.env['church.member.checkpoint'].sudo().search([
            ('member_id', 'in', members.ids), ('state', '=', 'planned')]).write({'state': 'cancelled'})
        members.filtered('reopen_suggested').write({'reopen_suggested': False})
        return records


class ChurchMobileUser(models.Model):
    _inherit = 'church.mobile.user'

    def _todo_items(self, today=None):
        """Ajoute les contrôles dus (à qui les fait) et, pour les responsables,
        les réouvertures de suivi proposées."""
        items = super()._todo_items(today)
        self.ensure_one()
        if self.role not in ('cell_leader', 'manager', 'super_admin'):
            return items
        today = today or fields.Date.context_today(self)
        domain = [('state', '=', 'planned'), ('due_date', '<=', today)]
        if self.church_id:
            domain.append(('church_id', '=', self.church_id.id))
        if self.role == 'cell_leader':
            domain.append(('prayer_cell_id', '=', self.prayer_cell_id.id))
        labels = dict(MILESTONES)
        for checkpoint in self.env['church.member.checkpoint'].sudo().search(domain):
            if self.role == 'super_admin' or self in checkpoint._assessors():
                items.append({
                    'kind': 'checkpoint_due', 'checkpoint_id': checkpoint.id,
                    'member_id': checkpoint.member_id.id, 'due_date': str(checkpoint.due_date),
                    'title': _('Contrôle %(milestone)s : %(member)s',
                               milestone=labels[checkpoint.milestone].lower(),
                               member=checkpoint.member_id.display_name),
                    'detail': _('La personne vient-elle toujours ? (rattrapage)') if checkpoint.is_catchup
                    else _('La personne vient-elle toujours ?'),
                })
        if self.role in ('manager', 'super_admin'):
            members = self.env['church.member'].sudo().search(
                [('reopen_suggested', '=', True)]
                + ([('church_id', '=', self.church_id.id)] if self.church_id else []))
            for member in members:
                items.append({
                    'kind': 'reopen_suggested', 'member_id': member.id,
                    'title': _('Rouvrir un suivi ? %s') % member.display_name,
                    'detail': _('Deux contrôles défavorables de suite.'),
                })
        return items

    def _todo_labels(self):
        return super()._todo_labels() + [
            ('checkpoint_due', _('%s\u00a0contrôle(s) à faire')),
            ('reopen_suggested', _('%s\u00a0suivi(s) à rouvrir')),
        ]
