from odoo import api, fields, models, _


class ChurchDistrict(models.Model):
    _name = 'church.district'
    _description = 'Quartier'
    _order = 'name'

    name = fields.Char(string='Nom du quartier', required=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    city = fields.Char(string='Ville')
    description = fields.Text(string='Description')
    active = fields.Boolean(default=True)

    prayer_cell_id = fields.Many2one('church.prayer.cell', string='Cellule de prière', compute='_compute_prayer_cell', store=True)
    member_count = fields.Integer(compute='_compute_member_count', string='Nombre de membres')
    member_ids = fields.One2many('church.member', 'district_id', string='Membres')

    @api.depends('church_id.prayer_cell_ids.district_ids')
    def _compute_prayer_cell(self):
        for rec in self:
            cell = self.env['church.prayer.cell'].search([
                ('church_id', '=', rec.church_id.id),
                ('district_ids', 'in', rec.id),
            ], limit=1)
            rec.prayer_cell_id = cell.id if cell else False

    @api.depends('member_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)
