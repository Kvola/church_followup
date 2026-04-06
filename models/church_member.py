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

    @api.depends('name', 'first_name')
    def _compute_display_name_custom(self):
        for rec in self:
            parts = [rec.name or '', rec.first_name or '']
            rec.display_name_custom = ' '.join(p for p in parts if p)

    @api.depends('date_of_birth')
    def _compute_age(self):
        today = fields.Date.today()
        for rec in self:
            if rec.date_of_birth:
                rec.age = relativedelta(today, rec.date_of_birth).years
            else:
                rec.age = 0
