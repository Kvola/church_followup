import functools
import logging

from psycopg2 import IntegrityError

from odoo import fields, http
from odoo.exceptions import AccessDenied, AccessError, UserError, ValidationError
from odoo.http import request

from odoo.addons.otp_auth.tools.client_ip import client_ip

from ..models.church_mobile_user import phone_key
from ..models.church_tools import ACTIVE_FOLLOWUP_STATES

_logger = logging.getLogger(__name__)

# Connexion par code à usage unique (otp_auth). Le code lui-même est limité à
# 5 essais et 10 minutes par le socle ; ces compteurs-ci protègent la porte :
# * demandes par adresse : une machine ne fait pas pleuvoir les SMS ;
# * demandes par identifiant : un numéro ne reçoit pas dix codes d'affilée ;
# * vérifications par adresse : on n'essaie pas numéro après numéro.
OTP_SCOPE = 'church_followup'
OTP_DEBUG_PARAM = 'church_followup.otp_debug_return'
_OTP_LIMITS = {
    'request_ip': (10, 15 * 60, 15 * 60),
    'request_id': (3, 5 * 60, 5 * 60),
    'verify_ip': (20, 15 * 60, 30 * 60),
}
_OTP_SENT = "Si ce numéro ou cette adresse a un compte, un code vient d'y être envoyé."
_OTP_REFUSED = 'Code incorrect ou expiré. Demandez-en un nouveau.'
_TOO_MANY = 'Trop de tentatives. Réessayez dans quelques minutes.'

MANAGERS = ('super_admin', 'manager')
ALL_ROLES = ('super_admin', 'manager', 'evangelist', 'cell_leader', 'group_leader')


class ApiInputError(Exception):
    """Donnée envoyée par l'app invalide : le message est montré tel quel."""


def _error(message, code='error'):
    return {'status': 'error', 'code': code, 'message': message}


def church_endpoint(roles=ALL_ROLES):
    """Garde commune des routes authentifiées.

    Authentifie par jeton, vérifie le rôle, exécute dans un point de reprise et
    traduit toute erreur en réponse lisible : un refus métier (UserError,
    ValidationError) est rendu avec son message, une donnée invalide aussi ;
    seul l'imprévu devient « Erreur interne » et est journalisé.
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(self, **kwargs):
            user = request.env['church.mobile.session'].sudo()._resolve_account(_bearer())
            if not user:
                return _error('Session expirée : veuillez vous reconnecter.', 'auth_required')
            if user.role not in roles:
                return _error('Action non autorisée pour votre rôle.', 'forbidden')
            try:
                with request.env.cr.savepoint():
                    return func(self, user, **kwargs)
            except ApiInputError as e:
                return _error(str(e), 'invalid')
            except (UserError, ValidationError) as e:
                return _error(e.args[0] if e.args else str(e), 'refused')
            except AccessError:
                return _error('Action non autorisée.', 'forbidden')
            except IntegrityError:
                return _error('Cet enregistrement existe déjà.', 'duplicate')
            except Exception:
                _logger.exception("Erreur de l'API église : %s", func.__name__)
                return _error('Erreur interne du serveur.', 'server')
        return wrapper
    return decorator


def _bearer():
    """Le jeton de session, lu dans l'en-tête ``Authorization: Bearer …``."""
    header = request.httprequest.headers.get('Authorization') or ''
    scheme, _sep, token = header.partition(' ')
    return token.strip() if scheme.lower() == 'bearer' and len(token.strip()) >= 32 else ''


def _mask(identifier, kind):
    """« +225 07 •• •• •• 12 » / « a•••@exemple.ci » : de quoi reconnaître, pas de quoi lire."""
    if kind == 'email':
        local, _sep, domain = identifier.partition('@')
        return '%s•••@%s' % (local[:1], domain)
    # « +225 07 •• •• •• 01 » : l'indicatif, l'opérateur, les deux derniers chiffres.
    head = '+225 %s' % identifier[4:6] if identifier.startswith('+225') else identifier[:-8]
    return '%s •• •• •• %s' % (head, identifier[-2:])


# ─── Lecture des paramètres ──────────────────────────────────────────

def _text(kwargs, key, required=False, label=None):
    value = kwargs.get(key)
    if value is None or value is False:
        value = ''
    if not isinstance(value, str):
        value = str(value)
    value = value.strip()
    if required and not value:
        raise ApiInputError('Le champ « %s » est requis.' % (label or key))
    return value


def _int(kwargs, key, required=False, label=None):
    value = kwargs.get(key)
    if value in (None, False, ''):
        if required:
            raise ApiInputError('Le champ « %s » est requis.' % (label or key))
        return None
    if isinstance(value, bool):
        raise ApiInputError('Valeur invalide pour « %s ».' % (label or key))
    try:
        return int(value)
    except (TypeError, ValueError):
        raise ApiInputError('Valeur invalide pour « %s ».' % (label or key))


def _date(kwargs, key, label=None):
    value = kwargs.get(key)
    if value in (None, False, ''):
        return False
    try:
        parsed = fields.Date.to_date(str(value).strip())
    except (TypeError, ValueError):
        parsed = None
    if not parsed:
        raise ApiInputError('Date invalide pour « %s » : format attendu AAAA-MM-JJ.' % (label or key))
    return parsed


def _bool(kwargs, key):
    value = kwargs.get(key)
    if isinstance(value, str):
        return value.strip().lower() in ('1', 'true', 'oui', 'yes')
    return bool(value)


def _choice(model, field, value, label=None):
    if value in (None, False, ''):
        return False
    allowed = dict(request.env[model]._fields[field]._description_selection(request.env))
    if value not in allowed:
        raise ApiInputError('Valeur « %s » invalide pour « %s ».' % (value, label or field))
    return value


def _id_list(kwargs, key):
    values = kwargs.get(key) or []
    if not isinstance(values, (list, tuple)):
        raise ApiInputError('« %s » doit être une liste.' % key)
    ids = []
    for v in values:
        if isinstance(v, bool):
            raise ApiInputError('Identifiant invalide dans « %s ».' % key)
        try:
            ids.append(int(v))
        except (TypeError, ValueError):
            raise ApiInputError('Identifiant invalide dans « %s ».' % key)
    return ids


