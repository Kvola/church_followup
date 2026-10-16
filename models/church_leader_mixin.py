from odoo import _, fields, models
from odoo.exceptions import UserError

from .church_mobile_user import phone_key


class ChurchLeaderMixin(models.AbstractModel):
    """Responsable d'une cellule ou d'un groupe d'âge, et son compte mobile.

    Le compte appartient à une PERSONNE, pas à la cellule : quand le numéro du
    responsable change, l'ancien compte est désactivé (sa session tombe) et le
    nouveau responsable reçoit le sien — l'ancien ne garde plus l'accès.
    """
    _name = 'church.leader.mixin'
    _description = 'Responsable avec compte mobile'

    _leader_role = None        # 'cell_leader' | 'group_leader'
    _leader_link_field = None  # champ du compte qui désigne l'unité

    leader_name = fields.Char(string='Responsable')
    leader_phone = fields.Char(string='Téléphone du responsable')
    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte mobile responsable',
                                     readonly=True, copy=False)

    def _leader_accounts(self):
        """Comptes actifs qui ouvrent cette unité — créés par le bouton de l'unité
        ou ailleurs (administration, API) : seul compte le rattachement."""
        return self.env['church.mobile.user'].sudo().search([
            ('role', '=', self._leader_role), (self._leader_link_field, 'in', self.ids)])

    def write(self, vals):
        stale = self.env['church.mobile.user']
        if 'leader_phone' in vals:
            new_key = phone_key(vals['leader_phone'])
            stale = self._leader_accounts().filtered(lambda a: a.phone_key != new_key)
        res = super().write(vals)
        if stale:
            # Le compte de l'ancien responsable ne doit plus ouvrir cette unité.
            units = self.filtered(lambda r: r in stale.mapped(self._leader_link_field))
            stale.write({'active': False, self._leader_link_field: False})
            super(ChurchLeaderMixin, self.filtered(lambda r: r.mobile_user_id in stale)).write(
                {'mobile_user_id': False})
            for rec in units:
                rec.message_post(body=_("Responsable changé : l'ancien compte mobile est désactivé. "
                                        "Créez celui du nouveau responsable."))
        if vals.get('leader_name'):
            # Même personne, nom corrigé : le compte suit.
            self._leader_accounts().write({'name': vals['leader_name']})
        return res

    def action_create_leader_account(self):
        """Crée (ou réactive) le compte mobile du responsable actuel.

        :return: le compte (sans PIN : il se génère et se partage à part)
        """
        self.ensure_one()
        if self.mobile_user_id.active:
            return self.mobile_user_id
        current = self._leader_accounts().filtered(lambda a: a.phone_key == phone_key(self.leader_phone))
        if current:
            self.mobile_user_id = current[:1]
            return current[:1]
        if not self.leader_phone:
            raise UserError(_('Veuillez renseigner le téléphone du responsable avant de créer le compte.'))
        Users = self.env['church.mobile.user'].sudo().with_context(active_test=False)
        existing = Users.search([('phone_key', '=', phone_key(self.leader_phone)),
                                 ('church_id', '=', self.church_id.id)], limit=1)
        if existing and (existing.active and existing.role != self._leader_role
                         or existing.active and existing[self._leader_link_field]):
            raise UserError(_(
                "Ce numéro a déjà un compte actif dans cette église (%(name)s, %(role)s). "
                "Un compte n'a qu'un rôle : changez le numéro ou le compte existant.",
                name=existing.name, role=existing.get_role_label()))
        vals = {'name': self.leader_name or self.name, 'phone': self.leader_phone,
                'role': self._leader_role, 'church_id': self.church_id.id,
                self._leader_link_field: self.id, 'active': True}
        if existing:
            existing.write(vals)
            account = existing
        else:
            account = Users.create(vals)
        self.mobile_user_id = account
        return account
