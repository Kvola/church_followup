from datetime import timedelta

from odoo import api, fields, models, _

from .church_tools import ACTIVE_FOLLOWUP_STATES, REPORT_GRACE_DAYS


class ChurchFollowup(models.Model):
    _inherit = 'church.followup'

    def _overdue_report_weeks(self, today=None):
        """N° des semaines écoulées dont le rapport manque, délai de grâce passé."""
        self.ensure_one()
        today = today or fields.Date.context_today(self)
        if self.state not in ACTIVE_FOLLOWUP_STATES or not self.start_date:
            return []
        reported = set(self.week_ids.mapped('week_number'))
        overdue = []
        for number in range(1, self.duration_weeks + 1):
            _first, last = self._week_bounds(number)
            if last + timedelta(days=REPORT_GRACE_DAYS) >= today:
                break
            if number not in reported:
                overdue.append(number)
        return overdue

    def _decision_due(self, today=None):
        self.ensure_one()
        today = today or fields.Date.context_today(self)
        return self.state in ACTIVE_FOLLOWUP_STATES and bool(self.end_date) and self.end_date <= today

    # ─── Points d'accroche des relances (voir church_followup_notify) ──

    def _notify_assigned(self):
        """Un suivi vient d'être confié à un évangéliste."""

    def _notify_period_end(self):
        """La période de ces suivis vient d'arriver à terme."""

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records.filtered(lambda f: f.state in ACTIVE_FOLLOWUP_STATES)._notify_assigned()
        return records


class ChurchMobileUser(models.Model):
    _inherit = 'church.mobile.user'

    def _todo_items(self, today=None):
        """Ce que ce compte a à faire, du plus urgent au moins urgent.

        Évangéliste : décisions à prendre et rapports en retard sur SES suivis.
        Responsable : décisions à prendre dans l'église, personnes à attribuer,
        évangélistes en retard. Les autres rôles n'ont pas de tâche de suivi.
        """
        self.ensure_one()
        today = today or fields.Date.context_today(self)
        Followup = self.env['church.followup'].sudo()
        items = []
        if self.role == 'evangelist':
            if not self.evangelist_id:
                return []
            followups = Followup.search([('evangelist_id', '=', self.evangelist_id.id),
                                         ('state', 'in', ACTIVE_FOLLOWUP_STATES)])
        elif self.role in ('manager', 'super_admin'):
            domain = [('state', 'in', ACTIVE_FOLLOWUP_STATES)]
            if self.church_id:
                domain.append(('church_id', '=', self.church_id.id))
            followups = Followup.search(domain)
        else:
            return []

        for f in followups.filtered(lambda f: f._decision_due(today)):
            items.append({
                'kind': 'decision_due', 'followup_id': f.id, 'member_id': f.member_id.id,
                'evangelist_id': f.evangelist_id.id, 'due_date': str(f.end_date),
                'title': _('Décision à prendre : %s') % f.member_id.display_name,
                'detail': _('Suivi arrivé à terme le %s : intégrer, prolonger ou transférer.')
                % f.end_date.strftime('%d/%m/%Y'),
            })

        if self.role == 'evangelist':
            for f in followups:
                for number in f._overdue_report_weeks(today):
                    items.append({
                        'kind': 'report_overdue', 'followup_id': f.id, 'member_id': f.member_id.id,
                        'week_number': number, 'due_date': str(f._week_bounds(number)[1]
                                                               + timedelta(days=REPORT_GRACE_DAYS)),
                        'title': _('Rapport en retard : %(member)s, semaine %(week)s',
                                   member=f.member_id.display_name, week=number),
                        'detail': _('À rédiger dans l\'application.'),
                    })
            return items

        waiting = self.env['church.member'].sudo().search(
            [('member_type', '=', 'new')] + ([('church_id', '=', self.church_id.id)] if self.church_id else []),
            order='create_date')
        for member in waiting:
            items.append({
                'kind': 'to_assign', 'member_id': member.id, 'due_date': str(member.create_date.date()),
                'title': _('À attribuer : %s') % member.display_name,
                'detail': member.proposed_followup_label,
            })
        late = {}
        for f in followups:
            overdue = len(f._overdue_report_weeks(today))
            if overdue:
                late[f.evangelist_id] = late.get(f.evangelist_id, 0) + overdue
        for evangelist, count in sorted(late.items(), key=lambda kv: -kv[1]):
            items.append({
                'kind': 'evangelist_late', 'evangelist_id': evangelist.id,
                'title': _('%(name)s : %(count)s rapport(s) en retard', name=evangelist.name, count=count),
                'detail': _('À relancer.'),
            })
        return items

    def _todo_summary(self, items=None):
        """Résumé d'une ligne (sans retour à la ligne : variable de gabarit WhatsApp)."""
        self.ensure_one()
        items = self._todo_items() if items is None else items
        counts = {}
        for item in items:
            counts[item['kind']] = counts.get(item['kind'], 0) + 1
        labels = (
            ('decision_due', _('%s décision(s) à prendre')),
            ('report_overdue', _('%s rapport(s) en retard')),
            ('to_assign', _('%s personne(s) à attribuer')),
            ('evangelist_late', _('%s évangéliste(s) en retard')),
        )
        return ', '.join(label % counts[kind] for kind, label in labels if counts.get(kind))
