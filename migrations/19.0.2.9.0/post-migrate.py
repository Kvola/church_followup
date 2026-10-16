"""Profil des personnes déjà enregistrées.

Le champ arrive avec « Nouvelle personne » partout. Est un ancien membre :
- qui est enregistré comme tel ;
- ou qui est intégré / affermi sans être jamais passé par un suivi (inscrit
  directement dans sa cellule ou son groupe).
"""


def migrate(cr, version):
    cr.execute("""
        UPDATE church_member m SET person_profile = 'old_member'
         WHERE m.member_type = 'old_member'
            OR (m.member_type IN ('integrated', 'established')
                AND NOT EXISTS (SELECT 1 FROM church_followup f WHERE f.member_id = m.id))
    """)
    cr.execute("""
        UPDATE church_followup f SET person_profile = m.person_profile
          FROM church_member m WHERE m.id = f.member_id
    """)
