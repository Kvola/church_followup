from odoo import api, fields, models, _
from dateutil.relativedelta import relativedelta

from .church_tools import (
    DEFAULT_FOLLOWUP_WEEKS, FOLLOWUP_ORIGINS, MAX_PROPOSED_WEEKS, check_same_church, check_weeks,
)


class ChurchMember(models.Model):
    _name = 'church.member'
    _description = 'Membre / Personne'
    _inherit = ['mail.thread']
    _order = 'name'
    _rec_name = 'display_name_custom'

    # Identité
    name = fields.Char(string='Nom', required=True, tracking=True)
    first_name = fields.Char(string='Prénom(s)', required=True)
    display_name_custom = fields.Char(compute='_compute_display_name_custom', store=True, string='Nom complet')
    phone = fields.Char(string='Téléphone', tracking=True)
    email = fields.Char(string='Email')
    photo = fields.Binary(string='Photo')
    gender = fields.Selection([
        ('male', 'Homme'),
        ('female', 'Femme'),
    ], string='Sexe',
        help="Peut manquer sur une fiche venue d'ailleurs (import, événement) : elle est "
             "alors signalée « à compléter » plutôt que de recevoir un sexe inventé.")
    to_complete = fields.Boolean(
        string='À compléter', compute='_compute_to_complete', store=True,
        help="Une information indispensable manque (le sexe, qui oriente le groupe d'âge).")
    date_of_birth = fields.Date(string='Date de naissance')
    age = fields.Integer(compute='_compute_age', store=True, string='Âge')
    profession = fields.Char(string='Profession')

    # Adresse
    address = fields.Char(string='Lieu d\'habitation')
    district_id = fields.Many2one('church.district', string='Quartier', tracking=True, ondelete='set null')
    city = fields.Char(string='Ville')
    country_id = fields.Many2one('res.country', string='Pays', ondelete='set null')

    # Référentiel des personnes : contact commun (res.partner). Point de jointure
    # partagé qui relie la personne évangélisée à son éventuelle adhésion, ses
    # inscriptions et ses formations ailleurs dans le système.
    partner_id = fields.Many2one(
        'res.partner',
        string='Contact',
        ondelete='set null',
        copy=False,
        index=True,
        tracking=True,
        help="Contact `res.partner` lié — référentiel commun des personnes.",
    )

    # Église
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade', tracking=True)

    # Statut
    marital_status = fields.Selection([
        ('single', 'Célibataire'),
        ('married', 'Marié(e)'),
        ('divorced', 'Divorcé(e)'),
        ('widowed', 'Veuf/Veuve'),
    ], string='Statut matrimonial', default='single')
    salvation_date = fields.Date(string='Date de salut', tracking=True)
    baptism_date = fields.Date(string='Date de baptême')
    integration_date = fields.Date(string='Date d\'intégration')
    member_type = fields.Selection([
        ('new', 'Nouvelle personne'),
        ('in_followup', 'En suivi'),
        ('interrupted', 'Suivi interrompu'),
        ('integrated', 'Intégré(e)'),
        ('established', 'Fidèle affermi(e)'),
        ('old_member', 'Ancien membre'),
    ], string='Type', default='new', tracking=True)

    # Relations
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule de prière', tracking=True, ondelete='set null')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge', tracking=True, ondelete='set null')
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste référent', ondelete='set null')

    # Inviter & Mentor
    invited_by_id = fields.Many2one('church.member', string='Invité(e) par', tracking=True, ondelete='set null',
                                     help='La personne qui a invité ce membre à l\'église')
    mentor_id = fields.Many2one('church.member', string='Mentor', tracking=True, ondelete='set null',
                                 help='Le mentor qui suit ce membre dans sa vie chrétienne')

    # Notes
    notes = fields.Text(string='Notes')
    active = fields.Boolean(default=True)

    # Durée du suivi à venir. Vide : le réglage de l'église s'applique.
    planned_followup_weeks = fields.Integer(
        string='Durée de suivi prévue (semaines)', tracking=True,
        help="Fixée par l'événement d'où vient la personne, ou par un responsable. "
             "Elle est proposée à l'ouverture du suivi, qui peut la modifier.",
    )
    planned_followup_origin = fields.Selection(
        [o for o in FOLLOWUP_ORIGINS if o[0] != 'church'], string='Origine de la durée prévue',
    )
    proposed_followup_weeks = fields.Integer(
        string='Durée proposée (semaines)', compute='_compute_proposed_followup',
    )
    proposed_followup_origin = fields.Selection(
        FOLLOWUP_ORIGINS, string='Origine de la durée proposée', compute='_compute_proposed_followup',
    )
    proposed_followup_label = fields.Char(
        string='Durée proposée', compute='_compute_proposed_followup',
    )

    # Parcours : tous les suivis de la personne, du plus ancien au plus récent.
    followup_ids = fields.One2many('church.followup', 'member_id', string='Parcours de suivi')
    last_followup_id = fields.Many2one('church.followup', string='Dernier suivi',
                                       compute='_compute_last_followup')

    # Computed followup stats
    followup_count = fields.Integer(compute='_compute_followup_count', string='Suivis')

    @api.constrains('church_id', 'district_id', 'prayer_cell_id', 'age_group_id', 'evangelist_id', 'invited_by_id', 'mentor_id')
    def _check_same_church(self):
        check_same_church(self, ['district_id', 'prayer_cell_id', 'age_group_id', 'evangelist_id', 'invited_by_id', 'mentor_id'])

    @api.constrains('planned_followup_weeks')
    def _check_planned_followup_weeks(self):
        check_weeks(self, 'planned_followup_weeks', MAX_PROPOSED_WEEKS, allow_empty=True)

    @api.depends('planned_followup_weeks', 'planned_followup_origin', 'church_id.default_followup_weeks')
    def _compute_proposed_followup(self):
        origins = dict(FOLLOWUP_ORIGINS)
        for rec in self:
            if rec.planned_followup_weeks:
                rec.proposed_followup_weeks = rec.planned_followup_weeks
                rec.proposed_followup_origin = rec.planned_followup_origin or 'manual'
            else:
                rec.proposed_followup_weeks = rec.church_id.default_followup_weeks or DEFAULT_FOLLOWUP_WEEKS
                rec.proposed_followup_origin = 'church'
            rec.proposed_followup_label = '%s semaines — %s' % (
                rec.proposed_followup_weeks, rec._followup_origin_description())

    def _followup_origin_description(self):
        """Libellé de l'origine de la durée proposée ; `event_evangelization` y ajoute l'événement."""
        self.ensure_one()
        return dict(FOLLOWUP_ORIGINS).get(self.proposed_followup_origin, '')

    def write(self, vals):
        # Une durée saisie à la main par un responsable devient « son choix ».
        if 'planned_followup_weeks' in vals and 'planned_followup_origin' not in vals:
            vals = dict(vals, planned_followup_origin='manual' if vals['planned_followup_weeks'] else False)
        return super().write(vals)

    def action_open_followup_wizard(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Ouvrir un suivi'),
            'res_model': 'church.followup.assign',
            'view_mode': 'form',
            'target': 'new',
            'context': {'default_member_ids': self.ids},
        }

    @api.depends('gender')
    def _compute_to_complete(self):
        for rec in self:
            rec.to_complete = not rec.gender

    @api.depends('name', 'first_name')
    def _compute_display_name_custom(self):
        for rec in self:
            parts = [rec.name or '', rec.first_name or '']
            rec.display_name_custom = ' '.join(p for p in parts if p)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('planned_followup_weeks') and not vals.get('planned_followup_origin'):
                vals['planned_followup_origin'] = 'manual'
        records = super().create(vals_list)
        records._ensure_partner()
        return records

    def _ensure_partner(self):
        """Relie chaque personne évangélisée à un contact `res.partner`.

        Rapproche d'un contact existant par e-mail exact (converge vers le contact
        d'un membre/participant déjà connu), sinon par téléphone, sinon crée une
        fiche. Recherche/création en sudo (référentiel commun). Idempotent.
        """
        Partner = self.env['res.partner'].sudo()
        for rec in self:
            if rec.partner_id:
                continue
            partner = Partner.browse()
            email = (rec.email or '').strip()
            phone = (rec.phone or '').strip()
            if email:
                partner = Partner.search([('email', '=ilike', email)], limit=1)
            if not partner and phone:
                partner = Partner.search([('phone', '=', phone)], limit=1)
            if not partner:
                partner = Partner.create({
                    'name': rec.display_name_custom or rec.name,
                    'email': email or False,
                    'phone': phone or False,
                    'city': rec.city or False,
                    'country_id': rec.country_id.id or False,
                })
            rec.partner_id = partner.id

    @api.depends('followup_ids')
    def _compute_last_followup(self):
        for rec in self:
            rec.last_followup_id = rec.followup_ids.sorted(lambda f: (f.start_date, f.id))[-1:]

    def action_resume_followup(self):
        """Reprendre le suivi d'une personne dont le suivi a été interrompu."""
        return self.action_open_followup_wizard()

    def _compute_followup_count(self):
        followup_model = self.env['church.followup']
        for rec in self:
            rec.followup_count = followup_model.search_count([('member_id', '=', rec.id)])

    @api.depends('date_of_birth')
    def _compute_age(self):
        today = fields.Date.today()
        for rec in self:
            if rec.date_of_birth:
                rec.age = relativedelta(today, rec.date_of_birth).years
            else:
                rec.age = 0

    @api.model
    def _cron_refresh_age(self):
        """L'âge est stocké : le recalculer pour ceux dont l'anniversaire l'a changé."""
        self.env.cr.execute("""
            SELECT id FROM church_member
             WHERE date_of_birth IS NOT NULL
               AND age IS DISTINCT FROM date_part('year', age(CURRENT_DATE, date_of_birth))::int
        """)
        members = self.with_context(active_test=False).browse(r[0] for r in self.env.cr.fetchall())
        if members:
            self.env.add_to_compute(self._fields['age'], members)
            members.flush_recordset(['age'])

    def action_view_followups(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Suivis'),
            'res_model': 'church.followup',
            'view_mode': 'list,form',
            'domain': [('member_id', '=', self.id)],
        }
