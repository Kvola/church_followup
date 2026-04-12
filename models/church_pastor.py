from odoo import api, fields, models


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

    _constraints = [
        models.Constraint(
            'UNIQUE(name, church_id)',
            'Ce pasteur est déjà enregistré dans cette église.',
        ),
    ]

    @api.constrains('pastor_type', 'church_id')
    def _check_principal_unique(self):
        for rec in self:
            if rec.pastor_type == 'principal' and rec.active:
                existing = self.search([
                    ('church_id', '=', rec.church_id.id),
                    ('pastor_type', '=', 'principal'),
                    ('active', '=', True),
                    ('id', '!=', rec.id),
                ])
                if existing:
                    # Demote existing principal to assistant
                    existing.write({'pastor_type': 'assistant'})
