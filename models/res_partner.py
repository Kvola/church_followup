# -*- coding: utf-8 -*-

from odoo import fields, models


class ResPartner(models.Model):
    """Contribution de `church_followup` à la fiche 360° du contact : les fiches
    de personne suivie (évangélisation) rattachées à ce contact.
    """

    _inherit = 'res.partner'

    church_member_ids = fields.One2many(
        'church.member',
        'partner_id',
        string="Fiches d'évangélisation",
    )
    church_member_count = fields.Integer(
        string='Nombre de fiches évangélisation',
        compute='_compute_church_member_count',
    )

    def _compute_church_member_count(self):
        data = self.env['church.member']._read_group(
            [('partner_id', 'in', self.ids)],
            groupby=['partner_id'],
            aggregates=['__count'],
        )
        counts = {partner.id: count for partner, count in data}
        for partner in self:
            partner.church_member_count = counts.get(partner.id, 0)

    def action_view_church_members(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': "Fiches d'évangélisation",
            'res_model': 'church.member',
            'view_mode': 'list,form',
            'domain': [('partner_id', '=', self.id)],
            'context': {'default_partner_id': self.id},
        }
