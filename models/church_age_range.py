from odoo import api, fields, models, _


class ChurchAgeRange(models.Model):
    _name = 'church.age.range'
    _description = 'Tranche d\'âge'
    _order = 'sequence, name'

    name = fields.Char(string='Nom', required=True)
    sequence = fields.Integer(string='Séquence', default=10)
    age_min = fields.Integer(string='Âge minimum')
    age_max = fields.Integer(string='Âge maximum')
    for_married = fields.Boolean(string='Pour les mariés', default=True)
    church_id = fields.Many2one('church.church', string='Église',
                                 help='Laisser vide pour une tranche globale')
    active = fields.Boolean(default=True)
