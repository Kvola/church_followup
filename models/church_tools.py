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


# Durées de suivi, en semaines. Une durée PROPOSÉE (réglage d'église, événement,
# choix initial) reste dans un trimestre ; prolongations comprises, un suivi ne
# dépasse pas un an.
DEFAULT_FOLLOWUP_WEEKS = 4
MAX_PROPOSED_WEEKS = 26
MAX_FOLLOWUP_WEEKS = 52

FOLLOWUP_ORIGINS = [
    ('church', "Réglage de l'église"),
    ('event', "Événement d'origine"),
    ('manual', "Choix d'un responsable"),
]


def check_weeks(records, fname, maximum, allow_empty=False):
    """Refuse une durée hors de [1, maximum] (0 toléré si ``allow_empty``)."""
    for rec in records:
        value = rec[fname]
        if allow_empty and not value:
            continue
        if not 1 <= value <= maximum:
            raise ValidationError(rec.env._(
                "« %(field)s » doit être compris entre 1 et %(max)s semaines (valeur : %(value)s).",
                field=rec._fields[fname].string, max=maximum, value=value,
            ))

ABANDON_REASONS = [
    ('unreachable', 'Injoignable'),
    ('moved', 'A déménagé'),
    ('other_church', 'Fréquente une autre église'),
    ('not_interested', 'Ne souhaite pas poursuivre'),
    ('other', 'Autre raison'),
]

# Un rapport hebdomadaire est en retard trois jours après la fin de sa semaine :
# le temps de couvrir le culte du dimanche et d'appeler la personne.
REPORT_GRACE_DAYS = 3


# Portée des codes de connexion de l'application (otp_auth) : la même pour la
# route qui envoie, celle qui vérifie et le bouton du back-office.
OTP_SCOPE = 'church_followup'
