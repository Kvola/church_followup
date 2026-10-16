import hashlib
import hmac
import re
import secrets
import string
from datetime import timedelta
from urllib.parse import quote

from passlib.context import CryptContext

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

from .church_tools import check_same_church

# Même famille d'algorithme que les mots de passe Odoo : salé et lent, donc un
# PIN de 6 chiffres ne se retrouve plus en une seconde à partir de son empreinte.
_PIN_CRYPT = CryptContext(['pbkdf2_sha512'], pbkdf2_sha512__rounds=25000)

SESSION_DAYS = 60


def phone_key(phone):
    """Le numéro réduit à ses chiffres : « +225 07 00 » et « +2250700 » se confondent."""
    return re.sub(r'\D', '', phone or '')


def _token_digest(token):
    # Le jeton est un aléa de 256 bits : une empreinte rapide suffit à le protéger.
    return hashlib.sha256(token.encode()).hexdigest()


class ChurchMobileUser(models.Model):
    _name = 'church.mobile.user'
    _description = 'Utilisateur mobile'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    phone = fields.Char(string='Numéro de téléphone', required=True, tracking=True)
    phone_key = fields.Char(
        string='Numéro (chiffres)', compute='_compute_phone_key', store=True, index=True,
        help="Le numéro réduit à ses chiffres : c'est lui qui sert à se connecter.",
    )
    # Ni le PIN ni le jeton ne sont conservés en clair ; leurs empreintes ne sont
    # lisibles que par l'administrateur technique.
    phone_e164 = fields.Char(
        string='Numéro international', compute='_compute_phone_e164', store=True, index=True,
        help="Le numéro au format international (+225…), celui où partent les codes et les "
             "messages. Le zéro initial ivoirien est conservé.",
    )
    pin_hash = fields.Char(readonly=True, copy=False, groups='base.group_system')
    pin_set_date = fields.Datetime(
        string='PIN communiqué le', readonly=True, copy=False,
        help="Date du dernier PIN généré. Vide : aucun PIN n'a encore été communiqué.",
    )
    token_hash = fields.Char(readonly=True, copy=False, index=True, groups='base.group_system')
    token_expiry = fields.Datetime(string='Session valable jusqu\'au', readonly=True, copy=False)
    last_login = fields.Datetime(string='Dernière connexion', readonly=True, copy=False)
    role = fields.Selection([
        ('super_admin', 'Super Administrateur'),
        ('manager', 'Responsable des évangélistes'),
        ('evangelist', 'Évangéliste'),
        ('cell_leader', 'Responsable de cellule'),
        ('group_leader', 'Responsable de groupe d\'âge'),
    ], string='Rôle', required=True, tracking=True)
    church_id = fields.Many2one('equipment.church', string='Église', ondelete='restrict',
                                help='Optionnel pour le Super Administrateur (accès multi-église)')
    active = fields.Boolean(default=True)

    # Link to related records
    evangelist_id = fields.Many2one('church.evangelist', string='Évangéliste lié', ondelete='set null')
    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule liée', ondelete='set null')
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge lié', ondelete='set null')

    _phone_church_uniq = models.Constraint(
        'UNIQUE(phone_key, church_id)',
        'Ce numéro de téléphone est déjà utilisé dans cette église.',
    )

    @api.depends('phone')
    def _compute_phone_key(self):
        for rec in self:
            rec.phone_key = phone_key(rec.phone)

    @api.depends('phone')
    def _compute_phone_e164(self):
        # Le normaliseur partagé d'otp_auth : celui-là même qui reconnaîtra le
        # numéro saisi à la connexion. Deux normaliseurs finiraient par diverger.
        Otp = self.env['otp.code']
        for rec in self:
            try:
                rec.phone_e164 = Otp._norm_phone(rec.phone) if rec.phone else False
            except ValidationError:
                rec.phone_e164 = False

    @api.constrains('phone')
    def _check_phone(self):
        for rec in self:
            if len(rec.phone_key or '') < 8:
                raise ValidationError(_('Le numéro « %s » est trop court pour servir à se connecter.') % rec.phone)

    @api.constrains('church_id', 'evangelist_id', 'prayer_cell_id', 'age_group_id')
    def _check_same_church(self):
        check_same_church(self, ['evangelist_id', 'prayer_cell_id', 'age_group_id'])

    @api.constrains('role', 'church_id')
    def _check_church_required(self):
        """church_id is required for all roles except super_admin."""
        for rec in self:
            if rec.role != 'super_admin' and not rec.church_id:
                raise ValidationError(_('L\'église est obligatoire pour le rôle %s.') % rec.get_role_label())

    def get_role_label(self):
        """Return the human-readable role label."""
        return dict(self._fields['role'].selection).get(self.role, self.role)

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records.church_id._enable_followup()
        return records

    def write(self, vals):
        # Un compte désactivé, ou dont le rôle change, perd sa session en cours.
        if 'active' in vals and not vals['active'] or 'role' in vals:
            vals = dict(vals, token_hash=False, token_expiry=False)
        return super().write(vals)

    # ─── PIN ──────────────────────────────────────────────────────────

    def _issue_pin(self):
        """Tire un nouveau PIN, n'en garde que l'empreinte et le rend en clair.

        C'est la seule occasion de le lire : l'appelant doit le transmettre
        aussitôt. La session en cours est fermée.
        """
        self.ensure_one()
        pin = ''.join(secrets.choice(string.digits) for _ in range(6))
        self.sudo().write({
            'pin_hash': _PIN_CRYPT.hash(pin),
            'pin_set_date': fields.Datetime.now(),
            'token_hash': False,
            'token_expiry': False,
        })
        return pin

    def verify_pin(self, pin):
        self.ensure_one()
        stored = self.sudo().pin_hash
        if not stored or not pin:
            return False
        try:
            return _PIN_CRYPT.verify(pin, stored)
        except (ValueError, TypeError):
            return False

    def get_share_message(self, pin):
        self.ensure_one()
        return _(
            "Bonjour %(name)s,\n\n"
            "Vos identifiants pour l'application de suivi :\n"
            "Téléphone : %(phone)s\n"
            "PIN : %(pin)s\n\n"
            "Veuillez télécharger l'application et vous connecter.",
            name=self.name, phone=self.phone, pin=pin,
        )

    def action_regenerate_pin(self):
        """Génère un nouveau PIN et l'affiche une seule fois, prêt à partager."""
        self.ensure_one()
        pin = self._issue_pin()
        wizard = self.env['church.mobile.user.credentials'].create({
            'mobile_user_id': self.id,
            'pin': pin,
            'message': self.get_share_message(pin),
        })
        return {
            'type': 'ir.actions.act_window',
            'name': _('Identifiants de %s') % self.name,
            'res_model': 'church.mobile.user.credentials',
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'new',
        }

    # ─── Session ──────────────────────────────────────────────────────

    def _open_session(self):
        """Ouvre une session et rend le jeton en clair (seule copie : celle de l'app)."""
        self.ensure_one()
        token = secrets.token_hex(32)
        now = fields.Datetime.now()
        self.sudo().write({
            'token_hash': _token_digest(token),
            'token_expiry': now + timedelta(days=SESSION_DAYS),
            'last_login': now,
        })
        return token

    @api.model
    def _from_session(self, user_id, token):
        """Le compte actif dont ``token`` est la session en cours, sinon un recordset vide."""
        try:
            user = self.sudo().browse(int(user_id))
        except (TypeError, ValueError):
            return self.browse()
        if not token or not isinstance(token, str) or not user.exists() or not user.active:
            return self.browse()
        if not user.token_hash or not user.token_expiry or user.token_expiry < fields.Datetime.now():
            return self.browse()
        if not hmac.compare_digest(user.token_hash, _token_digest(token)):
            return self.browse()
        return user

    def action_close_session(self):
        self.sudo().write({'token_hash': False, 'token_expiry': False})


class ChurchMobileUserCredentials(models.TransientModel):
    """Affiche un PIN fraîchement généré, une seule fois, avec son message de partage."""
    _name = 'church.mobile.user.credentials'
    _description = 'Identifiants à transmettre'

    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte', required=True, readonly=True)
    phone = fields.Char(related='mobile_user_id.phone', string='Téléphone')
    pin = fields.Char(string='PIN', readonly=True)
    message = fields.Text(string='Message à transmettre', readonly=True)
    whatsapp_url = fields.Char(string='WhatsApp', compute='_compute_whatsapp_url')

    @api.depends('message', 'mobile_user_id.phone_key')
    def _compute_whatsapp_url(self):
        for rec in self:
            rec.whatsapp_url = 'https://wa.me/%s?text=%s' % (
                rec.mobile_user_id.phone_key or '', quote(rec.message or ''))
