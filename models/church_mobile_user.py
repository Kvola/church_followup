import random
import string
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchMobileUser(models.Model):
    _name = 'church.mobile.user'
    _description = 'Utilisateur mobile'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    phone = fields.Char(string='Numéro de téléphone', required=True, tracking=True, index=True)
    pin = fields.Char(string='PIN', readonly=True, copy=False, groups='church_followup.group_church_manager')
    role = fields.Selection([
        ('manager', 'Responsable des évangélistes'),
        ('evangelist', 'Évangéliste'),
        ('cell_leader', 'Responsable de cellule'),
        ('group_leader', 'Responsable de groupe d\'âge'),
    ], string='Rôle', required=True, tracking=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    active = fields.Boolean(default=True)

    # Link to related records
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste lié')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule liée')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge lié')

    @api.constrains('phone', 'church_id')
    def _check_phone_unique(self):
        for rec in self:
            duplicate = self.search_count([
                ('phone', '=', rec.phone),
                ('church_id', '=', rec.church_id.id),
                ('id', '!=', rec.id),
            ])
            if duplicate:
                raise ValidationError(_('Ce numéro de téléphone est déjà utilisé dans cette église.'))

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('pin'):
                vals['pin'] = self._generate_pin()
        return super().create(vals_list)

    def _generate_pin(self):
        """Génère un PIN unique de 6 chiffres."""
        while True:
            pin = ''.join(random.choices(string.digits, k=6))
            if not self.search_count([('pin', '=', pin)]):
                return pin

    def action_regenerate_pin(self):
        """Régénère le PIN de l'utilisateur."""
        for rec in self:
            rec.pin = rec._generate_pin()

    def get_share_message(self):
        """Retourne le message de partage des credentials."""
        self.ensure_one()
        return _(
            "Bonjour %s,\n\n"
            "Vos identifiants pour l'application de suivi :\n"
            "Téléphone : %s\n"
            "PIN : %s\n\n"
            "Veuillez télécharger l'application et vous connecter."
        ) % (self.name, self.phone, self.pin)
