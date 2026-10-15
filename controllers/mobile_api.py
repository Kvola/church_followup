import functools
import logging

from psycopg2 import IntegrityError

from odoo import fields, http
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.http import request

from odoo.addons.otp_auth.tools.client_ip import client_ip

from ..models.church_mobile_user import phone_key
from ..models.church_tools import ACTIVE_FOLLOWUP_STATES

_logger = logging.getLogger(__name__)

# Seuls les ÉCHECS de connexion sont comptés. Deux compteurs :
# * numéro + adresse : un inconnu ne peut pas verrouiller le compte d'autrui
#   depuis sa propre adresse ;
# * adresse seule : une même machine ne peut pas essayer numéro après numéro.
_LOGIN_LIMITS = (
    ('phone_ip', 5, 15 * 60, 15 * 60),
    ('ip', 30, 15 * 60, 30 * 60),
)
_LOGIN_FAILED = 'Identifiants incorrects ou trop de tentatives. Réessayez plus tard.'

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
            user = request.env['church.mobile.user'].sudo()._from_session(
                kwargs.get('user_id'), kwargs.get('token'))
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
            if not church_id or not request.env['church.church'].sudo().browse(church_id).exists():
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

    @http.route('/api/church/auth/login', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    def login(self, **kwargs):
        """Connexion via téléphone + PIN."""
        phone = phone_key(kwargs.get('phone') if isinstance(kwargs.get('phone'), str) else '')
        pin = kwargs.get('pin') if isinstance(kwargs.get('pin'), str) else ''
        pin = pin.strip()
        if not phone or not pin:
            return _error('Téléphone et PIN requis', 'invalid')

        try:
            ip = client_ip(request)
            keys = {'phone_ip': 'church_login:%s:%s' % (phone, ip), 'ip': 'church_login_ip:%s' % ip}
            Limit = request.env['otp.rate.limit'].sudo()
            now = fields.Datetime.now()
            if Limit.search_count([('key', 'in', list(keys.values())), ('blocked_until', '>', now)]):
                return _error(_LOGIN_FAILED, 'auth_failed')

            # Un même numéro peut avoir un compte dans plusieurs églises : le PIN choisit.
            candidates = request.env['church.mobile.user'].sudo().search([
                ('phone_key', '=', phone), ('active', '=', True),
            ])
            user = next((u for u in candidates if u.verify_pin(pin)), None)
            if not user:
                for kind, max_req, window, block in _LOGIN_LIMITS:
                    Limit.check_and_record(keys[kind], max_req, window, block)
                return _error(_LOGIN_FAILED, 'auth_failed')

            token = user._open_session()
            data = {
                'id': user.id,
                'name': user.name,
                'phone': user.phone,
                'role': user.role,
                'church_id': user.church_id.id or False,
                'church_name': user.church_id.name or '',
                'is_multi_church': user.role == 'super_admin' and not user.church_id,
                'session_expiry': fields.Datetime.to_string(user.token_expiry),
                'default_followup_weeks': user.church_id.default_followup_weeks or 4,
            }
            if user.role == 'evangelist' and user.evangelist_id:
                data['evangelist_id'] = user.evangelist_id.id
            elif user.role == 'cell_leader' and user.prayer_cell_id:
                data['prayer_cell_id'] = user.prayer_cell_id.id
            elif user.role == 'group_leader' and user.age_group_id:
                data['age_group_id'] = user.age_group_id.id

            return {'status': 'success', 'message': 'Connexion réussie', 'user': data, 'token': token}
        except Exception:
            _logger.exception("Erreur de connexion")
            return _error('Erreur interne du serveur.', 'server')

    @http.route('/api/church/auth/logout', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def logout(self, user, **kwargs):
        user.action_close_session()
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
        """Créer un évangéliste et son compte mobile ; le PIN n'est rendu qu'ici."""
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
                'pin': account._issue_pin() if account else '',
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
            'gender': m.gender,
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
        members = request.env['church.member'].sudo().search(
            self._church_domain(user, kwargs) + [('member_type', '=', 'new')], order='create_date desc')
        return {
            'status': 'success',
            'members': [dict(self._member_summary(m), created_on=str(m.create_date.date()))
                        for m in members],
        }

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
                'gender': member.gender,
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
                'average_score': round(sum(weeks.mapped('score')) / len(weeks), 1) if weeks else 0,
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
            followup.write({'target_cell_id': cell_id, 'target_age_group_id': group_id})
            followup.action_integrate()
        elif action == 'abandon':
            followup.action_abandon()
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

    @http.route('/api/church/settings', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def church_settings(self, user, **kwargs):
        """Réglages de l'église ; un responsable peut changer la durée de suivi par défaut."""
        church = request.env['church.church'].sudo().browse(self._resolve_church_id(user, kwargs))
        if 'default_followup_weeks' in kwargs:
            if not self._is_manager(user):
                return _error('Action non autorisée pour votre rôle.', 'forbidden')
            church.write({'default_followup_weeks': _int(
                kwargs, 'default_followup_weeks', True, 'durée de suivi par défaut')})
        return {
            'status': 'success',
            'settings': {'church_id': church.id, 'default_followup_weeks': church.default_followup_weeks},
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
        """Message de partage des identifiants.

        Le PIN n'étant plus conservé en clair, partager revient à en générer un
        nouveau : l'ancien cesse de fonctionner.
        """
        target = self._get_account(user, kwargs)
        pin = target._issue_pin()
        return {
            'status': 'success',
            'message': target.get_share_message(pin),
            'phone': target.phone,
            'pin_regenerated': True,
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
                    'rate': round(evangelist.integration_rate, 1),
                },
                'followups': [{
                    'name': f.name,
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
                'pin_set': bool(u.pin_set_date),
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
        return account._issue_pin() if account else ''

    @http.route('/api/church/cell_leader/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def create_cell_leader(self, user, **kwargs):
        """Créer un responsable de cellule (manager/super_admin uniquement)."""
        pin = self._create_leader(user, kwargs, 'church.prayer.cell', 'prayer_cell_id', 'Cellule')
        return {'status': 'success', 'message': 'Responsable de cellule créé', 'pin': pin}

    @http.route('/api/church/group_leader/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=MANAGERS)
    def create_group_leader(self, user, **kwargs):
        """Créer un responsable de groupe d'âge (manager/super_admin uniquement)."""
        pin = self._create_leader(user, kwargs, 'church.age.group', 'age_group_id', 'Groupe d\'âge')
        return {'status': 'success', 'message': 'Responsable de groupe créé', 'pin': pin}

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
        new_user = request.env['church.mobile.user'].sudo().create({
            'name': name,
            'phone': phone,
            'role': role,
            'church_id': self._resolve_church_id(user, kwargs),
            'evangelist_id': self._ref('church.evangelist', user, kwargs, 'evangelist_id', 'Évangéliste'),
            'prayer_cell_id': self._ref('church.prayer.cell', user, kwargs, 'prayer_cell_id', 'Cellule'),
            'age_group_id': self._ref('church.age.group', user, kwargs, 'age_group_id', 'Groupe d\'âge'),
        })
        return {
            'status': 'success',
            'message': 'Utilisateur %s créé avec le rôle %s' % (name, role),
            'user': {
                'id': new_user.id,
                'name': new_user.name,
                'phone': new_user.phone,
                'role': new_user.role,
                'pin': new_user._issue_pin(),
            },
        }

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
        if vals:
            target.write(vals)
        return {
            'status': 'success',
            'message': 'Utilisateur mis à jour',
            'user': {'id': target.id, 'name': target.name, 'role': target.role, 'active': target.active},
        }

    @http.route('/api/church/admin/reset_pin', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def admin_reset_pin(self, user, **kwargs):
        """Régénérer le PIN d'un utilisateur (super_admin uniquement)."""
        target = self._get_account(user, kwargs)
        return {'status': 'success', 'message': 'PIN régénéré pour %s' % target.name, 'pin': target._issue_pin()}

    # ─── Church Management (super_admin only) ─────────────────────────

    @http.route('/api/church/churches', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def get_churches(self, user, **kwargs):
        """Liste de toutes les églises (super_admin uniquement)."""
        churches = request.env['church.church'].sudo().with_context(active_test=False).search([])
        return {
            'status': 'success',
            'churches': [{
                'id': c.id,
                'name': c.name,
                'code': c.code or '',
                'address': c.address or '',
                'city': c.city or '',
                'phone': c.phone or '',
                'email': c.email or '',
                'pastor_name': c.pastor_name or '',
                'pastors': [{
                    'id': p.id,
                    'name': p.name,
                    'pastor_type': p.pastor_type,
                    'phone': p.phone or '',
                } for p in c.pastor_ids.filtered('active')],
                'active': c.active,
                'member_count': c.member_count,
                'evangelist_count': c.evangelist_count,
                'cell_count': c.cell_count,
            } for c in churches],
        }

    @http.route('/api/church/churches/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def create_church(self, user, **kwargs):
        """Créer une nouvelle église (super_admin uniquement)."""
        code = _text(kwargs, 'code')
        Church = request.env['church.church'].sudo()
        if code and Church.with_context(active_test=False).search_count([('code', '=', code)]):
            raise ApiInputError('Ce code est déjà utilisé par une autre église.')
        church = Church.create({
            'name': _text(kwargs, 'name', True, 'nom'),
            'code': code or False,
            'address': _text(kwargs, 'address') or False,
            'city': _text(kwargs, 'city') or False,
            'phone': _text(kwargs, 'phone') or False,
            'email': _text(kwargs, 'email') or False,
        })
        pastors = kwargs.get('pastors') or []
        if not isinstance(pastors, list):
            raise ApiInputError('« pastors » doit être une liste.')
        for pd in pastors:
            if not isinstance(pd, dict) or not _text(pd, 'name'):
                continue
            request.env['church.pastor'].sudo().create({
                'name': _text(pd, 'name'),
                'phone': _text(pd, 'phone') or False,
                'pastor_type': _choice('church.pastor', 'pastor_type', pd.get('pastor_type') or 'assistant', 'type'),
                'church_id': church.id,
            })
        return {
            'status': 'success',
            'message': 'Église « %s » créée avec succès' % church.name,
            'church': {'id': church.id, 'name': church.name, 'code': church.code or ''},
        }

    def _get_church(self, kwargs):
        church = request.env['church.church'].sudo().with_context(active_test=False).browse(
            _int(kwargs, 'church_id', True, 'église'))
        if not church.exists():
            raise ApiInputError('Église non trouvée.')
        return church

    @http.route('/api/church/churches/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def update_church(self, user, **kwargs):
        """Mettre à jour une église (super_admin uniquement)."""
        church = self._get_church(kwargs)
        vals = {}
        for f in ('name', 'code', 'address', 'city', 'phone', 'email'):
            if f in kwargs:
                vals[f] = _text(kwargs, f) or False
        if 'name' in vals and not vals['name']:
            raise ApiInputError('Le nom est requis.')
        if 'active' in kwargs:
            vals['active'] = _bool(kwargs, 'active')
        if 'default_followup_weeks' in kwargs:
            vals['default_followup_weeks'] = _int(kwargs, 'default_followup_weeks', True, 'durée de suivi par défaut')
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
            'church': {
                'id': church.id,
                'name': church.name,
                'code': church.code or '',
                'address': church.address or '',
                'city': church.city or '',
                'phone': church.phone or '',
                'email': church.email or '',
                'pastor_name': church.pastor_name or '',
                'pastors': [{
                    'id': p.id,
                    'name': p.name,
                    'pastor_type': p.pastor_type,
                    'phone': p.phone or '',
                    'start_date': str(p.start_date) if p.start_date else '',
                } for p in church.pastor_ids.filtered('active')],
                'active': church.active,
                'member_count': church.member_count,
                'evangelist_count': church.evangelist_count,
                'cell_count': church.cell_count,
                'age_group_count': church.age_group_count,
                'default_followup_weeks': church.default_followup_weeks,
                'active_followups': len(followups.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)),
                'total_integrated': len(followups.filtered(lambda f: f.state == 'integrated')),
                'managers': [{'id': m.id, 'name': m.name, 'phone': m.phone} for m in managers],
            },
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
        })
        return {
            'status': 'success',
            'message': 'Responsable « %s » créé pour %s' % (new_manager.name, church.name),
            'user': {
                'id': new_manager.id,
                'name': new_manager.name,
                'phone': new_manager.phone,
                'role': new_manager.role,
                'pin': new_manager._issue_pin(),
                'church_name': church.name,
            },
        }

    # ─── Pastor Management ──────────────────────────────────────────

    @http.route('/api/church/pastors', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint()
    def get_pastors(self, user, **kwargs):
        """Liste des pasteurs : son église, ou n'importe laquelle pour le super admin."""
        domain = [('active', '=', True)]
        church_id = _int(kwargs, 'church_id', label='église')
        if user.role != 'super_admin':
            church_id = user.church_id.id
        if church_id:
            domain.append(('church_id', '=', church_id))
        pastors = request.env['church.pastor'].sudo().search(domain, order='pastor_type, name')
        return {
            'status': 'success',
            'pastors': [{
                'id': p.id,
                'name': p.name,
                'phone': p.phone or '',
                'pastor_type': p.pastor_type,
                'start_date': str(p.start_date) if p.start_date else '',
                'church_id': p.church_id.id,
                'church_name': p.church_id.name,
            } for p in pastors],
        }

    @http.route('/api/church/pastors/create', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def create_pastor(self, user, **kwargs):
        """Créer un pasteur (super_admin uniquement)."""
        church = self._get_church(kwargs)
        pastor = request.env['church.pastor'].sudo().create({
            'name': _text(kwargs, 'name', True, 'nom'),
            'phone': _text(kwargs, 'phone') or False,
            'pastor_type': _choice('church.pastor', 'pastor_type',
                                   kwargs.get('pastor_type') or 'assistant', 'type'),
            'church_id': church.id,
            'start_date': _date(kwargs, 'start_date', 'date d\'entrée en fonction'),
        })
        return {
            'status': 'success',
            'message': 'Pasteur « %s » ajouté à %s' % (pastor.name, church.name),
            'pastor': {
                'id': pastor.id,
                'name': pastor.name,
                'pastor_type': pastor.pastor_type,
                'phone': pastor.phone or '',
                'church_id': church.id,
            },
        }

    def _get_pastor(self, kwargs):
        pastor = request.env['church.pastor'].sudo().with_context(active_test=False).browse(
            _int(kwargs, 'pastor_id', True, 'pasteur'))
        if not pastor.exists():
            raise ApiInputError('Pasteur non trouvé.')
        return pastor

    @http.route('/api/church/pastors/update', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def update_pastor(self, user, **kwargs):
        """Mettre à jour un pasteur (super_admin uniquement)."""
        pastor = self._get_pastor(kwargs)
        vals = {}
        if 'name' in kwargs:
            vals['name'] = _text(kwargs, 'name', True, 'nom')
        if 'phone' in kwargs:
            vals['phone'] = _text(kwargs, 'phone') or False
        if 'pastor_type' in kwargs:
            vals['pastor_type'] = _choice('church.pastor', 'pastor_type', kwargs['pastor_type'], 'type')
        if 'start_date' in kwargs:
            vals['start_date'] = _date(kwargs, 'start_date', 'date d\'entrée en fonction')
        if 'active' in kwargs:
            vals['active'] = _bool(kwargs, 'active')
        if vals:
            pastor.write(vals)
        return {'status': 'success', 'message': 'Pasteur mis à jour'}

    @http.route('/api/church/pastors/delete', type='jsonrpc', auth='public', methods=['POST'], csrf=False)
    @church_endpoint(roles=('super_admin',))
    def delete_pastor(self, user, **kwargs):
        """Archiver un pasteur (super_admin uniquement)."""
        pastor = self._get_pastor(kwargs)
        pastor.write({'active': False})
        return {'status': 'success', 'message': 'Pasteur « %s » archivé' % pastor.name}
