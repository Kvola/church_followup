# Suivi Évangélisation Église

**Version** : 19.0.1.0.0 | **Licence** : AGPL-3 | **Auteur** : ICP

Module Odoo de suivi d'évangélisation pour les églises, avec application mobile Flutter intégrée.

---

## Fonctionnalités

- Gestion multi-église
- Inscription et suivi des évangélistes
- Suivi des nouvelles personnes (programme de 4 semaines)
- Gestion des cellules de prière par quartier
- Gestion des groupes d'âge configurables
- Suivi des présences (cultes du dimanche et cellules de prière)
- Rotation cuisine des cellules
- Traçabilité du parrainage (inviteur et mentor)
- Rôle Super Administrateur pour la gestion complète via mobile
- Tableaux de bord et rapports PDF
- API REST pour application mobile Flutter

---

## Installation

### Odoo (Backend)

1. Copier le module dans le répertoire `addons`
2. Mettre à jour la liste des modules dans Odoo
3. Installer le module « Suivi Évangélisation Église »

### Application mobile (Flutter)

```bash
cd flutter_app
flutter pub get
flutter build apk --release --split-per-abi
```

Les APKs sont générées dans `flutter_app/build/app/outputs/flutter-apk/`.

---

## Rôles et permissions

| Rôle | Description | Accès mobile |
|------|-------------|--------------|
| **Super Administrateur** | Gestion complète : créer/modifier/désactiver des utilisateurs, changer les rôles, régénérer les PIN | Toutes les fonctionnalités du gestionnaire + gestion des utilisateurs |
| **Gestionnaire (Manager)** | Responsable des évangélistes : tableau de bord, rapports, création d'évangélistes et chefs de cellule/groupe | Tableau de bord, suivis, membres, présences, rapports |
| **Évangéliste** | Suivi des nouvelles personnes : créer des suivis, remplir les rapports hebdomadaires | Mes suivis, membres, présence dimanche |
| **Chef de cellule** | Gestion de sa cellule de prière : membres, présences | Ma cellule, membres, présence cellule |
| **Chef de groupe** | Gestion de son groupe d'âge : membres | Mon groupe, membres |

---

## Flux d'utilisation

### Flux 1 — Configuration initiale par le Super Administrateur

> **Acteur** : Super Administrateur  
> **But** : Mettre en place le système pour une église

1. **Dans Odoo** : créer une fiche **Église** (nom, adresse, pasteur, téléphone)
2. **Dans Odoo** : créer les **Quartiers/Districts** de l'église
3. **Dans Odoo** : créer les **Cellules de prière** (nom, jour de réunion, lieu)
4. **Dans Odoo** : créer les **Groupes d'âge** (Mariés, Jeunes, Universitaires, etc.)
5. **Dans Odoo** : créer un **Utilisateur mobile** avec le rôle `Super Administrateur`
6. **Sur le mobile** : se connecter avec le téléphone + PIN
7. **Sur le mobile** > **Utilisateurs** > **+** : créer un compte **Gestionnaire**
8. Communiquer le PIN généré au gestionnaire (le PIN s'affiche à l'écran et peut être copié)

**Résultat** : L'église est configurée et le gestionnaire peut prendre le relais.

---

### Flux 2 — Création de l'équipe d'évangélisation

> **Acteur** : Gestionnaire  
> **But** : Constituer l'équipe d'évangélistes et de responsables

1. Se connecter sur l'app mobile
2. Aller dans **Évangélistes** > **+ Ajouter** > saisir nom + téléphone
3. Un compte mobile est automatiquement créé pour l'évangéliste (PIN généré)
4. Partager les identifiants (bouton **Partager** sur la fiche utilisateur)
5. Répéter pour chaque évangéliste
6. Aller dans **Utilisateurs** > créer les **Chefs de cellule** et **Chefs de groupe**

**Résultat** : Toute l'équipe a accès à l'application mobile.

---

### Flux 3 — Enregistrement d'un nouveau venu à l'église

> **Acteur** : Évangéliste ou Gestionnaire  
> **But** : Enregistrer une nouvelle personne qui vient à l'église pour la première fois

