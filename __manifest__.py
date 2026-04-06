{
    'name': 'Suivi Évangélisation Église',
    'version': '19.0.1.0.0',
    'category': 'Church Management',
    'summary': 'Suivi des classes d\'évangile et gestion des cellules de prière',
    'description': """
        Module de suivi d'évangélisation pour les églises.
        
        Fonctionnalités :
        - Gestion multi-église
        - Inscription et suivi des évangélistes
        - Suivi des nouvelles personnes (4 semaines)
        - Gestion des cellules de prière par quartier
        - Gestion des groupes d'âge configurables
        - Suivi des présences (cultes et cellules)
        - Rotation cuisine des cellules
        - Tableaux de bord et rapports
        - API mobile pour application Flutter
    """,
    'author': 'ICP',
    'license': 'AGPL-3',
    'depends': ['base', 'mail'],
    'data': [
        # Security
        'security/church_followup_security.xml',
        'security/ir.model.access.csv',
        # Data
        'data/ir_sequence.xml',
        'data/age_range_data.xml',
        'data/cron_data.xml',
        # Reports
        'reports/report_followup.xml',
        'reports/report_cell_members.xml',
        'reports/report_age_group_members.xml',
        'reports/report_dashboard.xml',
        # Views
        'views/church_pastor_views.xml',
        'views/church_church_views.xml',
        'views/church_district_views.xml',
        'views/church_member_views.xml',
        'views/church_mobile_user_views.xml',
        'views/church_evangelist_views.xml',
        'views/church_followup_views.xml',
        'views/church_prayer_cell_views.xml',
        'views/church_age_group_views.xml',
        'views/church_attendance_views.xml',
        'views/church_cooking_rotation_views.xml',
        'views/menus.xml',
    ],
    'assets': {},
    'demo': [
        'demo/demo_data.xml',
    ],
    'installable': True,
    'application': True,
}
