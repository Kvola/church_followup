"""Un numéro, une église : signaler les comptes qui y dérogent déjà.

La règle ne vaut qu'à l'écriture ; les doublons d'avant restent en place
(rien n'est désactivé en silence). On les nomme dans le journal pour que
l'administrateur choisisse, compte par compte, l'église à garder.
"""
import logging

_logger = logging.getLogger(__name__)


def migrate(cr, version):
    for column, label in (('phone_e164', 'numéro'), ('email', 'adresse')):
        cr.execute(f"""
            SELECT u.{column}, string_agg(u.name || ' (#' || u.id || ', église ' || u.church_id || ')', ' ; ')
              FROM church_mobile_user u
             WHERE u.active AND u.role != 'super_admin' AND u.{column} IS NOT NULL
             GROUP BY u.{column}
            HAVING COUNT(DISTINCT u.church_id) > 1
        """)
        for value, accounts in cr.fetchall():
            _logger.warning(
                "Suivi : le %s %s a des comptes dans plusieurs églises — la connexion ouvre le "
                "dernier utilisé. Désactivez ceux en trop (Suivi › Utilisateurs mobiles) : %s",
                label, value, accounts)
