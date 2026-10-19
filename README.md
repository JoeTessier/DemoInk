# DemoInk

Petite app macOS (barre des menus) pour annoter l'écran pendant les démos en direct.
Remplace « Annotate » : raccourcis globaux fiables (Carbon, aucune permission Accessibilité requise) et tracé fluide (Core Animation).

## Raccourcis globaux (partout, même hors mode dessin)

| Raccourci | Action |
|---|---|
| ⌃§ | Activer / quitter le mode dessin (touche physique § en haut à gauche des claviers ISO) |
| ⌃⌥A | Idem, raccourci de secours |
| ⌃⌥C | Tout effacer |
| ⌃⌥1 … ⌃⌥5 | Changer de couleur |

Quitter avec ⌃§ (ou ⌃⌥A, ou le menu) conserve les annotations, sauf si « Effacer en quittant le mode dessin » est coché.

## En mode dessin

| Touche | Action |
|---|---|
| A | Flèche (par défaut, un seul contour plein, sans artefact à la jonction tige/pointe) — ⇧ : angle par pas de 45° |
| R | Rectangle arrondi — ⇧ : carré |
| O | Ovale (contour) — ⇧ : cercle |
| H | Surligneur — ⇧ : ligne horizontale |
| S | Projecteur (spot) : assombrit l'écran sauf la zone tracée |
| P | Stylo (main levée, lissé) |
| N | Compteur : chaque clic pose une bulle numérotée 1, 2, 3… (cercle plein + queue pointant exactement le point cliqué, en haut à droite, retournée près des bords et sous la barre des menus). Numérotation globale à tous les écrans ; Z/⌘Z retire la dernière bulle et décrémente ; tout effacement (C, E, Échap, ⌃⌥C, effacement en quittant) repart à 1 |
| 1 … 5 | Rouge, orange, jaune, vert, bleu (même en plein tracé) |
| [ / ] (ou - / +), molette | Épaisseur du trait |
| ⌘-glisser | Rectangle temporaire (depuis Flèche, Rectangle, Ovale, Stylo ou Compteur) |
| ⌥-glisser | Flèche temporaire (depuis Flèche, Rectangle, Ovale, Stylo ou Compteur) |
| W | Tableau blanc (même touche pour le retirer) |
| K | Tableau noir (même touche pour le retirer) |
| Z ou ⌘Z | Annuler le dernier tracé de l'écran sous la souris |
| C ou E | Tout effacer (tableau compris) |
| Échap | Quitter le mode dessin **et tout effacer** (tracés, projecteur, tableau — quel que soit le réglage), même en plein tracé |

Hors mode dessin, les clics traversent l'overlay et les annotations restent visibles,
sauf si « Effacer en quittant le mode dessin » est coché dans le menu. Le tableau blanc/noir est toujours retiré en sortant.
Outil, couleur, épaisseur et cette option sont mémorisés.

Les chiffres utilisent les touches physiques de la rangée du haut : pas besoin de Maj sur un clavier AZERTY.

### Comment les touches du mode dessin arrivent à l'app

DemoInk ne s'active jamais (l'app présentée garde le focus clavier). Les touches ci-dessus sont donc enregistrées
comme raccourcis globaux Carbon **sans modificateur** à l'entrée du mode dessin, et désenregistrées immédiatement
à la sortie : hors mode dessin, aucune touche n'est interceptée. Les lettres suivent la disposition du clavier,
les chiffres la position physique.

## Compiler

Seuls les Command Line Tools sont nécessaires (pas Xcode) :

```bash
./build.sh
```

Résultat : `dist/DemoInk.app` (signature ad hoc).

## Installer

1. Copier `dist/DemoInk.app` dans `/Applications`.
2. Premier lancement : clic droit sur l'app → **Ouvrir** (signature ad hoc, Gatekeeper peut demander une confirmation ;
   sinon Réglages Système → Confidentialité et sécurité → « Ouvrir quand même »).
3. Optionnel : Réglages Système → Général → Ouverture → ajouter DemoInk pour l'ouvrir au démarrage.

L'icône crayon apparaît dans la barre des menus. Hors mode dessin, seule l'icône est affichée (largeur minimale).
En mode dessin, l'icône est cerclée et suivie de l'outil actif (`Arrow`, `Rect.`, `Oval`, `Hilite`, `Spot`, `Pen`, `Count`)
et d'une pastille de la couleur courante. Le libellé se met à jour
instantanément (touche, raccourci global ou menu) ; les surcharges temporaires ⌘/⌥-glisser ne le modifient pas.
Il n'y a plus de bulle à l'écran pour l'outil ou la couleur : seule l'épaisseur du trait (molette, - / +) affiche
encore une bulle temporaire.

## Tests développeur

| Variable | Effet |
|---|---|
| `DEMOINK_SELFTEST=1` | Un tracé par outil, ovales/cercles, compteur 1…12 (bords compris), annulation, effacement, ⌘/⌥ depuis Compteur + machine à états clavier (PASS/FAIL dans le log). Réglages restaurés à la fin (outil, couleur, épaisseur, effacement en quittant). |
| `DEMOINK_SELFTEST=arrows` | Galerie de flèches (épaisseurs 2/4/10/24, 8 directions, glissés courts), reste affichée pour `screencapture`. `DEMOINK_BOARD=white` ou `black` ajoute un tableau derrière. |
| `DEMOINK_SELFTEST=shapes` | Galerie ovales/cercles + bulles 1…15 (chaque bord et coin, épaisseurs 1/8/24), reste affichée pour `screencapture` ; les points cliqués sont dans le log. |
| `DEMOINK_SELFTEST=menubar` | Passe en mode dessin, fait défiler outil + couleur toutes les secondes, puis quitte le mode dessin (icône seule). |

Lancer le binaire directement : `DEMOINK_SELFTEST=arrows dist/DemoInk.app/Contents/MacOS/DemoInk`.
