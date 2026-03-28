import hashlib
import secrets
import string
from odoo import api, fields, models, _
from odoo.exceptions import ValidationError, UserError


class ChurchMobileUser(models.Model):
    _name = 'church.mobile.user'
    _description = 'Utilisateur mobile'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    phone = fields.Char(string='Numéro de téléphone', required=True, tracking=True, index=True)
    pin = fields.Char(string='PIN', readonly=True, copy=False, groups='church_followup.group_church_manager')
    pin_hash = fields.Char(string='PIN Hash', readonly=True, copy=False)
    token = fields.Char(string='Token de session', readonly=True, copy=False, index=True)
    login_attempts = fields.Integer(string='Tentatives de connexion', default=0)
    last_login_attempt = fields.Datetime(string='Dernière tentative')
    role = fields.Selection([
        ('manager', 'Responsable des évangélistes'),
        ('evangelist', 'Évangéliste'),
        ('cell_leader', 'Responsable de cellule'),
        ('group_leader', 'Responsable de groupe d\'âge'),
    ], string='Rôle', required=True, tracking=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    active = fields.Boolean(default=True)

    # Link to related records
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste lié', ondelete='set null')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule liée', ondelete='set null')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge lié', ondelete='set null')

    _sql_constraints = [
        ('unique_phone_church', 'UNIQUE(phone, church_id)',
         'Ce numéro de téléphone est déjà utilisé dans cette église.'),
    ]

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('pin'):
                pin = self._generate_pin()
                vals['pin'] = pin
                vals['pin_hash'] = self._hash_pin(pin)
            elif not vals.get('pin_hash'):
                vals['pin_hash'] = self._hash_pin(vals['pin'])
        return super().create(vals_list)

    @staticmethod
    def _hash_pin(pin):
        """Hash a PIN using SHA-256."""
        return hashlib.sha256(pin.encode()).hexdigest()

    def verify_pin(self, pin):
        """Verify a PIN against the stored hash."""
        self.ensure_one()
        # Support both hashed and legacy plaintext PINs
        if self.pin_hash:
            return self._hash_pin(pin) == self.pin_hash
        # Fallback for legacy records without hash
        return self.pin == pin

    def _generate_pin(self):
        """Génère un PIN unique de 6 chiffres (cryptographiquement sûr)."""
        for _ in range(100):
            pin = ''.join(secrets.choice(string.digits) for _ in range(6))
            if not self.search_count([('pin', '=', pin)]):
                return pin
        raise UserError(_('Impossible de générer un PIN unique. Contactez un administrateur.'))

    def action_regenerate_pin(self):
        """Régénère le PIN de l'utilisateur."""
        for rec in self:
            pin = rec._generate_pin()
            rec.write({
                'pin': pin,
                'pin_hash': self._hash_pin(pin),
                'token': False,  # Invalidate active session
            })

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

    def action_share_credentials(self):
        """Affiche les identifiants dans une notification pour copier/partager."""
        self.ensure_one()
        message = self.get_share_message()
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Identifiants de %s') % self.name,
                'message': _('Téléphone : %s — PIN : %s') % (self.phone, self.pin),
                'type': 'info',
                'sticky': True,
            },
        }
