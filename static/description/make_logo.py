#!/usr/bin/env python3
"""Génère le logo de « Suivi des classes d'Évangile » en SVG, puis le rasterise.

L'icône précédente portait son titre en toutes lettres sur un ruban qui
traversait le dessin. Le recadrer n'aurait servi à rien — le texte chevauchait
le livre. D'où un redessin complet.

Le dessin : une croix posée sur un livre ouvert. Le livre dit « classes », la
croix dit « Évangile ». Deux formes franches, aucune ne dépend de l'autre pour
être reconnue à 32 px.
"""
import pathlib

import cairosvg

WINE_LIGHT = '#C0546C'
WINE_DARK = '#5E1E31'
CREAM = '#FFF3E6'
CREAM_SHADE = '#E2D2C6'


def svg(with_background=True, scale=1.0):
    """Dessin sur une grille de 512.

    ``scale`` réduit le motif sans toucher au cadre, pour les rognages
    circulaires (icônes adaptatives, « maskable »).
    """
    center = 256

    def sx(x):
        return center + (x - center) * scale

    def sy(y):
        return center + (y - center) * scale

    background = ''
    if with_background:
        background = f'''
  <defs>
    <linearGradient id="fond" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{WINE_LIGHT}"/>
      <stop offset="100%" stop-color="{WINE_DARK}"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#fond)"/>'''

    # Croix, dessinée avant le livre : les pages passent par-dessus le pied.
    cross = (f'<path d="M {sx(230):.1f},{sy(96):.1f} h {52 * scale:.1f} '
             f'v {74 * scale:.1f} h {70 * scale:.1f} v {52 * scale:.1f} '
             f'h {-70 * scale:.1f} v {130 * scale:.1f} h {-52 * scale:.1f} '
             f'v {-130 * scale:.1f} h {-70 * scale:.1f} v {-52 * scale:.1f} '
             f'h {70 * scale:.1f} Z" fill="{CREAM}"/>')

    # Livre ouvert : deux pages qui se rejoignent sur une reliure creusée.
    left = (f'<path d="M {sx(72):.1f},{sy(322):.1f} '
            f'C {sx(140):.1f},{sy(300):.1f} {sx(212):.1f},{sy(306):.1f} '
            f'{sx(250):.1f},{sy(340):.1f} '
            f'L {sx(250):.1f},{sy(428):.1f} '
            f'C {sx(212):.1f},{sy(394):.1f} {sx(140):.1f},{sy(388):.1f} '
            f'{sx(72):.1f},{sy(410):.1f} Z" fill="{CREAM}"/>')
    right = (f'<path d="M {sx(440):.1f},{sy(322):.1f} '
             f'C {sx(372):.1f},{sy(300):.1f} {sx(300):.1f},{sy(306):.1f} '
             f'{sx(262):.1f},{sy(340):.1f} '
             f'L {sx(262):.1f},{sy(428):.1f} '
             f'C {sx(300):.1f},{sy(394):.1f} {sx(372):.1f},{sy(388):.1f} '
             f'{sx(440):.1f},{sy(410):.1f} Z" fill="{CREAM_SHADE}"/>')

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{background}
  {cross}
  {left}
  {right}
</svg>'''


def write_png(source, destination, size):
    destination.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=source.encode(), write_to=str(destination),
                     output_width=size, output_height=size)
    print(f'{destination}  {size}×{size}')


HERE = pathlib.Path(__file__).resolve().parent

full = svg(with_background=True)
(HERE / 'logo.svg').write_text(full)

# 256 px : Odoo embarque ce fichier en base64 dans le menu chargé à chaque
# ouverture du client web.
write_png(full, HERE / 'icon.png', 256)
