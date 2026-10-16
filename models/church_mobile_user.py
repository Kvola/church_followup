import logging
import re
from urllib.parse import quote

from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError

from .church_tools import OTP_SCOPE, check_same_church

_logger = logging.getLogger(__name__)

SESSION_DAYS = 90


def phone_key(phone):
    """Le numéro réduit à ses chiffres : « +225 07 00 » et « +2250700 » se confondent."""
    return re.sub(r'\D', '', phone or '')


class ChurchMobileUser(models.Model):
    _name = 'church.mobile.user'
    _description = 'Utilisateur mobile'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    # Obligatoire pour tous, sauf un administrateur du back-office qui se
    # connecte par son e-mail (voir _check_contact).
    phone = fields.Char(string='Numéro de téléphone', tracking=True)
    phone_key = fields.Char(
        string='Numéro (chiffres)', compute='_compute_phone_key', store=True, index=True,
        help="Le numéro réduit à ses chiffres : c'est lui qui sert à se connecter.",
    )
    phone_e164 = fields.Char(
        string='Numéro international', compute='_compute_phone_e164', store=True, index=True,
        help="Le numéro au format international (+225…), celui où partent les codes et les "
             "messages. Le zéro initial ivoirien est conservé.",
    )
    email = fields.Char(
        string='E-mail', tracking=True,
        help="Facultatif. Le code de connexion y part aussi : utile quand ni WhatsApp "
             "ni le SMS n'arrivent.",
    )
    user_id = fields.Many2one(
        'res.users', string='Utilisateur Odoo', readonly=True, copy=False, ondelete='set null',
        help="Renseigné quand le compte a été ouvert par un administrateur du suivi dans "
             "Odoo, à sa première connexion dans l'application.",
    )
    partner_id = fields.Many2one(
        'res.partner', string='Contact', readonly=True, copy=False, ondelete='restrict',
        help="La personne derrière le compte ; ses sessions d'application y sont rattachées.",
    )
    session_ids = fields.One2many('church.mobile.session', 'mobile_user_id', string='Sessions')
    open_session_count = fields.Integer(string='Sessions ouvertes', compute='_compute_open_session_count')
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
    role_display = fields.Char(
        string='Fonction', compute='_compute_role_display',
        help="« Pasteur » ou « Missionnaire » pour un compte de l'annuaire des pasteurs ; "
             "sinon le rôle.")
    pastor_id = fields.Many2one(
        'equipment.pastor', string='Pasteur', readonly=True, copy=False, ondelete='set null',
        help="Le compte d'un pasteur de l'annuaire, ouvert à sa première connexion. Il suit "
             "l'église du pasteur : après une mutation, il entre dans la nouvelle.")
    age_group_id = fields.Many2one('church.age.group', string='Groupe d\'âge lié', ondelete='set null')

    _phone_church_uniq = models.Constraint(
        'UNIQUE(phone_key, church_id)',
        'Ce numéro de téléphone est déjà utilisé dans cette église.',
    )

    @api.depends('session_ids.revoked', 'session_ids.expires_at')
    def _compute_open_session_count(self):
        now = fields.Datetime.now()
        for rec in self:
            rec.open_session_count = len(rec.session_ids.filtered(
                lambda s: not s.revoked and s.expires_at > now))

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
            if rec.phone and (len(rec.phone_key or '') < 8 or not rec.phone_e164):
                raise ValidationError(_('Le numéro « %s » ne peut pas servir à se connecter.') % rec.phone)

    @api.constrains('phone', 'email', 'role')
    def _check_contact(self):
        for rec in self:
            if not rec.phone and not (rec.role == 'super_admin' and rec.email):
                raise ValidationError(_("Le numéro de téléphone de « %s » est obligatoire : "
                                        "c'est là que part son code de connexion.") % rec.name)

    @api.constrains('email')
    def _check_email(self):
        for rec in self:
            if rec.email and not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', rec.email.strip()):
                raise ValidationError(_("L'adresse « %s » n'est pas une adresse e-mail.") % rec.email)

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

    @api.depends('role', 'pastor_id.function')
    def _compute_role_display(self):
        for rec in self:
            rec.role_display = rec._role_display_label()

    def _role_display_label(self):
        """Ce que la personne lit : « Pasteur » (ou « Missionnaire ») plutôt que
        le rôle technique. Les droits restent ceux du rôle, ici responsable."""
        self.ensure_one()
        if self.pastor_id and self.role != 'super_admin':
            return dict(self.pastor_id._fields['function'].selection).get(
                self.pastor_id.function, _('Pasteur'))
        return self.get_role_label()

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('email'):
                vals['email'] = vals['email'].strip().lower()
        records = super().create(vals_list)
        records.church_id._enable_followup()
        return records

    def write(self, vals):
        if vals.get('email'):
            vals = dict(vals, email=vals['email'].strip().lower())
        res = super().write(vals)
        # Un compte désactivé, ou dont le rôle change, perd ses sessions en cours.
        if 'active' in vals and not vals['active'] or 'role' in vals:
            self._revoke_sessions()
        return res

    # ─── Identité et sessions ─────────────────────────────────────────

    @api.model
    def _accounts_for_identifier(self, identifier, kind):
        """Les comptes actifs d'une personne : même numéro, ou même adresse.

        Un même numéro peut servir dans plusieurs églises (un évangéliste aussi
        responsable ailleurs). La session s'ouvre sur le PREMIER compte rendu :
        on entre dans son église, et seul l'administrateur en change.
        """
        field = 'email' if kind == 'email' else 'phone_e164'
        accounts = self.sudo().search([(field, '=', identifier), ('active', '=', True)],
                                      order='last_login desc, id')
        # Le compte d'un pasteur parti de l'annuaire ne rouvre plus rien.
        accounts = accounts.filtered(lambda a: not a.pastor_id or a.pastor_id.active)
        # On entre dans SON église : l'administrateur d'abord (lui seul change
        # d'église), puis l'église où la personne est pasteur.
        pastor_account = self._pastor_account(identifier, kind, accounts)
        if pastor_account:
            accounts = pastor_account | (accounts - pastor_account)
        admin = accounts.filtered(lambda a: a.role == 'super_admin')[:1]
        if admin:
            accounts = admin | (accounts - admin)
        return accounts or self._back_office_account(identifier, kind)

    @api.model
    def _pastor_account(self, identifier, kind, accounts):
        """Le compte d'un pasteur de l'annuaire, dans l'église où il est affecté.

        Le pasteur n'a pas à se faire créer un compte : son numéro (ou son
        adresse) dans l'annuaire le prouve. Il entre comme responsable de son
        église ; muté, il entre dans la nouvelle à la connexion suivante.
        """
        Pastor = self.env['equipment.pastor'].sudo()
        if kind == 'email':
            domain = [('email', '=ilike', identifier)]
        else:
            domain = [('phone_intl', '=', identifier.lstrip('+'))]
        pastor = Pastor.search(domain + [('active', '=', True), ('church_id', '!=', False)], limit=1)
        if not pastor:
            return self.browse()
        church = pastor.church_id
        account = accounts.filtered(lambda a: a.church_id == church)[:1]
        if not account:
            account = self.sudo().with_context(active_test=False).search(
                [('pastor_id', '=', pastor.id)], limit=1)
            if account and not account.active:
                return self.browse()  # désactivé exprès : on ne le rouvre pas en silence
        vals = {}
        if account:
            if account.church_id != church:
                # Muté : le compte suit, sans ses rattachements de l'ancienne église.
                vals.update(church_id=church.id, evangelist_id=False,
                            prayer_cell_id=False, age_group_id=False)
            if account.role not in ('super_admin', 'manager'):
                vals['role'] = 'manager'
            if account.pastor_id != pastor:
                vals['pastor_id'] = pastor.id
            if vals:
                account.sudo().write(vals)
                church._enable_followup()
            return account
        phone = identifier if kind == 'phone' else (
            '+%s' % pastor.phone_intl if pastor.phone_intl else pastor.phone)
        email = identifier if kind == 'email' else (pastor.email or '').strip().lower()
        if not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email or ''):
            email = False  # une adresse mal saisie dans l'annuaire ne bloque pas l'entrée
        account = self.sudo().create({
            'name': pastor.name, 'phone': phone,
            'email': email,
            'role': 'manager', 'church_id': church.id, 'pastor_id': pastor.id,
        })
        _logger.info("Compte mobile ouvert pour le pasteur %s (%s)", pastor.name, church.name)
        return account

    @api.model
    def _back_office_account(self, identifier, kind):
        """Le compte d'un administrateur du suivi dans Odoo, ouvert à la demande.

        Celui qui administre l'église dans Odoo n'a pas à se créer d'abord un
        compte mobile pour entrer dans l'application : son utilisateur Odoo —
        même adresse ou même numéro — le prouve déjà. Seul le groupe
        « Super Administrateur Église » ouvre cette porte, et le rôle donné est
        celui-là : rien de plus que ce qu'il a déjà dans Odoo.
        """
        Otp = self.env['otp.code'].sudo()
        # L'appartenance au groupe est la seule porte : pas `share`, qui dépend
        # d'autres groupes et écartait un administrateur du seul suivi.
        users = self.env['res.users'].sudo().search([('active', '=', True)])
        user = self.env['res.users']
        for candidate in users.filtered(lambda u: u.has_group('church_followup.group_church_admin')):
            if kind == 'email':
                emails = {(e or '').strip().lower() for e in (candidate.email, candidate.login)}
                if identifier in emails:
                    user = candidate
                    break
            else:
                for raw in (candidate.partner_id.phone, getattr(candidate.partner_id, 'mobile', False)):
                    try:
                        if raw and Otp._norm_phone(raw) == identifier:
                            user = candidate
                            break
                    except ValidationError:
                        continue
                if user:
                    break
        if not user:
            return self.browse()
        account = self.sudo().with_context(active_test=False).search([('user_id', '=', user.id)], limit=1)
        if account:
            if not account.active:
                return self.browse()  # désactivé exprès : on ne le rouvre pas en silence
            return account
        email = (user.email or (user.login if '@' in (user.login or '') else '') or '').strip().lower()
        phone = identifier if kind == 'phone' else (user.partner_id.phone or False)
        account = self.sudo().create({
            'name': user.name, 'phone': phone or False, 'email': email or False,
            'role': 'super_admin', 'user_id': user.id, 'partner_id': user.partner_id.id,
        })
        _logger.info("Compte mobile super administrateur ouvert pour l'utilisateur Odoo %s", user.login)
        return account

    def _sibling_accounts(self):
        """Les autres comptes actifs de la même personne."""
        self.ensure_one()
        # Un champ vide ne rapproche personne : sans numéro, seule l'adresse compte.
        keys = [(f, self[f]) for f in ('phone_e164', 'email') if self[f]]
        domain = ['|'] * (len(keys) - 1) + [(f, '=', v) for f, v in keys]
        return self.sudo().search([('active', '=', True)] + domain, order='church_id, id') | self

    def _ensure_partner(self):
        """Le contact de la personne : celui qui porte déjà ce numéro, sinon un nouveau."""
        Partner = self.env['res.partner'].sudo()
        for rec in self.sudo():
            if rec.partner_id:
                continue
            partner = Partner.browse()
            # Une clé vide ne rapproche personne : sans numéro, on cherche par l'adresse.
            if rec.phone_e164:
                partner = Partner.search([('phone', '=', rec.phone_e164)], limit=1)
            elif rec.email:
                partner = Partner.search([('email', '=ilike', rec.email)], limit=1)
            if not partner:
                partner = Partner.create({'name': rec.name, 'phone': rec.phone_e164,
                                          'email': rec.email or False})
            rec.partner_id = partner
        return self.partner_id

    def _open_session(self, device_label=None):
        """Ouvre une session d'application et rend le jeton en clair (seule copie : celle de l'app)."""
        self.ensure_one()
        self._ensure_partner()
        token = self.env['church.mobile.session'].sudo()._issue(
            self.partner_id, device_label=device_label, values={'mobile_user_id': self.id})
        self.sudo().last_login = fields.Datetime.now()
        return token

    def _revoke_sessions(self):
        self.env['church.mobile.session'].sudo().search([
            ('mobile_user_id', 'in', self.ids), ('revoked', '=', False)]).write({'revoked': True})

    def action_close_session(self):
        self._revoke_sessions()

    # ─── Code de connexion ────────────────────────────────────────────

    @api.model
    def _otp_company(self):
        """La société au nom de laquelle partent les codes.

        Twilio (WhatsApp, SMS) se règle par société. La route publique de l'app
        tourne sous l'utilisateur public, le bouton du back-office sous
        l'administrateur : sans société fixée, les deux enverraient au nom de
        deux sociétés différentes, et l'un réussirait quand l'autre échoue.
        """
        public = self.env.ref('base.public_user', raise_if_not_found=False)
        return public.sudo().company_id if public and public.sudo().company_id else self.env.company

    @api.model
    def _issue_login_code(self, identifier, account, force=False):
        """Émet et envoie un code pour cet identifiant (numéro ou adresse)."""
        return self.env['otp.code'].sudo().with_company(self._otp_company())._issue(
            identifier, OTP_SCOPE, phone=account.phone_e164 or None,
            email=account.email or None, force=force)

    def _delivery_report(self, code_record):
        """Par où le code est réellement parti : ce que l'écran ne peut pas dire."""
        self.ensure_one()
        company = self._otp_company().sudo()
        lines = []
        try:
            from odoo.addons.push_notification_hub.services import messaging
        except ImportError:  # pragma: no cover - otp_twilio absent
            messaging = None
        if self.phone_e164:
            if messaging is None:
                lines.append(_("Téléphone : aucun envoi possible (module otp_twilio absent)."))
            else:
                wa = bool((getattr(company, 'otp_twilio_whatsapp_sid', '') or '').strip()) \
                    and messaging.is_configured(company, 'whatsapp')
                sms = messaging.is_configured(company, 'sms')
                relay = self.env['notification.relay'].sudo().search_count(
                    [('source_ref', '=', 'otp.code,%d' % code_record.id)]) \
                    if 'notification.relay' in self.env else 0
                if relay:
                    lines.append(_("Téléphone %s : ni WhatsApp ni SMS n'ont pu partir ; le code attend "
                                   "dans la file du relais humain (application des notificateurs).")
                                 % self.phone_e164)
                elif wa:
                    lines.append(_("Téléphone %s : envoyé par WhatsApp (gabarit approuvé).") % self.phone_e164)
                elif sms:
                    lines.append(_("Téléphone %s : envoyé par SMS.") % self.phone_e164)
                else:
                    lines.append(_("Téléphone %s : rien n'est parti — WhatsApp et SMS ne sont pas "
                                   "réglés pour %s, et le relais humain n'a pas pris le code. "
                                   "Dictez le code ci-dessus.") % (self.phone_e164, company.name))
        if self.email:
            lines.append(_("E-mail %s : envoyé.") % self.email)
        if not lines:
            lines.append(_("Aucun canal : ce compte n'a ni numéro ni adresse."))
        return '\n'.join(lines)

    def action_send_login_code(self):
        """Envoie un code de connexion et dit par où il est parti.

        Le code est aussi AFFICHÉ : si rien n'arrive, l'administrateur peut le
        dicter au téléphone. Il ne vaut que pour ce compte, 10 minutes, une fois.
        """
        self.ensure_one()
        if not self.active:
            raise UserError(_("Ce compte est désactivé : réactivez-le d'abord."))
        identifier = self.phone_e164 or (self.email or '').strip().lower()
        if not identifier:
            raise UserError(_("Ce compte n'a ni numéro ni adresse : impossible d'y envoyer un code."))
        code = self._issue_login_code(identifier, self, force=True)
        record = self.env['otp.code'].sudo()._record_for(identifier, OTP_SCOPE)
        wizard = self.env['church.mobile.user.code'].create({
            'mobile_user_id': self.id,
            'identifier': identifier,
            'code': code,
            'report': self._delivery_report(record),
        })
        return {
            'type': 'ir.actions.act_window',
            'name': _('Code de connexion de %s') % self.name,
            'res_model': 'church.mobile.user.code',
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'new',
        }

    # ─── Invitation ───────────────────────────────────────────────────

    def _app_url(self):
        app = self.env.ref('church_followup.mobile_app_suivi_evangelisation', raise_if_not_found=False)
        return app.sudo().page_url if app else ''

    def get_invitation_message(self):
        """Le message qui invite à installer l'app. Il ne contient aucun secret :
        le code arrive au moment de se connecter, sur le numéro du compte."""
        self.ensure_one()
        return _(
            "Bonjour %(name)s,\n\n"
            "Vous avez un compte %(role)s dans l'application Suivi Évangélisation "
            "(%(church)s).\n"
            "1. Installez l'application : %(url)s\n"
            "2. Saisissez votre numéro %(phone)s\n"
            "3. Recopiez le code reçu par WhatsApp ou SMS.",
            name=self.name, role=self.get_role_label().lower(),
            church=self.church_id.name or _('toutes les églises'),
            url=self._app_url() or '/apps/suivi-evangelisation', phone=self.phone,
        )

    def action_share_invitation(self):
        """Affiche l'invitation, prête à copier ou à envoyer par WhatsApp."""
        self.ensure_one()
        wizard = self.env['church.mobile.user.invite'].create({
            'mobile_user_id': self.id,
            'message': self.get_invitation_message(),
        })
        return {
            'type': 'ir.actions.act_window',
            'name': _('Inviter %s') % self.name,
            'res_model': 'church.mobile.user.invite',
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'new',
        }


