from odoo import _, api, fields, models
from odoo.exceptions import UserError


class ChurchPastor(models.Model):
    _name = 'church.pastor'
    _description = 'Pasteur'
    _inherit = ['mail.thread']
    _order = 'pastor_type, name'

    name = fields.Char(string='Nom complet', required=True, tracking=True)
    phone = fields.Char(string='Téléphone', tracking=True)
    photo = fields.Image(string='Photo', max_width=512, max_height=512)
    start_date = fields.Date(string='Date d\'entrée en fonction', tracking=True)
    pastor_type = fields.Selection([
        ('principal', 'Pasteur principal'),
        ('assistant', 'Pasteur assistant'),
    ], string='Type', default='assistant', required=True, tracking=True)
    active = fields.Boolean(default=True)

    church_id = fields.Many2one(
        'church.church', string='Église', required=True,
        ondelete='cascade', tracking=True,
    )

    _name_church_uniq = models.Constraint(
        'UNIQUE(name, church_id)',
        'Ce pasteur est déjà enregistré dans cette église.',
    )

    # Un seul pasteur principal actif par église, garanti par la base même en
    # cas d'écritures simultanées. Le changer passe par action_set_principal.
    _one_principal_per_church = models.UniqueIndex(
        "(church_id) WHERE pastor_type = 'principal' AND active IS TRUE",
        "Cette église a déjà un pasteur principal actif. Utilisez « Désigner pasteur "
        "principal » sur le nouveau : l'actuel deviendra pasteur assistant.",
    )

    def action_set_principal(self):
        """Désigne ce pasteur comme principal ; l'actuel devient assistant."""
        self.ensure_one()
        if not self.active:
            raise UserError(_("Un pasteur archivé ne peut pas être désigné pasteur principal."))
        if self.pastor_type == 'principal':
            return
        current = self.search([('church_id', '=', self.church_id.id), ('pastor_type', '=', 'principal'),
                               ('active', '=', True), ('id', '!=', self.id)])
        current.write({'pastor_type': 'assistant'})
        # L'index n'admet qu'un principal à la fois : la rétrogradation doit
        # atteindre la base AVANT la promotion (Odoo n'ordonne pas ses écritures).
        current.flush_recordset(['pastor_type'])
        self.pastor_type = 'principal'
        self.church_id.message_post(body=_(
            "%(new)s devient pasteur principal%(previous)s.", new=self.name,
            previous=_(" (succède à %s)") % ', '.join(current.mapped('name')) if current else ''))
