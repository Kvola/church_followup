import hashlib
import logging
from odoo import http, fields, _
from odoo.http import request

_logger = logging.getLogger(__name__)


class ChurchMobileApi(http.Controller):
    """API REST pour l'application mobile de suivi d'évangélisation."""

    # ─── Authentication ───────────────────────────────────────────────

    @http.route('/api/church/auth/login', type='json', auth='public', methods=['POST'], csrf=False)
    def login(self, **kwargs):
        """Connexion via téléphone + PIN."""
        phone = kwargs.get('phone', '').strip()
        pin = kwargs.get('pin', '').strip()
        db = kwargs.get('db', request.db)

        if not phone or not pin:
            return {'status': 'error', 'message': 'Téléphone et PIN requis'}

        try:
            user = request.env['church.mobile.user'].sudo().search([
                ('phone', '=', phone),
                ('pin', '=', pin),
                ('active', '=', True),
            ], limit=1)

            if not user:
                return {'status': 'error', 'message': 'Identifiants incorrects'}

            # Build user data
            data = {
                'id': user.id,
                'name': user.name,
                'phone': user.phone,
                'role': user.role,
                'church_id': user.church_id.id,
                'church_name': user.church_id.name,
            }

            if user.role == 'evangelist' and user.evangelist_id:
                data['evangelist_id'] = user.evangelist_id.id
            elif user.role == 'cell_leader' and user.prayer_cell_id:
                data['prayer_cell_id'] = user.prayer_cell_id.id
            elif user.role == 'group_leader' and user.age_group_id:
                data['age_group_id'] = user.age_group_id.id

            # Generate a simple token
            token = hashlib.sha256(
                f"{user.id}:{user.pin}:{fields.Datetime.now()}".encode()
            ).hexdigest()

            return {
                'status': 'success',
                'message': 'Connexion réussie',
                'user': data,
                'token': token,
            }
        except Exception as e:
            _logger.exception("Login error")
            return {'status': 'error', 'message': str(e)}

    def _get_mobile_user(self, kwargs):
        """Helper to get authenticated mobile user."""
        user_id = kwargs.get('user_id')
        if not user_id:
            return None
        try:
            user_id = int(user_id)
        except (ValueError, TypeError):
            return None
        user = request.env['church.mobile.user'].sudo().browse(user_id)
        if user.exists() and user.active:
            return user
        return None

    @staticmethod
    def _safe_int(value, field_name=''):
        """Safely convert a value to int, raising a clear error message."""
        if not value:
            return None
        try:
            return int(value)
        except (ValueError, TypeError):
            raise ValueError(_('Valeur invalide pour %s') % field_name)

    # ─── Dashboard ────────────────────────────────────────────────────

    @http.route('/api/church/dashboard', type='json', auth='public', methods=['POST'], csrf=False)
    def get_dashboard(self, **kwargs):
        """Tableau de bord du responsable."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        try:
            church_id = user.church_id.id
            church_name = user.church_id.name

            followups = request.env['church.followup'].sudo().search([('church_id', '=', church_id)])
            evangelists = request.env['church.evangelist'].sudo().search([('church_id', '=', church_id)])
            members = request.env['church.member'].sudo().search([('church_id', '=', church_id)])
            cells = request.env['church.prayer.cell'].sudo().search([('church_id', '=', church_id)])
            groups = request.env['church.age.group'].sudo().search([('church_id', '=', church_id)])

            active_followups = followups.filtered(lambda f: f.state == 'in_progress')
            integrated = followups.filtered(lambda f: f.state == 'integrated')
            abandoned = followups.filtered(lambda f: f.state == 'abandoned')

            # Stats par évangéliste
            evangelist_stats = []
            for ev in evangelists:
                ev_followups = followups.filtered(lambda f: f.evangelist_id.id == ev.id)
                ev_integrated = ev_followups.filtered(lambda f: f.state == 'integrated')
                ev_active = ev_followups.filtered(lambda f: f.state == 'in_progress')
                completed = len(ev_followups.filtered(lambda f: f.state in ('integrated', 'abandoned')))
                rate = (len(ev_integrated) / completed * 100) if completed else 0

                evangelist_stats.append({
                    'id': ev.id,
                    'name': ev.name,
                    'active_count': len(ev_active),
                    'integrated_count': len(ev_integrated),
                    'total_count': len(ev_followups),
                    'integration_rate': round(rate, 1),
                })

            return {
                'status': 'success',
                'dashboard': {
                    'church_name': church_name,
                    'total_members': len(members),
                    'total_evangelists': len(evangelists),
                    'total_cells': len(cells),
                    'total_groups': len(groups),
                    'active_followups': len(active_followups),
                    'total_integrated': len(integrated),
                    'total_abandoned': len(abandoned),
                    'integration_rate': round(
                        len(integrated) / (len(integrated) + len(abandoned)) * 100, 1
                    ) if (len(integrated) + len(abandoned)) > 0 else 0,
                    'evangelist_stats': evangelist_stats,
                },
            }
        except Exception as e:
            _logger.exception("Dashboard error")
            return {'status': 'error', 'message': str(e)}

    # ─── Evangelists ──────────────────────────────────────────────────

    @http.route('/api/church/evangelists', type='json', auth='public', methods=['POST'], csrf=False)
    def get_evangelists(self, **kwargs):
        """Liste des évangélistes de l'église."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        evangelists = request.env['church.evangelist'].sudo().search([
            ('church_id', '=', user.church_id.id),
        ])

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

    @http.route('/api/church/evangelist/create', type='json', auth='public', methods=['POST'], csrf=False)
    def create_evangelist(self, **kwargs):
        """Créer un évangéliste (rôle manager uniquement)."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role != 'manager':
            return {'status': 'error', 'message': 'Non autorisé'}

        name = kwargs.get('name', '').strip()
        phone = kwargs.get('phone', '').strip()

        if not name or not phone:
            return {'status': 'error', 'message': 'Nom et téléphone requis'}

        evangelist = request.env['church.evangelist'].sudo().create({
            'name': name,
            'phone': phone,
            'church_id': user.church_id.id,
        })

        return {
            'status': 'success',
            'message': 'Évangéliste créé',
            'evangelist': {
                'id': evangelist.id,
                'name': evangelist.name,
                'phone': evangelist.phone,
                'pin': evangelist.mobile_user_id.pin if evangelist.mobile_user_id else '',
            },
        }

    # ─── Members ──────────────────────────────────────────────────────

    @http.route('/api/church/members', type='json', auth='public', methods=['POST'], csrf=False)
    def get_members(self, **kwargs):
        """Liste des membres de l'église."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        domain = [('church_id', '=', user.church_id.id)]
        member_type = kwargs.get('member_type')
        if member_type:
            domain.append(('member_type', '=', member_type))

        members = request.env['church.member'].sudo().search(domain)

        return {
            'status': 'success',
            'members': [{
                'id': m.id,
                'name': m.name,
                'first_name': m.first_name,
                'phone': m.phone or '',
                'gender': m.gender,
                'district_id': m.district_id.id if m.district_id else False,
                'district_name': m.district_id.name if m.district_id else '',
                'member_type': m.member_type,
                'prayer_cell_id': m.prayer_cell_id.id if m.prayer_cell_id else False,
                'prayer_cell_name': m.prayer_cell_id.name if m.prayer_cell_id else '',
                'age_group_id': m.age_group_id.id if m.age_group_id else False,
                'age_group_name': m.age_group_id.name if m.age_group_id else '',
                'age': m.age,
                'marital_status': m.marital_status,
            } for m in members],
        }

    @http.route('/api/church/member/create', type='json', auth='public', methods=['POST'], csrf=False)
    def create_member(self, **kwargs):
        """Créer un nouveau membre/personne."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        required = ['name', 'first_name', 'gender']
        for field in required:
            if not kwargs.get(field, '').strip():
                return {'status': 'error', 'message': f'Le champ {field} est requis'}

        vals = {
            'name': kwargs['name'].strip(),
            'first_name': kwargs['first_name'].strip(),
            'gender': kwargs['gender'],
            'church_id': user.church_id.id,
            'phone': kwargs.get('phone', '').strip() or False,
            'address': kwargs.get('address', '').strip() or False,
            'city': kwargs.get('city', '').strip() or False,
            'profession': kwargs.get('profession', '').strip() or False,
            'marital_status': kwargs.get('marital_status', 'single'),
            'date_of_birth': kwargs.get('date_of_birth') or False,
            'salvation_date': kwargs.get('salvation_date') or False,
            'notes': kwargs.get('notes', '').strip() or False,
        }

        district_id = kwargs.get('district_id')
        if district_id:
            try:
                vals['district_id'] = int(district_id)
            except (ValueError, TypeError):
                return {'status': 'error', 'message': 'district_id invalide'}

        member_type = kwargs.get('member_type', 'new')
        vals['member_type'] = member_type

        # Si ajouté par un responsable de cellule, affecter directement
        if user.role == 'cell_leader' and user.prayer_cell_id:
            vals['prayer_cell_id'] = user.prayer_cell_id.id
            vals['member_type'] = 'old_member'

        # Si ajouté par un responsable de groupe, affecter directement
        if user.role == 'group_leader' and user.age_group_id:
            vals['age_group_id'] = user.age_group_id.id
            vals['member_type'] = 'old_member'

        member = request.env['church.member'].sudo().create(vals)

        return {
            'status': 'success',
            'message': 'Membre créé',
            'member': {'id': member.id, 'name': member.display_name_custom},
        }

    @http.route('/api/church/member/detail', type='json', auth='public', methods=['POST'], csrf=False)
    def get_member_detail(self, **kwargs):
        """Détail d'un membre."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        member_id = kwargs.get('member_id')
        if not member_id:
            return {'status': 'error', 'message': 'member_id requis'}

        try:
            member = request.env['church.member'].sudo().browse(int(member_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'member_id invalide'}
        if not member.exists() or member.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Membre non trouvé'}

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
                'district_id': member.district_id.id if member.district_id else False,
                'prayer_cell_id': member.prayer_cell_id.id if member.prayer_cell_id else False,
                'age_group_id': member.age_group_id.id if member.age_group_id else False,
            },
        }

    @http.route('/api/church/member/update', type='json', auth='public', methods=['POST'], csrf=False)
    def update_member(self, **kwargs):
        """Mettre à jour un membre."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        member_id = kwargs.get('member_id')
        if not member_id:
            return {'status': 'error', 'message': 'member_id requis'}

        try:
            member = request.env['church.member'].sudo().browse(int(member_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'member_id invalide'}
        if not member.exists() or member.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Membre non trouvé'}

        allowed_fields = [
            'name', 'first_name', 'phone', 'gender', 'date_of_birth',
            'address', 'profession', 'marital_status', 'member_type', 'notes',
        ]
        vals = {}
        for f in allowed_fields:
            if f in kwargs:
                vals[f] = kwargs[f] if kwargs[f] else False

        int_fields = ['district_id', 'prayer_cell_id', 'age_group_id']
        for f in int_fields:
            if f in kwargs:
                try:
                    vals[f] = int(kwargs[f]) if kwargs[f] else False
                except (ValueError, TypeError):
                    return {'status': 'error', 'message': f'{f} invalide'}

        if vals:
            member.write(vals)

        return {'status': 'success', 'success': True, 'message': 'Membre mis à jour'}

    # ─── Followups ────────────────────────────────────────────────────

    @http.route('/api/church/followups', type='json', auth='public', methods=['POST'], csrf=False)
    def get_followups(self, **kwargs):
        """Liste des suivis."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        domain = [('church_id', '=', user.church_id.id)]

        # Évangéliste ne voit que ses propres suivis
        my_only = kwargs.get('my_only', False)
        if my_only and user.role == 'evangelist' and user.evangelist_id:
            domain.append(('evangelist_id', '=', user.evangelist_id.id))
        elif user.role == 'evangelist' and user.evangelist_id:
            domain.append(('evangelist_id', '=', user.evangelist_id.id))

        state = kwargs.get('state')
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
                'total_weeks': f.duration_weeks,
                'current_week': f.week_count,
                'progress': round(f.week_count / f.duration_weeks * 100, 1) if f.duration_weeks else 0,
                'state': f.state,
                'week_count': f.week_count,
                'weeks': [{
                    'id': w.id,
                    'week_number': w.week_number,
                    'date': str(w.date) if w.date else '',
                    'sunday_attendance': w.sunday_attendance,
                    'call_made': w.call_made,
                    'visit_made': w.visit_made,
                    'spiritual_state': w.spiritual_state or '',
                    'score': w.score,
                    'notes': w.notes or '',
                } for w in f.week_ids],
            } for f in followups],
        }

    @http.route('/api/church/followup/create', type='json', auth='public', methods=['POST'], csrf=False)
    def create_followup(self, **kwargs):
        """Créer un nouveau suivi."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        member_id = kwargs.get('member_id')
        evangelist_id = kwargs.get('evangelist_id')

        if not member_id:
            return {'status': 'error', 'message': 'Membre requis'}

        # Si l'utilisateur est un évangéliste, utiliser son ID
        if user.role == 'evangelist' and user.evangelist_id:
            evangelist_id = user.evangelist_id.id
        elif not evangelist_id:
            return {'status': 'error', 'message': 'Évangéliste requis'}

        try:
            vals = {
                'church_id': user.church_id.id,
                'evangelist_id': int(evangelist_id),
                'member_id': int(member_id),
            }
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'IDs invalides'}
        total_weeks = kwargs.get('total_weeks')
        if total_weeks:
            try:
                vals['duration_weeks'] = int(total_weeks)
            except (ValueError, TypeError):
                return {'status': 'error', 'message': 'Nombre de semaines invalide'}

        followup = request.env['church.followup'].sudo().create(vals)

        return {
            'status': 'success',
            'success': True,
            'message': 'Suivi créé',
            'followup': {
                'id': followup.id,
                'name': followup.name,
            },
        }

    @http.route('/api/church/followup/detail', type='json', auth='public', methods=['POST'], csrf=False)
    def get_followup_detail(self, **kwargs):
        """Détail d'un suivi."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        followup_id = kwargs.get('followup_id')
        if not followup_id:
            return {'status': 'error', 'message': 'followup_id requis'}

        try:
            f = request.env['church.followup'].sudo().browse(int(followup_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'followup_id invalide'}
        if not f.exists() or f.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Suivi non trouvé'}

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
                'progress': round(f.week_count / f.duration_weeks * 100, 1) if f.duration_weeks else 0,
                'average_score': round(sum(w.score for w in f.week_ids) / len(f.week_ids), 1) if f.week_ids else 0,
                'weeks': [{
                    'id': w.id,
                    'week_number': w.week_number,
                    'sunday_attendance': w.sunday_attendance,
                    'call_made': w.call_made,
                    'visit_made': w.visit_made,
                    'spiritual_state': w.spiritual_state or '',
                    'score': w.score,
                    'notes': w.notes or '',
                } for w in f.week_ids.sorted('week_number')],
            },
        }

    @http.route('/api/church/followup/week/save', type='json', auth='public', methods=['POST'], csrf=False)
    def save_followup_week(self, **kwargs):
        """Enregistrer un rapport hebdomadaire."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        followup_id = kwargs.get('followup_id')
        week_number = kwargs.get('week_number')

        if not followup_id or not week_number:
            return {'status': 'error', 'message': 'Suivi et numéro de semaine requis'}

        try:
            followup = request.env['church.followup'].sudo().browse(int(followup_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'followup_id invalide'}
        if not followup.exists() or followup.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Suivi introuvable'}

        # Chercher ou créer le rapport de semaine
        week = request.env['church.followup.week'].sudo().search([
            ('followup_id', '=', followup.id),
            ('week_number', '=', int(week_number)),
        ], limit=1)

        vals = {
            'followup_id': followup.id,
            'week_number': int(week_number),
            'date': fields.Date.today(),
            'sunday_attendance': kwargs.get('sunday_attendance', False),
            'call_made': kwargs.get('call_made', False),
            'visit_made': kwargs.get('visit_made', False),
            'spiritual_state': kwargs.get('spiritual_state', False),
            'notes': kwargs.get('notes', ''),
        }

        if week:
            week.write(vals)
        else:
            week = request.env['church.followup.week'].sudo().create(vals)

        return {
            'status': 'success',
            'message': 'Rapport enregistré',
            'week': {'id': week.id, 'score': week.score},
        }

    @http.route('/api/church/followup/action', type='json', auth='public', methods=['POST'], csrf=False)
    def followup_action(self, **kwargs):
        """Effectuer une action sur un suivi (intégrer, abandonner, etc.)."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        followup_id = kwargs.get('followup_id')
        action = kwargs.get('action')

        if not followup_id or not action:
            return {'status': 'error', 'message': 'Suivi et action requis'}

        try:
            followup = request.env['church.followup'].sudo().browse(int(followup_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'followup_id invalide'}
        if not followup.exists() or followup.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Suivi introuvable'}

        try:
            if action == 'integrate':
                cell_id = kwargs.get('target_cell_id')
                group_id = kwargs.get('target_age_group_id')
                if not cell_id or not group_id:
                    return {'status': 'error', 'message': 'Cellule et groupe d\'âge requis'}
                followup.write({
                    'target_cell_id': int(cell_id),
                    'target_age_group_id': int(group_id),
                })
                followup.action_integrate()
            elif action == 'abandon':
                followup.action_abandon()
            elif action == 'extend':
                followup.action_extend()
            elif action == 'transfer':
                target_id = kwargs.get('transferred_to_id')
                if not target_id:
                    return {'status': 'error', 'message': 'Évangéliste destinataire requis'}
                followup.write({'transferred_to_id': int(target_id)})
                followup.action_transfer()
            else:
                return {'status': 'error', 'message': 'Action inconnue'}

            return {'status': 'success', 'message': 'Action effectuée'}
        except Exception as e:
            return {'status': 'error', 'message': str(e)}

    # ─── Prayer Cells ─────────────────────────────────────────────────

    @http.route('/api/church/cells', type='json', auth='public', methods=['POST'], csrf=False)
    def get_prayer_cells(self, **kwargs):
        """Liste des cellules de prière."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        domain = [('church_id', '=', user.church_id.id)]
        if user.role == 'cell_leader' and user.prayer_cell_id:
            domain.append(('id', '=', user.prayer_cell_id.id))

        cells = request.env['church.prayer.cell'].sudo().search(domain)

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
                    'phone': m.phone or '',
                } for m in c.member_ids],
            } for c in cells],
        }

    # ─── Age Groups ───────────────────────────────────────────────────

    @http.route('/api/church/age_groups', type='json', auth='public', methods=['POST'], csrf=False)
    def get_age_groups(self, **kwargs):
        """Liste des groupes d'âge."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        domain = [('church_id', '=', user.church_id.id)]
        if user.role == 'group_leader' and user.age_group_id:
            domain.append(('id', '=', user.age_group_id.id))

        groups = request.env['church.age.group'].sudo().search(domain)

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
                    'phone': m.phone or '',
                    'age': m.age,
                } for m in g.member_ids],
            } for g in groups],
        }

    # ─── Districts ────────────────────────────────────────────────────

    @http.route('/api/church/districts', type='json', auth='public', methods=['POST'], csrf=False)
    def get_districts(self, **kwargs):
        """Liste des quartiers de l'église."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        districts = request.env['church.district'].sudo().search([
            ('church_id', '=', user.church_id.id),
        ])

        return {
            'status': 'success',
            'districts': [{
                'id': d.id,
                'name': d.name,
                'city': d.city or '',
            } for d in districts],
        }

    # ─── Attendance ───────────────────────────────────────────────────

    @http.route('/api/church/attendance/sunday/save', type='json', auth='public', methods=['POST'], csrf=False)
    def save_sunday_attendance(self, **kwargs):
        """Enregistrer la présence au culte du dimanche."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role not in ('manager', 'group_leader', 'evangelist'):
            return {'status': 'error', 'message': 'Non autorisé'}

        date = kwargs.get('date', str(fields.Date.today()))
        member_ids = kwargs.get('member_ids', [])

        AttSunday = request.env['church.attendance.sunday'].sudo()
        for mid in member_ids:
            try:
                mid_int = int(mid)
            except (ValueError, TypeError):
                continue
            existing = AttSunday.search([
                ('member_id', '=', mid_int),
                ('date', '=', date),
            ], limit=1)

            if not existing:
                AttSunday.create({
                    'church_id': user.church_id.id,
                    'member_id': mid_int,
                    'date': date,
                    'present': True,
                })

        return {'status': 'success', 'success': True, 'message': 'Présences enregistrées'}

    @http.route('/api/church/attendance/cell/save', type='json', auth='public', methods=['POST'], csrf=False)
    def save_cell_attendance(self, **kwargs):
        """Enregistrer la présence à la cellule de prière."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role not in ('manager', 'cell_leader'):
            return {'status': 'error', 'message': 'Non autorisé'}

        date = kwargs.get('date', str(fields.Date.today()))
        prayer_cell_id = kwargs.get('prayer_cell_id')
        member_ids = kwargs.get('member_ids', [])

        if not prayer_cell_id:
            return {'status': 'error', 'message': 'Cellule de prière requise'}

        try:
            cell_id_int = int(prayer_cell_id)
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'prayer_cell_id invalide'}

        AttCell = request.env['church.attendance.cell'].sudo()
        for mid in member_ids:
            try:
                mid_int = int(mid)
            except (ValueError, TypeError):
                continue
            existing = AttCell.search([
                ('member_id', '=', mid_int),
                ('date', '=', date),
                ('prayer_cell_id', '=', cell_id_int),
            ], limit=1)

            if not existing:
                AttCell.create({
                    'church_id': user.church_id.id,
                    'prayer_cell_id': cell_id_int,
                    'member_id': mid_int,
                    'date': date,
                    'present': True,
                })

        return {'status': 'success', 'success': True, 'message': 'Présences enregistrées'}

    # ─── Cooking Rotation ─────────────────────────────────────────────

    @http.route('/api/church/cooking_rotation', type='json', auth='public', methods=['POST'], csrf=False)
    def get_cooking_rotation(self, **kwargs):
        """Programme de rotation cuisine."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        rotations = request.env['church.cooking.rotation'].sudo().search([
            ('church_id', '=', user.church_id.id),
        ], order='date')

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

    @http.route('/api/church/user/share_message', type='json', auth='public', methods=['POST'], csrf=False)
    def get_share_message(self, **kwargs):
        """Obtenir le message de partage des credentials."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role != 'manager':
            return {'status': 'error', 'message': 'Non autorisé'}

        target_user_id = kwargs.get('target_user_id')
        if not target_user_id:
            return {'status': 'error', 'message': 'Utilisateur cible requis'}

        try:
            target = request.env['church.mobile.user'].sudo().browse(int(target_user_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'target_user_id invalide'}
        if not target.exists() or target.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Utilisateur introuvable'}

        message = target.get_share_message()
        return {
            'status': 'success',
            'message': message,
            'phone': target.phone,
        }

    # ─── Report data ──────────────────────────────────────────────────

    @http.route('/api/church/report/followup', type='json', auth='public', methods=['POST'], csrf=False)
    def get_followup_report(self, **kwargs):
        """Données du rapport de suivi par évangéliste."""
        user = self._get_mobile_user(kwargs)
        if not user:
            return {'status': 'error', 'message': 'Non authentifié'}

        evangelist_id = kwargs.get('evangelist_id')
        if not evangelist_id:
            return {'status': 'error', 'message': 'Évangéliste requis'}

        try:
            evangelist = request.env['church.evangelist'].sudo().browse(int(evangelist_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'evangelist_id invalide'}
        if not evangelist.exists() or evangelist.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Évangéliste introuvable'}

        followups = request.env['church.followup'].sudo().search([
            ('evangelist_id', '=', evangelist.id),
        ], order='create_date desc')

        return {
            'status': 'success',
            'report': {
                'evangelist': {
                    'name': evangelist.name,
                    'phone': evangelist.phone or '',
                    'total': len(followups),
                    'active': len(followups.filtered(lambda f: f.state == 'in_progress')),
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

    @http.route('/api/church/mobile_users', type='json', auth='public', methods=['POST'], csrf=False)
    def get_mobile_users(self, **kwargs):
        """Liste des utilisateurs mobiles (manager uniquement)."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role != 'manager':
            return {'status': 'error', 'message': 'Non autorisé'}

        users = request.env['church.mobile.user'].sudo().search([
            ('church_id', '=', user.church_id.id),
        ])

        return {
            'status': 'success',
            'users': [{
                'id': u.id,
                'name': u.name,
                'phone': u.phone,
                'role': u.role,
                'active': u.active,
            } for u in users],
        }

    @http.route('/api/church/cell_leader/create', type='json', auth='public', methods=['POST'], csrf=False)
    def create_cell_leader(self, **kwargs):
        """Créer un responsable de cellule (manager uniquement)."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role != 'manager':
            return {'status': 'error', 'message': 'Non autorisé'}

        name = kwargs.get('name', '').strip()
        phone = kwargs.get('phone', '').strip()
        cell_id = kwargs.get('prayer_cell_id')

        if not name or not phone or not cell_id:
            return {'status': 'error', 'message': 'Nom, téléphone et cellule requis'}

        try:
            cell = request.env['church.prayer.cell'].sudo().browse(int(cell_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'prayer_cell_id invalide'}
        if not cell.exists() or cell.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Cellule introuvable'}

        cell.write({
            'leader_name': name,
            'leader_phone': phone,
        })
        cell.action_create_leader_account()

        return {
            'status': 'success',
            'message': 'Responsable de cellule créé',
            'pin': cell.mobile_user_id.pin if cell.mobile_user_id else '',
        }

    @http.route('/api/church/group_leader/create', type='json', auth='public', methods=['POST'], csrf=False)
    def create_group_leader(self, **kwargs):
        """Créer un responsable de groupe d'âge (manager uniquement)."""
        user = self._get_mobile_user(kwargs)
        if not user or user.role != 'manager':
            return {'status': 'error', 'message': 'Non autorisé'}

        name = kwargs.get('name', '').strip()
        phone = kwargs.get('phone', '').strip()
        group_id = kwargs.get('age_group_id')

        if not name or not phone or not group_id:
            return {'status': 'error', 'message': 'Nom, téléphone et groupe requis'}

        try:
            group = request.env['church.age.group'].sudo().browse(int(group_id))
        except (ValueError, TypeError):
            return {'status': 'error', 'message': 'age_group_id invalide'}
        if not group.exists() or group.church_id.id != user.church_id.id:
            return {'status': 'error', 'message': 'Groupe introuvable'}

        group.write({
            'leader_name': name,
            'leader_phone': phone,
        })
        group.action_create_leader_account()

        return {
            'status': 'success',
            'message': 'Responsable de groupe créé',
            'pin': group.mobile_user_id.pin if group.mobile_user_id else '',
        }
