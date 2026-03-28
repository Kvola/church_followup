from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class ChurchAgeRange(models.Model):
    _name = 'church.age.range'
    _description = 'Tranche d\'âge'
    _order = 'sequence, name'

    name = fields.Char(string='Nom', required=True)
    sequence = fields.Integer(string='Séquence', default=10)
    age_min = fields.Integer(string='Âge minimum')
    age_max = fields.Integer(string='Âge maximum')
    for_married = fields.Boolean(string='Pour les mariés', default=True)
    church_id = fields.Many2one('church.church', string='Église', ondelete='cascade',
                                 help='Laisser vide pour une tranche globale')
    active = fields.Boolean(default=True)

    @api.constrains('age_min', 'age_max')
    def _check_age_range(self):
        for rec in self:
            if rec.age_min and rec.age_max and rec.age_min >= rec.age_max:
                raise ValidationError(_('L\'âge minimum doit être inférieur à l\'âge maximum.'))
