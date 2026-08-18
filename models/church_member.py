from odoo import api, fields, models, _
from dateutil.relativedelta import relativedelta


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
    ], string='Sexe', required=True)
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
        ('integrated', 'Intégré(e)'),
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

    # Computed followup stats
    followup_count = fields.Integer(compute='_compute_followup_count', string='Suivis')

    @api.depends('name', 'first_name')
    def _compute_display_name_custom(self):
        for rec in self:
            parts = [rec.name or '', rec.first_name or '']
            rec.display_name_custom = ' '.join(p for p in parts if p)

    @api.model_create_multi
    def create(self, vals_list):
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

    def action_view_followups(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Suivis'),
            'res_model': 'church.followup',
            'view_mode': 'list,form',
            'domain': [('member_id', '=', self.id)],
        }
