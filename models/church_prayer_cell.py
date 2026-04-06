from odoo import api, fields, models, _
from odoo.exceptions import UserError


class ChurchPrayerCell(models.Model):
    _name = 'church.prayer.cell'
    _description = 'Cellule de prière'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Nom de la cellule', required=True, tracking=True)
    church_id = fields.Many2one('church.church', string='Église', required=True, ondelete='cascade')
    district_ids = fields.Many2many('church.district', string='Quartiers couverts')
    leader_name = fields.Char(string='Responsable')
    leader_phone = fields.Char(string='Téléphone du responsable')
    mobile_user_id = fields.Many2one('church.mobile.user', string='Compte mobile responsable', readonly=True)

    # Horaire
    meeting_day = fields.Selection([
        ('monday', 'Lundi'),
        ('tuesday', 'Mardi'),
        ('wednesday', 'Mercredi'),
        ('thursday', 'Jeudi'),
        ('friday', 'Vendredi'),
        ('saturday', 'Samedi'),
        ('sunday', 'Dimanche'),
    ], string='Jour de réunion', default='friday')
    meeting_time = fields.Char(string='Heure de réunion', default='19:00')
    meeting_location = fields.Char(string='Lieu de réunion')

    # Membres
    member_ids = fields.One2many('church.member', 'prayer_cell_id', string='Membres')
    member_count = fields.Integer(compute='_compute_member_count', store=True, string='Nombre de membres')

    active = fields.Boolean(default=True)
    notes = fields.Text(string='Notes')

    @api.depends('member_ids')
    def _compute_member_count(self):
        for rec in self:
            rec.member_count = len(rec.member_ids)

    def action_view_members(self):
        return {
            'type': 'ir.actions.act_window',
            'name': _('Membres de la cellule'),
            'res_model': 'church.member',
            'view_mode': 'list,form',
            'domain': [('prayer_cell_id', '=', self.id)],
        }

    def action_create_leader_account(self):
        """Créer un compte mobile pour le responsable de cellule."""
        self.ensure_one()
        if self.mobile_user_id:
            return
        if not self.leader_phone:
            raise UserError(_('Veuillez renseigner le téléphone du responsable avant de créer le compte.'))
        mobile_user = self.env['church.mobile.user'].create({
            'name': self.leader_name or self.name,
            'phone': self.leader_phone,
            'role': 'cell_leader',
            'church_id': self.church_id.id,
            'prayer_cell_id': self.id,
        })
        self.mobile_user_id = mobile_user.id