class ChurchMobileSession(models.Model):
    """Une session de l'application, sur le socle commun d'otp_auth.

    Jeton haché, expiration, révocation qui garde la trace : rien n'est
    réécrit ici. Le suivi ajoute seulement le compte (l'église, le rôle) que
    la session ouvre.
    """
    _name = 'church.mobile.session'
    _description = "Session de l'application de suivi"
    _inherit = ['api.session.mixin']
    _session_ttl_days = SESSION_DAYS

    mobile_user_id = fields.Many2one(
        'church.mobile.user', string='Compte', required=True, index=True, ondelete='cascade')

    @api.model
    def _resolve_account(self, token):
        """Le compte actif ouvert par ce jeton, sinon un recordset vide."""
        account = self._resolve_session(token).mobile_user_id
        return account if account and account.active else self.env['church.mobile.user']


class ChurchMobileUserInvite(models.TransientModel):
    """L'invitation à installer l'application, prête à partager."""
    _name = 'church.mobile.user.invite'
    _description = "Invitation à l'application"

    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte', required=True, readonly=True)
    phone = fields.Char(related='mobile_user_id.phone', string='Téléphone')
    message = fields.Text(string='Message à transmettre', readonly=True)
    whatsapp_url = fields.Char(string='WhatsApp', compute='_compute_whatsapp_url')

    @api.depends('message', 'mobile_user_id.phone_key')
    def _compute_whatsapp_url(self):
        for rec in self:
            rec.whatsapp_url = 'https://wa.me/%s?text=%s' % (
                rec.mobile_user_id.phone_key or '', quote(rec.message or ''))


class ChurchMobileUserCode(models.TransientModel):
    """Le compte rendu d'un code envoyé depuis le back-office."""
    _name = 'church.mobile.user.code'
    _description = 'Code de connexion envoyé'

    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte', required=True, readonly=True)
    identifier = fields.Char(string='À saisir dans l\'application', readonly=True)
    code = fields.Char(string='Code', readonly=True)
    report = fields.Text(string='Envoi', readonly=True)