1. **Membres** > **+ Ajouter**
2. Remplir : Nom, Prénom, Téléphone, Sexe
3. Section **Organisation** : sélectionner le Quartier
4. Section **Parrainage** :
   - **Invité(e) par** : sélectionner le membre de l'église qui a invité cette personne
   - **Mentor** : sélectionner le membre qui sera responsable du suivi spirituel
5. Enregistrer

**Résultat** : Le nouveau venu est enregistré avec le statut « Nouvelle personne » et la traçabilité de son parrainage.

---

### Flux 4 — Lancement d'un suivi d'évangélisation (4 semaines)

> **Acteur** : Évangéliste  
> **But** : Démarrer le programme de suivi de 4 semaines pour un nouveau venu

1. **Suivis** > **+ Nouveau suivi**
2. Sélectionner le **Membre** à suivre (et l'**Évangéliste** si c'est le gestionnaire qui crée)
3. Le suivi démarre automatiquement avec la date du jour et une fin prévue à 4 semaines
4. Chaque semaine, l'évangéliste remplit le **Rapport hebdomadaire** :
   - ✅ Présence au culte du dimanche (3 pts)
   - ✅ Appel téléphonique effectué (2 pts)
   - ✅ Visite effectuée (3 pts)
   - 📊 État spirituel : Excellent (5 pts) / Bon (4 pts) / Moyen (3 pts) / Faible (2 pts) / Critique (1 pt)
   - 📝 Notes de la semaine
5. Le score est calculé automatiquement (max 13 pts/semaine)

**Résultat** : Le suivi est en cours avec un historique détaillé semaine par semaine.

---

### Flux 5 — Intégration d'un nouveau venu

> **Acteur** : Gestionnaire  
> **But** : Intégrer officiellement un nouveau venu dans la vie de l'église

1. Consulter le **Suivi** du membre (état « En cours »)
2. Vérifier les scores et rapports des 4 semaines
3. Sélectionner la **Cellule de prière** d'affectation
4. Sélectionner le **Groupe d'âge** d'affectation
5. Cliquer **Intégrer**

**Résultat** : 
- Le suivi passe à l'état « Intégré »
- Le membre est affecté à la cellule et au groupe
- Son statut passe à « Intégré(e) »
- La date d'intégration est enregistrée

---

### Flux 6 — Prolongation ou transfert d'un suivi

> **Acteur** : Gestionnaire  
> **But** : Gérer les cas où le suivi de 4 semaines ne suffit pas

**Cas A — Prolongation :**
1. Ouvrir le suivi en cours
2. Cliquer **Prolonger** → 4 semaines supplémentaires sont ajoutées

**Cas B — Transfert :**
1. Ouvrir le suivi en cours
2. Cliquer **Transférer** → sélectionner un autre évangéliste
3. Le suivi est transféré avec tout l'historique

**Cas C — Abandon :**
1. Ouvrir le suivi en cours
2. Cliquer **Abandonner** (la personne ne revient plus)

---

### Flux 7 — Suivi des présences au culte du dimanche

> **Acteur** : Évangéliste, Gestionnaire ou Chef de groupe  
> **But** : Enregistrer qui était présent au culte

1. **Présence dimanche** > sélectionner la date
2. Cocher les membres présents dans la liste
3. Enregistrer

**Résultat** : Les présences sont sauvegardées et consultables dans les rapports.

---

### Flux 8 — Suivi des présences à la cellule de prière

> **Acteur** : Chef de cellule ou Gestionnaire  
> **But** : Enregistrer les présences à la réunion de cellule

1. **Présence cellule** > sélectionner la cellule et la date
2. Cocher les membres présents
3. Enregistrer

---

### Flux 9 — Gestion des utilisateurs par le Super Administrateur

> **Acteur** : Super Administrateur  
> **But** : Gérer les accès et permissions de l'équipe

**Créer un utilisateur :**
1. **Utilisateurs** > **+** (bouton personne)
2. Saisir nom, téléphone, sélectionner le rôle
3. Le PIN est généré et affiché à l'écran

**Modifier un rôle :**
1. Sur la fiche d'un utilisateur > **Modifier le rôle**
2. Sélectionner le nouveau rôle > **Enregistrer**