class ChurchMobileApi(http.Controller):
    """API REST pour l'application mobile de suivi d'évangélisation."""

    # ─── Périmètre ────────────────────────────────────────────────────

    @staticmethod
    def _is_manager(user):
        return user.role in MANAGERS

    def _church_domain(self, user, kwargs):
        """Super admin sans église : tout, ou l'église demandée. Autres : leur église."""
        if user.role == 'super_admin':
            filter_church = _int(kwargs, 'filter_church_id')
            if filter_church:
                return [('church_id', '=', filter_church)]
            if user.church_id:
                return [('church_id', '=', user.church_id.id)]
            return []
        return [('church_id', '=', user.church_id.id)]

    def _in_scope(self, user, church):
        return user.role == 'super_admin' or (church and church == user.church_id)

    def _resolve_church_id(self, user, kwargs):
        if user.role == 'super_admin':
            church_id = _int(kwargs, 'church_id') or user.church_id.id
            if not church_id or not request.env['equipment.church'].sudo().browse(church_id).exists():
                raise ApiInputError('Église requise.')
            return church_id
        return user.church_id.id

    def _get(self, model, user, record_id, label):
        """Charge une fiche de l'église de l'utilisateur, sinon « introuvable »."""
        record = request.env[model].sudo().browse(record_id)
        if not record_id or not record.exists() or not self._in_scope(user, record.church_id):
            raise ApiInputError('%s introuvable.' % label)
        return record

    def _ref(self, model, user, kwargs, key, label):
        """Une fiche désignée par l'app, vérifiée dans le périmètre (ou False)."""
        record_id = _int(kwargs, key, label=label)
        if not record_id:
            return False
        return self._get(model, user, record_id, label).id

    def _member_domain(self, user, kwargs):
        domain = self._church_domain(user, kwargs)
        if user.role == 'cell_leader':
            domain.append(('prayer_cell_id', '=', user.prayer_cell_id.id))
        elif user.role == 'group_leader':
            domain.append(('age_group_id', '=', user.age_group_id.id))
        return domain

    def _can_edit_member(self, user, member):
        if self._is_manager(user):
            return True
        if user.role == 'evangelist':
            followups = request.env['church.followup'].sudo().search([('member_id', '=', member.id)])
            return (member.evangelist_id == user.evangelist_id
                    or user.evangelist_id in followups.evangelist_id
                    or not followups)
        if user.role == 'cell_leader':
            return member.prayer_cell_id == user.prayer_cell_id
        if user.role == 'group_leader':
            return member.age_group_id == user.age_group_id
        return False

    def _get_followup(self, user, kwargs):
        followup = self._get('church.followup', user, _int(kwargs, 'followup_id', True, 'suivi'), 'Suivi')
        if user.role == 'evangelist':
            if followup.evangelist_id != user.evangelist_id:
                raise ApiInputError('Suivi introuvable.')
        elif not self._is_manager(user):
            raise ApiInputError('Suivi introuvable.')
        return followup

    # ─── Authentication ───────────────────────────────────────────────

    @staticmethod
    def _user_payload(user):
        data = {
            'id': user.id,
            'name': user.name,
            'phone': user.phone,
            'email': user.email or '',
            'role': user.role,
            'church_id': user.church_id.id or False,
            'church_name': user.church_id.name or '',
            'is_multi_church': user.role == 'super_admin' and not user.church_id,
            'default_followup_weeks': user.church_id.default_followup_weeks or 4,
        }
        if user.role == 'evangelist' and user.evangelist_id:
            data['evangelist_id'] = user.evangelist_id.id
        elif user.role == 'cell_leader' and user.prayer_cell_id:
            data['prayer_cell_id'] = user.prayer_cell_id.id
            data['prayer_cell_name'] = user.prayer_cell_id.name
        elif user.role == 'group_leader' and user.age_group_id:
            data['age_group_id'] = user.age_group_id.id
            data['age_group_name'] = user.age_group_id.name
        return data

    @staticmethod
    def _accounts_payload(accounts):
        return [{
            'id': a.id,
            'church_name': a.church_id.name or 'Toutes les églises',
            'role': a.role,
            'role_label': a.get_role_label(),
        } for a in accounts]

    def _session_payload(self, user, message, device_label=None):
        token = user._open_session(device_label)
        session = request.env['church.mobile.session'].sudo()._resolve_session(token)
        return {
            'status': 'success',
            'message': message,
            'token': token,
            'session_expiry': fields.Datetime.to_string(session.expires_at),
            'user': self._user_payload(user),
            'accounts': self._accounts_payload(user._sibling_accounts()),
        }

    @staticmethod
    def _limited(kind, key):
        """Compte une tentative ; True si la porte est fermée pour un moment."""
        max_req, window, block = _OTP_LIMITS[kind]
        blocked, _retry = request.env['otp.rate.limit'].sudo().check_and_record(
            'church_otp:%s:%s' % (kind, key), max_req, window, block)
        return blocked

    @staticmethod
    def _identifier(kwargs):
        try:
            return request.env['otp.code'].sudo()._norm_identifier(_text(kwargs, 'identifier'))
        except ValidationError:
            raise ApiInputError('Saisissez votre numéro de téléphone ou votre adresse e-mail.')

    @http.route('/api/church/auth/request_otp', type='jsonrpc', auth='public', methods=['POST'],
                csrf=False, readonly=False)
    def request_otp(self, **kwargs):
        """Envoie un code au numéro (WhatsApp, sinon SMS) ou à l'adresse du compte.

        La réponse est la même qu'un compte existe ou non : sinon la route
        deviendrait un annuaire des numéros enregistrés.
        """
        try:
            identifier, kind = self._identifier(kwargs)
            if self._limited('request_ip', client_ip(request)) or self._limited('request_id', identifier):
                return _error(_TOO_MANY, 'rate_limited')
            payload = {
                'status': 'success',
                'message': _OTP_SENT,
                'identifier_masked': _mask(identifier, kind),
                'channel': kind,
                'expires_in_seconds': 600,
                'resend_after_seconds': 60,
            }
            accounts = request.env['church.mobile.user'].sudo()._accounts_for_identifier(identifier, kind)
            if accounts:
                account = accounts[0]
                code = request.env['otp.code'].sudo()._issue(
                    identifier, OTP_SCOPE, phone=account.phone_e164 or None, email=account.email or None)
                if code and request.env['ir.config_parameter'].sudo().get_param(OTP_DEBUG_PARAM):
                    payload['debug_otp'] = code
            return payload
        except ApiInputError as e:
            return _error(str(e), 'invalid')
        except Exception:
            _logger.exception("Envoi du code de connexion")
            return _error('Erreur interne du serveur.', 'server')

    @http.route('/api/church/auth/verify_otp', type='jsonrpc', auth='public', methods=['POST'],
                csrf=False, readonly=False)
    def verify_otp(self, **kwargs):
        """Vérifie le code et ouvre une session sur le compte utilisé en dernier.

        Si la personne a des comptes dans plusieurs églises, ils sont tous
        rendus dans ``accounts`` : l'application propose d'en changer.
        """
        try:
            identifier, kind = self._identifier(kwargs)
            if self._limited('verify_ip', client_ip(request)):
                return _error(_TOO_MANY, 'rate_limited')
            try:
                request.env['otp.code'].sudo()._verify(identifier, OTP_SCOPE, _text(kwargs, 'code'))
            except AccessDenied:
                return _error(_OTP_REFUSED, 'auth_failed')
            accounts = request.env['church.mobile.user'].sudo()._accounts_for_identifier(identifier, kind)
            if not accounts:
                # Le compte a été désactivé entre l'envoi et la saisie du code.
                return _error("Ce compte n'est plus actif. Adressez-vous à votre responsable.", 'auth_failed')
            return self._session_payload(accounts[0], 'Connexion réussie', _text(kwargs, 'device_label'))
        except ApiInputError as e:
            return _error(str(e), 'invalid')
        except Exception:
            _logger.exception("Vérification du code de connexion")
            return _error('Erreur interne du serveur.', 'server')

    @http.route('/api/church/auth/switch', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def switch_account(self, user, **kwargs):
        """Passe au compte de la même personne dans une autre église.

        Le code a prouvé qu'on tient ce numéro : il vaut pour tous ses comptes.
        La session en cours est fermée, une nouvelle est ouverte.
        """
        target = user._sibling_accounts().filtered(lambda a: a.id == _int(kwargs, 'account_id', True, 'compte'))
        if not target:
            raise ApiInputError('Compte introuvable.')
        request.env['church.mobile.session'].sudo()._revoke(_bearer())
        return self._session_payload(target, 'Vous êtes sur %s' % (target.church_id.name or 'toutes les églises'),
                                     _text(kwargs, 'device_label'))

    @http.route('/api/church/auth/logout', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def logout(self, user, **kwargs):
        request.env['church.mobile.session'].sudo()._revoke(_bearer())
        return {'status': 'success', 'message': 'Déconnecté'}

    # ─── Dashboard ────────────────────────────────────────────────────

    @http.route('/api/church/dashboard', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_dashboard(self, user, **kwargs):
        """Tableau de bord (un évangéliste n'y voit que ses propres suivis)."""
        env = request.env
        church_domain = self._church_domain(user, kwargs)
        church_name = user.church_id.name if user.church_id else 'Toutes les églises'

        followup_domain = list(church_domain)
        evangelist_domain = list(church_domain)
        if user.role == 'evangelist':
            followup_domain.append(('evangelist_id', '=', user.evangelist_id.id))
            evangelist_domain.append(('id', '=', user.evangelist_id.id))
        elif not self._is_manager(user):
            followup_domain.append(('id', '=', 0))
            evangelist_domain.append(('id', '=', 0))

        followups = env['church.followup'].sudo().search(followup_domain)
        evangelists = env['church.evangelist'].sudo().search(evangelist_domain)

        def stats(fs):
            integrated = fs.filtered(lambda f: f.state == 'integrated')
            abandoned = fs.filtered(lambda f: f.state == 'abandoned')
            done = len(integrated) + len(abandoned)
            return {
                'active': len(fs.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)),
                'integrated': len(integrated),
                'abandoned': len(abandoned),
                'rate': round(len(integrated) / done * 100, 1) if done else 0,
            }

        global_stats = stats(followups)
        evangelist_stats = []
        for ev in evangelists:
            ev_followups = followups.filtered(lambda f: f.evangelist_id == ev)
            s = stats(ev_followups)
            evangelist_stats.append({
                'id': ev.id,
                'name': ev.name,
                'active_count': s['active'],
                'integrated_count': s['integrated'],
                'total_count': len(ev_followups),
                'integration_rate': s['rate'],
            })

        return {
            'status': 'success',
            'dashboard': {
                'church_name': church_name,
                'total_members': env['church.member'].sudo().search_count(self._member_domain(user, kwargs)),
                'total_evangelists': env['church.evangelist'].sudo().search_count(church_domain),
                'total_cells': env['church.prayer.cell'].sudo().search_count(church_domain),
                'total_groups': env['church.age.group'].sudo().search_count(church_domain),
                'active_followups': global_stats['active'],
                'total_integrated': global_stats['integrated'],
                'total_abandoned': global_stats['abandoned'],
                'integration_rate': global_stats['rate'],
                'evangelist_stats': evangelist_stats,
            },
        }

    # ─── Evangelists ──────────────────────────────────────────────────

    @http.route('/api/church/evangelists', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_evangelists(self, user, **kwargs):
        """Liste des évangélistes de l'église."""
        evangelists = request.env['church.evangelist'].sudo().search(self._church_domain(user, kwargs))
        return {
            'status': 'success',
            'evangelists': [{
                'id': e.id,
                'name': e.name,
                'phone': e.phone or '',
                'active_followup_count': e.active_followup_count,
                'integrated_count': e.integrated_count,
                'integration_rate': round(e.integration_rate, 1),
            } for e in evangelists],
        }

    @http.route('/api/church/evangelist/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def create_evangelist(self, user, **kwargs):
        """Créer un évangéliste et son compte mobile, avec l'invitation à lui transmettre."""
        evangelist = request.env['church.evangelist'].sudo().create({
            'name': _text(kwargs, 'name', True, 'nom'),
            'phone': _text(kwargs, 'phone', True, 'téléphone'),
            'church_id': self._resolve_church_id(user, kwargs),
        })
        account = evangelist.mobile_user_id
        return {
            'status': 'success',
            'message': 'Évangéliste créé',
            'evangelist': {
                'id': evangelist.id,
                'name': evangelist.name,
                'phone': evangelist.phone,
                'invitation': account.get_invitation_message() if account else '',
            },
        }

    # ─── Members ──────────────────────────────────────────────────────

    @staticmethod
    def _member_summary(m):
        return {
            'id': m.id,
            'name': m.name,
            'first_name': m.first_name,
            'phone': m.phone or '',
            'gender': m.gender or '',
            'to_complete': m.to_complete,
            'district_id': m.district_id.id or False,
            'district_name': m.district_id.name or '',
            'member_type': m.member_type,
            'prayer_cell_id': m.prayer_cell_id.id or False,
            'prayer_cell_name': m.prayer_cell_id.name or '',
            'age_group_id': m.age_group_id.id or False,
            'age_group_name': m.age_group_id.name or '',
            'age': m.age,
            'marital_status': m.marital_status,
            'invited_by_id': m.invited_by_id.id or False,
            'invited_by_name': m.invited_by_id.display_name_custom or '',
            'mentor_id': m.mentor_id.id or False,
            'mentor_name': m.mentor_id.display_name_custom or '',
            'proposed_followup_weeks': m.proposed_followup_weeks,
            'proposed_followup_origin': m.proposed_followup_origin,
            'proposed_followup_label': m.proposed_followup_label,
        }

    @http.route('/api/church/members', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_members(self, user, **kwargs):
        """Liste des membres (les responsables ne voient que leur cellule ou leur groupe)."""
        domain = self._member_domain(user, kwargs)
        member_type = _choice('church.member', 'member_type', kwargs.get('member_type'), 'type')
        if member_type:
            domain.append(('member_type', '=', member_type))
        members = request.env['church.member'].sudo().search(domain)
        return {'status': 'success', 'members': [self._member_summary(m) for m in members]}

    def _member_vals(self, user, kwargs, creating):
        """Valeurs d'une fiche membre lues depuis l'app, chaque lien vérifié."""
        vals = {}
        text_fields = {'name': 'nom', 'first_name': 'prénom', 'phone': 'téléphone',
                       'address': 'adresse', 'city': 'ville', 'profession': 'profession',
                       'notes': 'notes'}
        for key, label in text_fields.items():
            if creating or key in kwargs:
                vals[key] = _text(kwargs, key, key in ('name', 'first_name'), label) or False
        if creating or 'gender' in kwargs:
            vals['gender'] = _choice('church.member', 'gender', kwargs.get('gender'), 'sexe')
            if not vals['gender']:
                raise ApiInputError('Le champ « sexe » est requis.')
        if creating or 'marital_status' in kwargs:
            vals['marital_status'] = _choice('church.member', 'marital_status',
                                             kwargs.get('marital_status') or 'single', 'statut matrimonial')
        for key, label in (('date_of_birth', 'date de naissance'), ('salvation_date', 'date de salut')):
            if creating or key in kwargs:
                vals[key] = _date(kwargs, key, label)
        links = (('district_id', 'church.district', 'Quartier'),
                 ('invited_by_id', 'church.member', 'Invité(e) par'),
                 ('mentor_id', 'church.member', 'Mentor'))
        for key, model, label in links:
            if key in kwargs:
                vals[key] = self._ref(model, user, kwargs, key, label)
        # Rattachement et statut : décisions de responsable, pas de saisie libre.
        if self._is_manager(user):
            for key, model, label in (('prayer_cell_id', 'church.prayer.cell', 'Cellule'),
                                      ('age_group_id', 'church.age.group', 'Groupe d\'âge')):
                if key in kwargs:
                    vals[key] = self._ref(model, user, kwargs, key, label)
            if kwargs.get('member_type'):
                vals['member_type'] = _choice('church.member', 'member_type', kwargs['member_type'], 'type')
            if 'planned_followup_weeks' in kwargs:
                vals['planned_followup_weeks'] = _int(kwargs, 'planned_followup_weeks',
                                                      label='durée de suivi prévue') or 0
        return vals

    @http.route('/api/church/member/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def create_member(self, user, **kwargs):
        """Créer un nouveau membre/personne."""
        vals = self._member_vals(user, kwargs, creating=True)
        vals['church_id'] = self._resolve_church_id(user, kwargs)
        vals.setdefault('member_type', 'new')
        if user.role == 'cell_leader' and user.prayer_cell_id:
            vals.update(prayer_cell_id=user.prayer_cell_id.id, member_type='old_member')
        if user.role == 'group_leader' and user.age_group_id:
            vals.update(age_group_id=user.age_group_id.id, member_type='old_member')
        member = request.env['church.member'].sudo().create(vals)
        return {
            'status': 'success',
            'message': 'Membre créé',
            'member': {'id': member.id, 'name': member.display_name_custom},
        }

    @http.route('/api/church/followups/to_assign', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def get_people_to_assign(self, user, **kwargs):
        """Nouvelles personnes qui attendent qu'un évangéliste leur soit confié."""
        Member = request.env['church.member'].sudo()
        church = self._church_domain(user, kwargs)
        members = Member.search(church + [('member_type', '=', 'new')], order='create_date desc')
        interrupted = Member.search(church + [('member_type', '=', 'interrupted')], order='write_date desc')
        return {
            'status': 'success',
            'members': [dict(self._member_summary(m), created_on=str(m.create_date.date()))
                        for m in members],
            # Suivis interrompus : à reprendre quand la personne redonne signe de vie.
            'interrupted': [dict(self._member_summary(m), **self._interruption(m)) for m in interrupted],
        }

    @staticmethod
    def _interruption(member):
        last = member.last_followup_id
        if not last or last.state != 'abandoned':
            return {}
        return {
            'interrupted_on': str(last.abandon_date or ''),
            'abandon_reason': last.abandon_reason or '',
            'abandon_reason_label': dict(last._fields['abandon_reason'].selection).get(last.abandon_reason, ''),
            'abandon_note': last.abandon_note or '',
        }

    @staticmethod
    def _journey(member):
        """Le parcours de la personne : chaque suivi, du plus ancien au plus récent."""
        states = dict(member.env['church.followup']._fields['state'].selection)
        reasons = dict(member.env['church.followup']._fields['abandon_reason'].selection)
        return [{
            'followup_id': f.id,
            'reference': f.name,
            'evangelist_name': f.evangelist_id.name,
            'start_date': str(f.start_date) if f.start_date else '',
            'end_date': str(f.end_date) if f.end_date else '',
            'duration_weeks': f.duration_weeks,
            'state': f.state,
            'state_label': states.get(f.state, ''),
            'abandon_reason': f.abandon_reason or '',
            'abandon_reason_label': reasons.get(f.abandon_reason, ''),
            'abandon_note': f.abandon_note or '',
            'resumes_followup_id': f.previous_followup_id.id or False,
        } for f in member.followup_ids.sorted(lambda f: (f.start_date, f.id))]

    @http.route('/api/church/member/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_member_detail(self, user, **kwargs):
        """Détail d'un membre."""
        member = self._get('church.member', user, _int(kwargs, 'member_id', True, 'membre'), 'Membre')
        if not member.filtered_domain(self._member_domain(user, {})):
            raise ApiInputError('Membre introuvable.')
        return {
            'status': 'success',
            'member': {
                'id': member.id,
                'name': member.name,
                'first_name': member.first_name or '',
                'phone': member.phone or '',
                'gender': member.gender or '',
                'to_complete': member.to_complete,
                'date_of_birth': str(member.date_of_birth) if member.date_of_birth else '',
                'address': member.address or '',
                'profession': member.profession or '',
                'marital_status': member.marital_status,
                'member_type': member.member_type,
                'salvation_date': str(member.salvation_date) if member.salvation_date else '',
                'district_id': member.district_id.id or False,
                'prayer_cell_id': member.prayer_cell_id.id or False,
                'age_group_id': member.age_group_id.id or False,
                'invited_by_id': member.invited_by_id.id or False,
                'invited_by_name': member.invited_by_id.display_name_custom or '',
                'mentor_id': member.mentor_id.id or False,
                'mentor_name': member.mentor_id.display_name_custom or '',
                'can_edit': self._can_edit_member(user, member),
                'journey': self._journey(member),
                'baptism_date': str(member.baptism_date) if member.baptism_date else '',
                'integration_date': str(member.integration_date) if member.integration_date else '',
                'established_date': str(member.established_date) if member.established_date else '',
                'reopen_suggested': member.reopen_suggested,
                'checkpoints': [self._checkpoint_json(c) for c in member.checkpoint_ids
                                if c.state != 'cancelled'],
                'planned_followup_weeks': member.planned_followup_weeks,
                'proposed_followup_weeks': member.proposed_followup_weeks,
                'proposed_followup_origin': member.proposed_followup_origin,
                'proposed_followup_label': member.proposed_followup_label,
            },
        }

    @http.route('/api/church/member/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def update_member(self, user, **kwargs):
        """Mettre à jour un membre."""
        member = self._get('church.member', user, _int(kwargs, 'member_id', True, 'membre'), 'Membre')
        if not self._can_edit_member(user, member):
            return _error('Vous ne pouvez modifier que les personnes dont vous avez la charge.', 'forbidden')
        vals = self._member_vals(user, kwargs, creating=False)
        if vals:
            member.write(vals)
        return {'status': 'success', 'success': True, 'message': 'Membre mis à jour'}

    # ─── Followups ────────────────────────────────────────────────────

    @staticmethod
    def _week_json(w, with_date=True):
        data = {
            'id': w.id,
            'week_number': w.week_number,
            'sunday_attendance': w.sunday_attendance,
            'roll_call_present': w.roll_call_present,
            'call_made': w.call_made,
            'visit_made': w.visit_made,
            'spiritual_state': w.spiritual_state or '',
            'score': w.score,
            'notes': w.notes or '',
        }
        if with_date:
            data['date'] = str(w.date) if w.date else ''
        return data

    @http.route('/api/church/followups', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def get_followups(self, user, **kwargs):
        """Liste des suivis (un évangéliste ne voit que les siens)."""
        domain = self._church_domain(user, kwargs)
        if user.role == 'evangelist':
            domain.append(('evangelist_id', '=', user.evangelist_id.id))
        state = _choice('church.followup', 'state', kwargs.get('state'), 'état')
        if state:
            domain.append(('state', '=', state))
        followups = request.env['church.followup'].sudo().search(domain, order='create_date desc')
        return {
            'status': 'success',
            'followups': [{
                'id': f.id,
                'name': f.name,
                'reference': f.name,
                'evangelist_id': f.evangelist_id.id,
                'evangelist_name': f.evangelist_id.name,
                'member_id': f.member_id.id,
                'member_name': f.member_id.display_name_custom,
                'member_phone': f.member_id.phone or '',
                'start_date': str(f.start_date) if f.start_date else '',
                'end_date': str(f.end_date) if f.end_date else '',
                'duration_weeks': f.duration_weeks,
                'duration_origin': f.duration_origin or '',
                'total_weeks': f.duration_weeks,
                'current_week': f.week_count,
                'progress': round(f.week_count / f.duration_weeks * 100, 1) if f.duration_weeks else 0,
                'state': f.state,
                'week_count': f.week_count,
                'attendance_rate': f.attendance_rate,
                'below_threshold': f.below_threshold,
                'average_score': round(f.average_score, 1),
                'weeks': [self._week_json(w) for w in f.week_ids],
            } for f in followups],
        }

    @http.route('/api/church/followup/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def create_followup(self, user, **kwargs):
        """Créer un nouveau suivi."""
        if user.role == 'evangelist':
            if not user.evangelist_id:
                raise ApiInputError('Votre compte n\'est relié à aucune fiche d\'évangéliste.')
            evangelist_id = user.evangelist_id.id
        else:
            evangelist_id = self._ref('church.evangelist', user, kwargs, 'evangelist_id', 'Évangéliste')
            if not evangelist_id:
                raise ApiInputError('Évangéliste requis.')
        member = self._get('church.member', user, _int(kwargs, 'member_id', True, 'membre'), 'Membre')
        vals = {
            'church_id': member.church_id.id,
            'evangelist_id': evangelist_id,
            'member_id': member.id,
        }
        # L'app envoie `duration_weeks` ; `total_weeks` reste accepté.
        duration = _int(kwargs, 'duration_weeks', label='durée') or _int(kwargs, 'total_weeks', label='durée')
        if duration:
            vals['duration_weeks'] = duration
        followup = request.env['church.followup'].sudo().create(vals)
        return {
            'status': 'success',
            'success': True,
            'message': 'Suivi créé',
            'followup': {'id': followup.id, 'name': followup.name, 'duration_weeks': followup.duration_weeks,
                         'duration_origin': followup.duration_origin},
        }

    @http.route('/api/church/followup/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def get_followup_detail(self, user, **kwargs):
        """Détail d'un suivi."""
        f = self._get_followup(user, kwargs)
        weeks = f.week_ids.sorted('week_number')
        return {
            'status': 'success',
            'followup': {
                'id': f.id,
                'reference': f.name,
                'evangelist_name': f.evangelist_id.name,
                'member_name': f.member_id.display_name_custom,
                'member_phone': f.member_id.phone or '',
                'start_date': str(f.start_date) if f.start_date else '',
                'planned_end_date': str(f.end_date) if f.end_date else '',
                'state': f.state,
                'current_week': f.week_count,
                'total_weeks': f.duration_weeks,
                'duration_origin': f.duration_origin or '',
                'progress': round(f.week_count / f.duration_weeks * 100, 1) if f.duration_weeks else 0,
                'average_score': round(f.average_score, 1),
                'elapsed_weeks': f.elapsed_weeks,
                'attendance_weeks': f.attendance_weeks,
                'attendance_rate': f.attendance_rate,
                'attendance_threshold': f.attendance_threshold,
                'below_threshold': f.below_threshold,
                'integration_justification': f.integration_justification or '',
                'weeks': [self._week_json(w, with_date=False) for w in weeks],
            },
        }

    @http.route('/api/church/followup/week/save', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def save_followup_week(self, user, **kwargs):
        """Enregistrer un rapport hebdomadaire."""
        followup = self._get_followup(user, kwargs)
        if followup.state not in ACTIVE_FOLLOWUP_STATES:
            raise ApiInputError('Ce suivi est clos : ses rapports ne peuvent plus être modifiés.')
        week_number = _int(kwargs, 'week_number', True, 'numéro de semaine')
        vals = {
            'followup_id': followup.id,
            'week_number': week_number,
            'date': fields.Date.today(),
            'sunday_attendance': _bool(kwargs, 'sunday_attendance'),
            'call_made': _bool(kwargs, 'call_made'),
            'visit_made': _bool(kwargs, 'visit_made'),
            'spiritual_state': _choice('church.followup.week', 'spiritual_state',
                                       kwargs.get('spiritual_state'), 'état spirituel'),
            'notes': _text(kwargs, 'notes') or False,
        }
        Week = request.env['church.followup.week'].sudo()
        week = Week.search([('followup_id', '=', followup.id), ('week_number', '=', week_number)], limit=1)
        if week:
            week.write(vals)
        else:
            week = Week.create(vals)
        return {'status': 'success', 'message': 'Rapport enregistré', 'week': {'id': week.id, 'score': week.score}}

    @http.route('/api/church/followup/action', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def followup_action(self, user, **kwargs):
        """Effectuer une action sur un suivi (intégrer, abandonner, etc.)."""
        followup = self._get_followup(user, kwargs)
        action = _text(kwargs, 'action', True, 'action')
        if action == 'integrate':
            cell_id = self._ref('church.prayer.cell', user, kwargs, 'target_cell_id', 'Cellule')
            group_id = self._ref('church.age.group', user, kwargs, 'target_age_group_id', 'Groupe d\'âge')
            if not cell_id or not group_id:
                raise ApiInputError('Cellule et groupe d\'âge requis.')
            vals = {'target_cell_id': cell_id, 'target_age_group_id': group_id}
            if _text(kwargs, 'justification'):
                vals['integration_justification'] = _text(kwargs, 'justification')
            followup.write(vals)
            followup.action_integrate()
        elif action == 'abandon':
            followup.action_abandon(
                reason=_choice('church.followup', 'abandon_reason', kwargs.get('reason'), 'motif'),
                note=_text(kwargs, 'note'))
        elif action == 'extend':
            followup.action_extend(weeks=_int(kwargs, 'weeks', label='semaines à ajouter'))
        elif action == 'transfer':
            target_id = self._ref('church.evangelist', user, kwargs, 'transferred_to_id', 'Évangéliste destinataire')
            if not target_id:
                raise ApiInputError('Évangéliste destinataire requis.')
            followup.write({'transferred_to_id': target_id})
            followup.action_transfer()
        else:
            raise ApiInputError('Action inconnue : %s.' % action)
        return {'status': 'success', 'message': 'Action effectuée'}

    @http.route('/api/church/todo', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_todo(self, user, **kwargs):
        """Liste « À faire » : ce qui attend l'utilisateur, avec un résumé pour le badge."""
        items = user._todo_items()
        return {'status': 'success', 'count': len(items), 'summary': user._todo_summary(items),
                'items': items}

    # ─── Points de contrôle après l'intégration ───────────────────────

    @staticmethod
    def _checkpoint_json(c):
        return {
            'id': c.id,
            'member_id': c.member_id.id,
            'member_name': c.member_id.display_name,
            'member_phone': c.member_id.phone or '',
            'prayer_cell_name': c.prayer_cell_id.name or '',
            'milestone': c.milestone,
            'is_catchup': c.is_catchup,
            'due_date': str(c.due_date),
            'state': c.state,
            'result': c.result or '',
            'done_date': str(c.done_date) if c.done_date else '',
            'service_count': c.service_count,
            'cell_count': c.cell_count,
            'notes': c.notes or '',
            'baptized': bool(c.member_id.baptism_date),
            'has_mentor': bool(c.member_id.mentor_id),
        }

    def _checkpoint_domain(self, user, kwargs):
        domain = self._church_domain(user, kwargs)
        if user.role == 'cell_leader':
            domain.append(('prayer_cell_id', '=', user.prayer_cell_id.id))
        return domain

    @http.route('/api/church/checkpoints', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'cell_leader'))
    def get_checkpoints(self, user, **kwargs):
        """Contrôles à faire (par défaut) ou faits, dans le périmètre de l'utilisateur."""
        state = _choice('church.member.checkpoint', 'state', kwargs.get('state') or 'planned', 'état')
        checkpoints = request.env['church.member.checkpoint'].sudo().search(
            self._checkpoint_domain(user, kwargs) + [('state', '=', state)], order='due_date')
        return {'status': 'success', 'checkpoints': [self._checkpoint_json(c) for c in checkpoints]}

    @http.route('/api/church/checkpoint/save', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'cell_leader'))
    def save_checkpoint(self, user, **kwargs):
        """Enregistre le résultat d'un contrôle ; peut aussi noter le baptême et le mentor."""
        checkpoint = self._get('church.member.checkpoint', user,
                               _int(kwargs, 'checkpoint_id', True, 'contrôle'), 'Contrôle')
        if not checkpoint.filtered_domain(self._checkpoint_domain(user, {})):
            raise ApiInputError('Contrôle introuvable.')
        member_vals = {}
        if kwargs.get('baptism_date'):
            member_vals['baptism_date'] = _date(kwargs, 'baptism_date', 'date de baptême')
        if kwargs.get('mentor_id'):
            member_vals['mentor_id'] = self._ref('church.member', user, kwargs, 'mentor_id', 'Mentor')
        if member_vals:
            checkpoint.member_id.write(member_vals)
        checkpoint.action_record(
            _choice('church.member.checkpoint', 'result', kwargs.get('result'), 'résultat'),
            notes=_text(kwargs, 'notes') or None, done_by=user.name)
        return {'status': 'success', 'message': 'Contrôle enregistré',
                'checkpoint': self._checkpoint_json(checkpoint),
                'member_type': checkpoint.member_id.member_type}

    @http.route('/api/church/settings', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def church_settings(self, user, **kwargs):
        """Réglages de l'église ; un responsable peut changer la durée de suivi par défaut."""
        church = request.env['equipment.church'].sudo().browse(self._resolve_church_id(user, kwargs))
        settings = {'default_followup_weeks': 'durée de suivi par défaut',
                    'integration_min_attendance': 'présence minimale pour intégrer'}
        vals = {key: _int(kwargs, key, True, label) for key, label in settings.items() if key in kwargs}
        if vals:
            if not self._is_manager(user):
                return _error('Action non autorisée pour votre rôle.', 'forbidden')
            church.write(vals)
        return {
            'status': 'success',
            'settings': {'church_id': church.id,
                         'default_followup_weeks': church.default_followup_weeks,
                         'integration_min_attendance': church.integration_min_attendance},
        }

    # ─── Prayer Cells ─────────────────────────────────────────────────

    @http.route('/api/church/cells', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_prayer_cells(self, user, **kwargs):
        """Liste des cellules de prière."""
        domain = self._church_domain(user, kwargs)
        if user.role == 'cell_leader':
            domain.append(('id', '=', user.prayer_cell_id.id))
        cells = request.env['church.prayer.cell'].sudo().search(domain)
        # Les numéros des membres ne sont donnés qu'à qui en a la charge.
        with_phones = self._is_manager(user) or user.role == 'cell_leader'
        return {
            'status': 'success',
            'cells': [{
                'id': c.id,
                'name': c.name,
                'leader_name': c.leader_name or '',
                'leader_phone': c.leader_phone or '',
                'meeting_day': c.meeting_day or '',
                'meeting_time': c.meeting_time or '',
                'meeting_location': c.meeting_location or '',
                'member_count': c.member_count,
                'members': [{
                    'id': m.id,
                    'name': m.display_name_custom,
                    'phone': (m.phone or '') if with_phones else '',
                } for m in c.member_ids],
            } for c in cells],
        }

    # ─── Age Groups ───────────────────────────────────────────────────

    @http.route('/api/church/age_groups', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_age_groups(self, user, **kwargs):
        """Liste des groupes d'âge."""
        domain = self._church_domain(user, kwargs)
        if user.role == 'group_leader':
            domain.append(('id', '=', user.age_group_id.id))
        groups = request.env['church.age.group'].sudo().search(domain)
        with_phones = self._is_manager(user) or user.role == 'group_leader'
        return {
            'status': 'success',
            'age_groups': [{
                'id': g.id,
                'name': g.name,
                'group_type': g.group_type,
                'gender': g.gender,
                'leader_name': g.leader_name or '',
                'leader_phone': g.leader_phone or '',
                'member_count': g.member_count,
                'members': [{
                    'id': m.id,
                    'name': m.display_name_custom,
                    'phone': (m.phone or '') if with_phones else '',
                    'age': m.age,
                } for m in g.member_ids],
            } for g in groups],
        }

    # ─── Districts ────────────────────────────────────────────────────

    @http.route('/api/church/districts', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_districts(self, user, **kwargs):
        """Liste des quartiers de l'église."""
        districts = request.env['church.district'].sudo().search(self._church_domain(user, kwargs))
        return {
            'status': 'success',
            'districts': [{'id': d.id, 'name': d.name, 'city': d.city or ''} for d in districts],
        }

    # ─── Attendance ───────────────────────────────────────────────────

    @http.route('/api/church/attendance/sunday/save', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'group_leader', 'evangelist'))
    def save_sunday_attendance(self, user, **kwargs):
        """Enregistrer la présence au culte du dimanche."""
        date = _date(kwargs, 'date', 'date') or fields.Date.today()
        members = request.env['church.member'].sudo().browse(_id_list(kwargs, 'member_ids')).exists()
        if members.filtered_domain(self._member_domain(user, {})) != members:
            raise ApiInputError('Certaines personnes ne relèvent pas de votre périmètre.')
        Att = request.env['church.attendance.sunday'].sudo()
        already = Att.search([('member_id', 'in', members.ids), ('date', '=', date)]).member_id
        Att.create([{
            'church_id': m.church_id.id,
            'member_id': m.id,
            'age_group_id': m.age_group_id.id or False,
            'date': date,
            'present': True,
        } for m in members - already])
        return {'status': 'success', 'success': True, 'message': 'Présences enregistrées'}

    @http.route('/api/church/attendance/cell/save', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'cell_leader'))
    def save_cell_attendance(self, user, **kwargs):
        """Enregistrer la présence à la cellule de prière."""
        date = _date(kwargs, 'date', 'date') or fields.Date.today()
        cell = self._get('church.prayer.cell', user, _int(kwargs, 'prayer_cell_id', True, 'cellule'), 'Cellule')
        if user.role == 'cell_leader' and cell != user.prayer_cell_id:
            raise ApiInputError('Vous ne pouvez pointer que votre propre cellule.')
        members = request.env['church.member'].sudo().browse(_id_list(kwargs, 'member_ids')).exists()
        Att = request.env['church.attendance.cell'].sudo()
        already = Att.search([
            ('member_id', 'in', members.ids), ('date', '=', date), ('prayer_cell_id', '=', cell.id),
        ]).member_id
        Att.create([{
            'church_id': cell.church_id.id,
            'prayer_cell_id': cell.id,
            'member_id': m.id,
            'date': date,
            'present': True,
        } for m in members - already])
        return {'status': 'success', 'success': True, 'message': 'Présences enregistrées'}

    # ─── Cooking Rotation ─────────────────────────────────────────────

    @http.route('/api/church/cooking_rotation', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_cooking_rotation(self, user, **kwargs):
        """Programme de rotation cuisine."""
        rotations = request.env['church.cooking.rotation'].sudo().search(
            self._church_domain(user, kwargs), order='date')
        return {
            'status': 'success',
            'rotations': [{
                'id': r.id,
                'date': str(r.date),
                'prayer_cell_id': r.prayer_cell_id.id,
                'prayer_cell_name': r.prayer_cell_id.name,
                'description': r.description or '',
                'state': r.state,
            } for r in rotations],
        }

    # ─── Credentials sharing ─────────────────────────────────────────

    def _get_account(self, user, kwargs):
        target = request.env['church.mobile.user'].sudo().with_context(active_test=False).browse(
            _int(kwargs, 'target_user_id', True, 'utilisateur'))
        if not target.exists() or not (user.role == 'super_admin' or target.church_id == user.church_id):
            raise ApiInputError('Utilisateur introuvable.')
        # Un responsable ne gère pas les comptes de même niveau ou supérieur.
        if user.role == 'manager' and target.role in MANAGERS:
            raise ApiInputError('Utilisateur introuvable.')
        return target

    @http.route('/api/church/user/share_message', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def get_share_message(self, user, **kwargs):
        """L'invitation à installer l'app et à s'y connecter. Aucun secret : on
        peut la renvoyer autant de fois qu'il faut."""
        target = self._get_account(user, kwargs)
        return {
            'status': 'success',
            'message': target.get_invitation_message(),
            'phone': target.phone,
        }

    # ─── Report data ──────────────────────────────────────────────────

    @http.route('/api/church/report/followup', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin', 'manager', 'evangelist'))
    def get_followup_report(self, user, **kwargs):
        """Données du rapport de suivi par évangéliste."""
        evangelist = self._get('church.evangelist', user,
                               _int(kwargs, 'evangelist_id', True, 'évangéliste'), 'Évangéliste')
        if user.role == 'evangelist' and evangelist != user.evangelist_id:
            raise ApiInputError('Évangéliste introuvable.')
        followups = request.env['church.followup'].sudo().search(
            [('evangelist_id', '=', evangelist.id)], order='create_date desc')
        return {
            'status': 'success',
            'report': {
                'evangelist': {
                    'name': evangelist.name,
                    'phone': evangelist.phone or '',
                    'total': len(followups),
                    'active': len(followups.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)),
                    'integrated': len(followups.filtered(lambda f: f.state == 'integrated')),
                    'abandoned': len(followups.filtered(lambda f: f.state == 'abandoned')),
                    'extended': len(followups.filtered(lambda f: f.state == 'extended')),
                    'rate': round(evangelist.integration_rate, 1),
                },
                'followups': [{
                    'name': f.name,
                    'duration_weeks': f.duration_weeks,
                    'member_name': f.member_id.display_name_custom,
                    'start_date': str(f.start_date) if f.start_date else '',
                    'end_date': str(f.end_date) if f.end_date else '',
                    'state': f.state,
                    'weeks': [{
                        'week_number': w.week_number,
                        'sunday_attendance': w.sunday_attendance,
                        'call_made': w.call_made,
                        'visit_made': w.visit_made,
                        'spiritual_state': w.spiritual_state or '',
                        'score': w.score,
                    } for w in f.week_ids],
                } for f in followups],
            },
        }

    # ─── Mobile user management (for manager) ────────────────────────

    @http.route('/api/church/mobile_users', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def get_mobile_users(self, user, **kwargs):
        """Liste des utilisateurs mobiles (manager/super_admin uniquement)."""
        users = request.env['church.mobile.user'].sudo().with_context(active_test=False).search(
            self._church_domain(user, kwargs))
        return {
            'status': 'success',
            'users': [{
                'id': u.id,
                'name': u.name,
                'phone': u.phone,
                'role': u.role,
                'active': u.active,
                'church_id': u.church_id.id or False,
                'church_name': u.church_id.name or '',
                'email': u.email or '',
                'last_login': fields.Datetime.to_string(u.last_login) if u.last_login else '',
            } for u in users],
        }

    def _create_leader(self, user, kwargs, model, key, label):
        record = self._get(model, user, _int(kwargs, key, True, label), label)
        record.write({
            'leader_name': _text(kwargs, 'name', True, 'nom'),
            'leader_phone': _text(kwargs, 'phone', True, 'téléphone'),
        })
        record.action_create_leader_account()
        account = record.mobile_user_id
        return account.get_invitation_message() if account else ''

    @http.route('/api/church/cell_leader/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def create_cell_leader(self, user, **kwargs):
        """Créer un responsable de cellule (manager/super_admin uniquement)."""
        invitation = self._create_leader(user, kwargs, 'church.prayer.cell', 'prayer_cell_id', 'Cellule')
        return {'status': 'success', 'message': 'Responsable de cellule créé', 'invitation': invitation}

    @http.route('/api/church/group_leader/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def create_group_leader(self, user, **kwargs):
        """Créer un responsable de groupe d'âge (manager/super_admin uniquement)."""
        invitation = self._create_leader(user, kwargs, 'church.age.group', 'age_group_id', 'Groupe d\'âge')
        return {'status': 'success', 'message': 'Responsable de groupe créé', 'invitation': invitation}

    # ─── Super Admin: User Management ─────────────────────────────────

    @http.route('/api/church/admin/create_user', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def admin_create_user(self, user, **kwargs):
        """Créer un utilisateur mobile (super_admin uniquement)."""
        name = _text(kwargs, 'name', True, 'nom')
        phone = _text(kwargs, 'phone', True, 'téléphone')
        role = _text(kwargs, 'role', True, 'rôle')
        valid_roles = ('manager', 'evangelist', 'cell_leader', 'group_leader')
        if role not in valid_roles:
            raise ApiInputError('Rôle invalide. Valeurs possibles : %s' % ', '.join(valid_roles))
        # Un responsable de cellule ou de groupe passe par le circuit de l'unité :
        # l'ancien responsable y est remplacé.
        if role in self._LEADER_UNITS:
            model, key, label = self._LEADER_UNITS[role]
            if not _int(kwargs, key):
                raise ApiInputError('Choisissez %s de ce responsable.' % label.lower())
            invitation = self._create_leader(user, kwargs, model, key, label)
            new_user = request.env[model].sudo().browse(_int(kwargs, key)).mobile_user_id
            if _text(kwargs, 'email'):
                new_user.email = _text(kwargs, 'email')
            return {
                'status': 'success',
                'message': 'Utilisateur %s créé avec le rôle %s' % (name, role),
                'user': {'id': new_user.id, 'name': new_user.name, 'phone': new_user.phone,
                         'role': new_user.role, 'invitation': invitation},
            }
        church_id = self._resolve_church_id(user, kwargs)
        vals = {'name': name, 'phone': phone, 'role': role, 'church_id': church_id,
                'email': _text(kwargs, 'email') or False}
        if role == 'evangelist':
            vals['evangelist_id'] = self._evangelist_for(user, kwargs, name, phone, church_id)
        new_user = request.env['church.mobile.user'].sudo().create(vals)
        return {
            'status': 'success',
            'message': 'Utilisateur %s créé avec le rôle %s' % (name, role),
            'user': {
                'id': new_user.id,
                'name': new_user.name,
                'phone': new_user.phone,
                'role': new_user.role,
                'invitation': new_user.get_invitation_message(),
            },
        }

    _LEADER_UNITS = {
        'cell_leader': ('church.prayer.cell', 'prayer_cell_id', 'La cellule'),
        'group_leader': ('church.age.group', 'age_group_id', 'Le groupe d\'âge'),
    }

    def _evangelist_for(self, user, kwargs, name, phone, church_id):
        """La fiche d'évangéliste du compte : celle désignée, sinon celle qui porte
        ce numéro dans l'église, sinon une nouvelle. Sans elle, un évangéliste ne
        peut ouvrir aucun suivi."""
        designated = self._ref('church.evangelist', user, kwargs, 'evangelist_id', 'Évangéliste')
        if designated:
            return designated
        Evangelist = request.env['church.evangelist'].sudo()
        key = phone_key(phone)
        same = Evangelist.search([('church_id', '=', church_id)]).filtered(lambda e: phone_key(e.phone) == key)
        if same:
            return same[:1].id
        return Evangelist.with_context(church_skip_mobile_account=True).create({
            'name': name, 'phone': phone, 'church_id': church_id}).id

    def _role_links(self, user, target, role, kwargs):
        """Le rattachement qu'exige un rôle ; un rôle sans rattachement est refusé."""
        if role == 'evangelist':
            return {'evangelist_id': target.evangelist_id.id or self._evangelist_for(
                user, kwargs, target.name, target.phone, target.church_id.id)}
        if role in self._LEADER_UNITS:
            model, key, label = self._LEADER_UNITS[role]
            unit_id = self._ref(model, user, kwargs, key, label) or target[key].id
            if not unit_id:
                raise ApiInputError('Choisissez %s de ce responsable.' % label.lower())
            return {key: unit_id}
        return {}

    @http.route('/api/church/admin/update_user', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def admin_update_user(self, user, **kwargs):
        """Modifier un utilisateur mobile : changer rôle, activer/désactiver."""
        target = self._get_account(user, kwargs)
        if target == user:
            raise ApiInputError('Vous ne pouvez pas modifier votre propre compte.')
        vals = {}
        if kwargs.get('role'):
            vals['role'] = _choice('church.mobile.user', 'role', kwargs['role'], 'rôle')
        if 'active' in kwargs:
            vals['active'] = _bool(kwargs, 'active')
        if _text(kwargs, 'name'):
            vals['name'] = _text(kwargs, 'name')
        if 'email' in kwargs:
            vals['email'] = _text(kwargs, 'email') or False
        if vals.get('role') or any(k in kwargs for k in ('prayer_cell_id', 'age_group_id', 'evangelist_id')):
            vals.update(self._role_links(user, target, vals.get('role') or target.role, kwargs))
        if vals:
            target.write(vals)
        # Le compte devient le responsable désigné de son unité.
        if target.role in self._LEADER_UNITS:
            _model, key, _label = self._LEADER_UNITS[target.role]
            unit = target[key]
            if unit and unit.mobile_user_id != target:
                unit.write({'leader_name': target.name, 'leader_phone': target.phone})
                unit.mobile_user_id = target
        return {
            'status': 'success',
            'message': 'Utilisateur mis à jour',
            'user': {'id': target.id, 'name': target.name, 'role': target.role, 'active': target.active},
        }

    # ─── Églises de l'annuaire (super_admin) ──────────────────────────
    # L'église et ses pasteurs vivent dans l'annuaire du réseau (church_core,
    # bng_equipment_loan). Le suivi les lit, et n'écrit que ce qui est à lui :
    # entrer dans le suivi, et ses propres réglages.

    @staticmethod
    def _pastors_json(church):
        return [{
            'id': p.id,
            'name': p.name,
            'function': p.function,
            'is_titular': p.function == 'pastor',
            'phone': p.phone or '',
        } for p in church.pastor_ids.filtered('active').sorted(lambda p: (p.function != 'pastor', p.name))]

    def _church_json(self, church):
        return {
            'id': church.id,
            'name': church.name,
            'code': church.code or '',
            'region': church.region_id.name or '',
            'address': church.address or '',
            'city': church.city or '',
            'phone': church.phone or '',
            'email': church.email or '',
            'pastor_name': church.pastor_name or '',
            'pastors': self._pastors_json(church),
            'active': church.active,
            'followup_enabled': church.followup_enabled,
            'member_count': church.member_count,
            'evangelist_count': church.evangelist_count,
            'cell_count': church.cell_count,
        }

    @http.route('/api/church/churches', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def get_churches(self, user, **kwargs):
        """Les églises qui utilisent le suivi (super_admin uniquement)."""
        churches = request.env['equipment.church'].sudo().with_context(active_test=False).search(
            [('followup_enabled', '=', True)])
        return {'status': 'success', 'churches': [self._church_json(c) for c in churches]}

    @http.route('/api/church/churches/directory', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def search_directory(self, user, **kwargs):
        """Chercher une église dans l'annuaire du réseau pour l'ajouter au suivi."""
        query = _text(kwargs, 'query')
        Church = request.env['equipment.church'].sudo()
        domain = [('followup_enabled', '=', False)]
        if query:
            domain += ['|', '|', ('name', 'ilike', query), ('city', 'ilike', query), ('code', 'ilike', query)]
        churches = Church.search(domain, limit=30)
        return {'status': 'success', 'churches': [{
            'id': c.id, 'name': c.name, 'city': c.city or '', 'region': c.region_id.name or '',
            'pastor_name': c.pastor_name or '',
        } for c in churches]}

    @http.route('/api/church/churches/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def create_church(self, user, **kwargs):
        """Faire entrer une église dans le suivi.

        Par son identifiant dans l'annuaire, ou par son nom : une église déjà
        connue sous une autre écriture (« EGLISE BNG ANGRE ») est reprise, pas
        doublée. Elle n'est créée dans l'annuaire que si elle n'y est pas.
        """
        Church = request.env['equipment.church'].sudo()
        church_id = _int(kwargs, 'church_id', label='église')
        if church_id:
            church = Church.browse(church_id)
            if not church.exists():
                raise ApiInputError('Église non trouvée.')
            created = False
        else:
            name = _text(kwargs, 'name', True, 'nom')
            # La clé de rapprochement se calcule sur le nom normalisé : « b.n.g »
            # y redevient « BNG ».
            church = Church._find_by_name(Church._normalize_name(name))
            created = not church
            if created:
                church = Church.create({
                    'name': name,
                    'address': _text(kwargs, 'address') or False,
                    'city': _text(kwargs, 'city') or False,
                    'phone': _text(kwargs, 'phone') or False,
                    'email': _text(kwargs, 'email') or False,
                })
        church._enable_followup()
        return {
            'status': 'success',
            'message': ('Église « %s » ajoutée à l\'annuaire et au suivi' if created
                        else 'Église « %s » ajoutée au suivi') % church.name,
            'church': {'id': church.id, 'name': church.name, 'code': church.code or ''},
        }

    def _get_church(self, kwargs):
        church = request.env['equipment.church'].sudo().with_context(active_test=False).browse(
            _int(kwargs, 'church_id', True, 'église'))
        if not church.exists():
            raise ApiInputError('Église non trouvée.')
        return church

    @http.route('/api/church/churches/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def update_church(self, user, **kwargs):
        """Réglages du suivi d'une église ; son identité se corrige dans l'annuaire."""
        church = self._get_church(kwargs)
        vals = {}
        if 'followup_enabled' in kwargs:
            vals['followup_enabled'] = _bool(kwargs, 'followup_enabled')
        if 'default_followup_weeks' in kwargs:
            vals['default_followup_weeks'] = _int(kwargs, 'default_followup_weeks', True, 'durée de suivi par défaut')
        if 'integration_min_attendance' in kwargs:
            vals['integration_min_attendance'] = _int(
                kwargs, 'integration_min_attendance', True, 'présence minimale pour intégrer')
        if vals:
            church.write(vals)
        return {
            'status': 'success',
            'message': 'Église mise à jour',
            'church': {'id': church.id, 'name': church.name, 'code': church.code or ''},
        }

    @http.route('/api/church/churches/detail', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def get_church_detail(self, user, **kwargs):
        """Détail d'une église avec statistiques (super_admin uniquement)."""
        church = self._get_church(kwargs)
        followups = request.env['church.followup'].sudo().search([('church_id', '=', church.id)])
        managers = request.env['church.mobile.user'].sudo().search([
            ('church_id', '=', church.id), ('role', '=', 'manager'), ('active', '=', True),
        ])
        return {
            'status': 'success',
            'church': dict(
                self._church_json(church),
                age_group_count=church.age_group_count,
                default_followup_weeks=church.default_followup_weeks,
                integration_min_attendance=church.integration_min_attendance,
                active_followups=len(followups.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)),
                total_integrated=len(followups.filtered(lambda f: f.state == 'integrated')),
                managers=[{'id': m.id, 'name': m.name, 'phone': m.phone} for m in managers],
            ),
        }

    @http.route('/api/church/manager/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def create_manager(self, user, **kwargs):
        """Créer un responsable des évangélistes pour une église (super_admin uniquement)."""
        church = self._get_church(kwargs)
        new_manager = request.env['church.mobile.user'].sudo().create({
            'name': _text(kwargs, 'name', True, 'nom'),
            'phone': _text(kwargs, 'phone', True, 'téléphone'),
            'role': 'manager',
            'church_id': church.id,
            'email': _text(kwargs, 'email') or False,
        })
        return {
            'status': 'success',
            'message': 'Responsable « %s » créé pour %s' % (new_manager.name, church.name),
            'user': {
                'id': new_manager.id,
                'name': new_manager.name,
                'phone': new_manager.phone,
                'role': new_manager.role,
                'invitation': new_manager.get_invitation_message(),
                'church_name': church.name,
            },
        }

    # ─── Pasteurs (annuaire du réseau, lecture seule) ─────────────────

    @http.route('/api/church/pastors', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_pastors(self, user, **kwargs):
        """Les pasteurs de son église, ou de n'importe laquelle pour le super admin.

        On les ajoute, les mute ou les retire dans l'annuaire du réseau.
        """
        domain = [('active', '=', True)]
        church_id = _int(kwargs, 'church_id', label='église')
        if user.role != 'super_admin':
            church_id = user.church_id.id
        if church_id:
            domain.append(('church_id', '=', church_id))
        pastors = request.env['equipment.pastor'].sudo().search(domain, order='function desc, name')
        return {
            'status': 'success',
            'pastors': [{
                'id': p.id,
                'name': p.name,
                'phone': p.phone or '',
                'function': p.function,
                'is_titular': p.function == 'pastor',
                'church_id': p.church_id.id,
                'church_name': p.church_id.name,
            } for p in pastors],
        }
