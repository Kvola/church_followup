#!/usr/bin/env python3
"""Génère l'icône de « Suivi Évangélisation » en SVG, puis toutes ses tailles.

Une seule source pour le module Odoo, le catalogue /apps et l'application
mobile : l'icône d'avant portait son titre (« Suivi Classes d'Évangile », un
nom qui n'est plus le sien) en toutes lettres, illisible sous 96 px.

Le dessin : une personne arrive au pied d'une croix, précédée de trois pas
qui grandissent — les semaines du suivi. Il dit ce que fait l'application,
accompagner quelqu'un jusqu'au bout, et reste lisible à 48 px.

Les couleurs sont celles de l'application (AppColors.primary).

    python3 static/description/make_logo.py
"""
import pathlib

import cairosvg

TOP = '#7C6DD8'
BOTTOM = '#3A2E9E'
CREAM = '#FFF6E8'
GOLD = '#FFC24B'
BACKGROUND = '#5B4FCF'  # fond de l'icône adaptative Android (pubspec.yaml)


def svg(with_background=True, scale=1.0, rounded=True):
    """Dessin sur une grille de 512.

    ``scale`` réduit le motif sans toucher au cadre : Android rogne l'icône
    adaptative en cercle, le motif doit tenir dans les 66 % du centre.
    """
    c = 256

    def x(v):
        return c + (v - c) * scale

    def y(v):
        return c + (v - c) * scale

    background = ''
    if with_background:
        background = f'''
  <defs>
    <linearGradient id="fond" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{TOP}"/>
      <stop offset="100%" stop-color="{BOTTOM}"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="{112 if rounded else 0}" fill="url(#fond)"/>'''

    # La croix : une seule forme, coins adoucis par un trait de même couleur.
    cx, top, w, arm, beam, bottom = 318, 78, 48, 164, 150, 318
    cross = (
        f'<path d="M {x(cx - w / 2):.1f},{y(top):.1f} H {x(cx + w / 2):.1f} '
        f'V {y(beam):.1f} H {x(cx + arm / 2):.1f} V {y(beam + w):.1f} '
        f'H {x(cx + w / 2):.1f} V {y(bottom):.1f} H {x(cx - w / 2):.1f} '
        f'V {y(beam + w):.1f} H {x(cx - arm / 2):.1f} V {y(beam):.1f} '
        f'H {x(cx - w / 2):.1f} Z" fill="{GOLD}" stroke="{GOLD}" '
        f'stroke-width="{10 * scale:.1f}" stroke-linejoin="round"/>')

    # Les pas : de plus en plus nets à mesure qu'on avance.
    steps = ''.join(
        f'<circle cx="{x(px):.1f}" cy="{y(py):.1f}" r="{r * scale:.1f}" '
        f'fill="{CREAM}" fill-opacity="{opacity}"/>'
        for px, py, r, opacity in ((96, 424, 15, 0.55), (150, 394, 19, 0.75),
                                   (206, 368, 23, 0.95)))

    # La personne, arrivée.
    px = 262
    person = (
        f'<circle cx="{x(px):.1f}" cy="{y(300):.1f}" r="{30 * scale:.1f}" fill="{CREAM}"/>'
        f'<path d="M {x(px - 52):.1f},{y(424):.1f} '
        f'C {x(px - 52):.1f},{y(362):.1f} {x(px - 30):.1f},{y(340):.1f} {x(px):.1f},{y(340):.1f} '
        f'C {x(px + 30):.1f},{y(340):.1f} {x(px + 52):.1f},{y(362):.1f} {x(px + 52):.1f},{y(424):.1f} Z" '
        f'fill="{CREAM}"/>')

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{background}
  {cross}
  {steps}
  {person}
</svg>'''


def write_png(source, destination, size):
    destination.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=source.encode(), write_to=str(destination),
                     output_width=size, output_height=size)
    print(f'{destination}  {size}×{size}')


HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parent.parent / 'flutter_app' / 'assets'

full = svg()
(HERE / 'logo.svg').write_text(full)

# 256 px : Odoo embarque ce fichier en base64 dans le menu chargé à chaque
# ouverture du client web ; c'est aussi l'icône du catalogue /apps.
write_png(full, HERE / 'icon.png', 256)

# Application : iOS refuse la transparence et arrondit lui-même — carré plein.
write_png(svg(rounded=False), APP / 'icon.png', 1024)
# Avant-plan de l'icône adaptative Android, posé sur BACKGROUND et rogné (le motif occupe déjà 75 % du cadre : 0,6 le garde (les pas, dans le coin, sont les premiers rognés) dans le cercle visible).
write_png(svg(with_background=False, scale=0.6), APP / 'icon_foreground.png', 1024)
# Le logo affiché dans l'application (écran de connexion) : coins arrondis.
write_png(full, APP / 'logo.png', 512)
