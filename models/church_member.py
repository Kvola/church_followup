import re
import unicodedata

from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError
from dateutil.relativedelta import relativedelta

from .church_tools import (
    DEFAULT_FOLLOWUP_WEEKS, FOLLOWUP_ORIGINS, MAX_PROPOSED_WEEKS, check_same_church, check_weeks,
)


#: Qui est la personne, une fois pour toutes — à ne pas confondre avec son
#: statut (`member_type`), qui suit le parcours : un ancien membre qu'on
#: reprend en suivi reste un ancien membre « en suivi ».
PERSON_PROFILES = [
    ('new', 'Nouvelle personne'),
    ('old_member', 'Ancien membre'),
]


def name_tokens(*parts):
    """Les mots d'un nom, sans accents ni casse : « KONAN Aya » = « Aya Konan »."""
    text = unicodedata.normalize('NFKD', ' '.join(p or '' for p in parts))
    text = ''.join(c for c in text if not unicodedata.combining(c)).lower()
    return [t for t in re.sub(r'[^0-9a-z]+', ' ', text).split() if t]


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
    phone_e164 = fields.Char(
        string='Numéro international', compute='_compute_phone_e164', store=True, index=True,
        help="Le numéro normalisé : c'est lui qui reconnaît une personne déjà enregistrée.")
    name_key = fields.Char(
        string='Clé du nom', compute='_compute_name_key', store=True, index=True,
        help="Nom et prénoms sans accents ni casse, mots triés : « KONAN Aya » = « Aya Konan ».")
    person_profile = fields.Selection(
        PERSON_PROFILES, string='Profil', required=True, default='new', tracking=True, index=True,
        help="Nouvelle personne (venue à la foi, à l'église depuis peu) ou ancien membre (déjà de "
             "l'église, qu'on reprend en suivi). Le profil ne change pas avec le parcours.")
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
    church_id = fields.Many2one('equipment.church', string='Église', required=True, ondelete='restrict', tracking=True)

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
        ('new', 'À attribuer'),
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
        if 'person_profile' in vals:
            # Le profil décide de qui suit (évangéliste ou cellule) : il ne change pas
            # sous un suivi en cours, qui deviendrait incohérent.
            for rec in self.filtered(lambda m: m.person_profile != vals['person_profile']):
                if rec.followup_ids.filtered(lambda f: f.state in ('in_progress', 'extended')):
                    raise UserError(_(
                        "Le profil de %s ne peut pas changer pendant son suivi : terminez ou "
                        "interrompez d'abord le suivi en cours.") % rec.display_name_custom)
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

    @api.depends('phone')
    def _compute_phone_e164(self):
        Otp = self.env['otp.code'].sudo()
        for rec in self:
            try:
                rec.phone_e164 = Otp._norm_phone(rec.phone) if rec.phone else False
            except ValidationError:
                rec.phone_e164 = False

    @api.depends('name', 'first_name')
    def _compute_name_key(self):
        for rec in self:
            rec.name_key = ' '.join(sorted(name_tokens(rec.name, rec.first_name))) or False

    @api.model
    def _find_same_person(self, church, name, first_name, phone=None, date_of_birth=None, pool=None):
        """La personne déjà enregistrée dans cette église, s'il y en a une.

        Rend (membre, raison, ambiguë) :
        - même numéro ET au moins un mot du nom en commun : la même personne
          (un numéro partagé en famille ne confond pas la mère et l'enfant) ;
        - sinon même nom complet (mots dans n'importe quel ordre), sans numéro
          ni date de naissance qui se contredisent ;
        - plusieurs homonymes possibles : `ambiguë`, rien n'est rapproché.

        `pool` : les membres de l'église déjà chargés (imports en lot).
        """
        tokens = name_tokens(name, first_name)
        key = ' '.join(sorted(tokens))
        e164 = False
        if phone:
            try:
                e164 = self.env['otp.code'].sudo()._norm_phone(phone)
            except ValidationError:
                e164 = False
        if pool is None:
            domain = [('church_id', '=', church.id)]
            criteria = [('name_key', '=', key)] + ([('phone_e164', '=', e164)] if e164 else [])
            domain += ['|'] * (len(criteria) - 1) + criteria
            pool = self.sudo().with_context(active_test=False).search(domain)
        if e164:
            same_phone = pool.filtered(lambda m: m.phone_e164 == e164
                                       and set(name_tokens(m.name, m.first_name)) & set(tokens))
            if same_phone:
                return same_phone[:1], 'phone', len(same_phone) > 1
        same_name = pool.filtered(lambda m: m.name_key == key
                                  and not (e164 and m.phone_e164 and m.phone_e164 != e164)
                                  and not (date_of_birth and m.date_of_birth and m.date_of_birth != date_of_birth))
        if len(same_name) > 1:
            return same_name[:1], 'name', True
        return same_name, ('name' if same_name else None), False

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
            # Enregistré comme ancien membre : c'est aussi son profil.
            if vals.get('member_type') == 'old_member' and not vals.get('person_profile'):
                vals['person_profile'] = 'old_member'
        records = super().create(vals_list)
        records._ensure_partner()
        records.church_id._enable_followup()
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
