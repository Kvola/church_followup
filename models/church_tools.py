from odoo.exceptions import ValidationError

# États d'un suivi qui demande encore une décision : un suivi prolongé reste actif.
ACTIVE_FOLLOWUP_STATES = ('in_progress', 'extended')


def check_same_church(records, field_names):
    """Refuse qu'une fiche désigne une fiche liée appartenant à une autre église.

    Chaque champ de ``field_names`` est un Many2one (ou Many2many) vers un modèle
    portant ``church_id``. Une fiche liée sans église est tolérée.
    """
    for rec in records:
        church = rec.church_id
        if not church:
            continue
        for fname in field_names:
            for linked in rec[fname]:
                if linked.church_id and linked.church_id != church:
                    raise ValidationError(rec.env._(
                        "%(record)s appartient à l'église « %(church)s » : « %(field)s » "
                        "ne peut pas désigner « %(linked)s », qui relève de l'église « %(other)s ».",
                        record=rec.display_name,
                        church=church.name,
                        field=rec._fields[fname].string,
                        linked=linked.display_name,
                        other=linked.church_id.name,
                    ))