**Régénérer un PIN oublié :**
1. Sur la fiche d'un utilisateur > **Régénérer PIN**
2. Le nouveau PIN s'affiche (l'ancien est invalidé)

**Désactiver un utilisateur :**
1. Sur la fiche d'un utilisateur > **Désactiver**
2. L'utilisateur ne peut plus se connecter

---

### Flux 10 — Consultation du tableau de bord et rapports

> **Acteur** : Gestionnaire ou Super Administrateur  
> **But** : Suivre la performance globale de l'évangélisation

1. **Tableau de bord** : vue d'ensemble
   - Nombre total de membres, évangélistes, cellules, groupes
   - Suivis actifs, intégrés, abandonnés
   - Taux d'intégration global
   - Performance par évangéliste (nombre de suivis, taux d'intégration)
2. **Rapports** > sélectionner un évangéliste pour voir le détail :
   - Liste de ses suivis avec état et scores
   - Taux de réussite

---

## Structure technique

```
church_followup/
├── __manifest__.py
├── models/
│   ├── church_church.py          # Église
│   ├── church_member.py          # Membres (avec inviteur et mentor)
│   ├── church_evangelist.py      # Évangélistes
│   ├── church_followup.py        # Suivis (4 semaines)
│   ├── church_followup_week.py   # Rapports hebdomadaires
│   ├── church_prayer_cell.py     # Cellules de prière
│   ├── church_age_group.py       # Groupes d'âge
│   ├── church_district.py        # Quartiers
│   ├── church_mobile_user.py     # Utilisateurs mobiles (5 rôles)
│   ├── church_attendance.py      # Présences
│   └── church_cooking_rotation.py
├── controllers/
│   └── mobile_api.py             # API REST (~30 endpoints)
├── views/                        # Vues Odoo (formulaires, listes, recherche)
├── security/                     # Groupes, règles d'accès
├── reports/                      # Rapports PDF
├── data/                         # Séquences, tranches d'âge, crons
└── flutter_app/                  # Application mobile Flutter
    ├── lib/
    │   ├── main.dart
    │   ├── core/                 # Thème, constantes
    │   ├── services/             # Client API
    │   ├── providers/            # State management
    │   ├── screens/              # Écrans (auth, home, members, followups, admin...)
    │   └── widgets/              # Composants réutilisables
    └── apk_output/               # APKs générées
```

## API REST

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/api/church/auth/login` | POST | Connexion (téléphone + PIN) |
| `/api/church/dashboard` | POST | Tableau de bord |
| `/api/church/members` | POST | Liste des membres |
| `/api/church/member/create` | POST | Créer un membre |
| `/api/church/member/detail` | POST | Détail d'un membre |
| `/api/church/member/update` | POST | Modifier un membre |
| `/api/church/followups` | POST | Liste des suivis |
| `/api/church/followup/create` | POST | Créer un suivi |
| `/api/church/followup/detail` | POST | Détail d'un suivi |
| `/api/church/followup/week/save` | POST | Enregistrer un rapport hebdomadaire |
| `/api/church/followup/action` | POST | Action sur un suivi (intégrer, abandonner, prolonger, transférer) |
| `/api/church/evangelists` | POST | Liste des évangélistes |
| `/api/church/evangelist/create` | POST | Créer un évangéliste |
| `/api/church/cells` | POST | Cellules de prière |
| `/api/church/age_groups` | POST | Groupes d'âge |
| `/api/church/districts` | POST | Quartiers |
| `/api/church/attendance/sunday/save` | POST | Présences culte |
| `/api/church/attendance/cell/save` | POST | Présences cellule |
| `/api/church/mobile_users` | POST | Liste utilisateurs mobiles |
| `/api/church/admin/create_user` | POST | Créer un utilisateur (super admin) |
| `/api/church/admin/update_user` | POST | Modifier un utilisateur (super admin) |
| `/api/church/admin/reset_pin` | POST | Régénérer un PIN (super admin) |

---

## Dépendances

- **Odoo** : `base`, `mail`
- **Flutter** : `provider`, `http`, `shared_preferences`, `flutter_secure_storage`, `fl_chart`, `pdf`, `printing`
