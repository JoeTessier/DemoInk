# DemoInk

Petite app macOS (barre des menus) pour annoter l'écran pendant les démos en direct.
Remplace « Annotate » : raccourcis globaux fiables (Carbon, aucune permission Accessibilité requise) et tracé fluide (Core Animation).

## Raccourcis globaux (partout, même hors mode dessin)

| Raccourci | Action |
|---|---|
| ⌃§ | Activer / quitter le mode dessin (touche physique § en haut à gauche des claviers ISO) |
| ⌃⌥A | Idem, raccourci de secours |
| ⌃⌥C | Tout effacer |
| ⌃⌥1 … ⌃⌥5 | Changer de couleur (celle du laser quand l'outil Laser est actif) |

Quitter avec ⌃§ (ou ⌃⌥A, ou le menu) conserve les annotations, sauf si « Effacer en quittant le mode dessin » est coché.

Menu « Suspendre les raccourcis globaux » : libère tous les raccourcis (et quitte le mode dessin) jusqu'à réactivation,
par exemple pour laisser ⌃⌥1 à une autre app. Un raccourci déjà pris par une autre app est signalé dans le menu
(« ⚠︎ Raccourci(s) indisponible(s) »), de même qu'une touche du mode dessin qui n'a pas pu être enregistrée.

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
| T | Texte : cliquer pour poser une étiquette, taper, Entrée pour valider (voir « Outil Texte » ci-dessous) |
| L | Pointeur laser : point lumineux à la place du curseur, avec une courte traînée (voir « Pointeur laser » ci-dessous). Ne dessine rien |
| 1 … 5 | Rouge, orange, jaune, vert, bleu (même en plein tracé). Avec l'outil Laser : couleur du laser, pas celle du dessin |
| [ / ] (ou - / +), molette | Épaisseur du trait |
| ⌘-glisser | Rectangle temporaire (depuis Flèche, Rectangle, Ovale, Stylo, Compteur ou Laser) |
| ⌥-glisser | Flèche temporaire (depuis Flèche, Rectangle, Ovale, Stylo, Compteur ou Laser) |
| W | Tableau blanc (même touche pour le retirer) |
| K | Tableau noir (même touche pour le retirer) |
| Z ou ⌘Z | Annuler le dernier tracé, la dernière forme, bulle ou étiquette de l'écran sous la souris ; répété, jusqu'à l'écran vide (puis sans effet). Le laser n'entre pas dans l'annulation |
| C ou E | Tout effacer (tableau compris) en **restant** en mode dessin : l'outil courant est conservé |
| Échap | Quitter le mode dessin **et tout effacer** (tracés, projecteur, tableau — quel que soit le réglage), même en plein tracé ou avec ⇧/⌘/⌥/⌃ enfoncé (sauf ⌘⌥Échap, réservé à Forcer à quitter) |

Hors mode dessin, les clics traversent l'overlay et les annotations restent visibles,
sauf si « Effacer en quittant le mode dessin » est coché dans le menu. Le tableau blanc/noir est toujours retiré en sortant.
Outil, couleur, couleur du laser, épaisseur et cette option sont mémorisés.

Les chiffres utilisent les touches physiques de la rangée du haut : pas besoin de Maj sur un clavier AZERTY.

### Outil Texte (T)

| Pendant la saisie | Action |
|---|---|
| Clic (outil Texte) | Commence une étiquette à cet endroit (curseur clignotant) |
| Lettres, chiffres, ⌫, ⌦, ← → ↑ ↓, ⌥← / ⌥→, ⌘← / ⌘→, ⌥⌫, ⌘⌫ | Saisie et édition standard (touches mortes et accents compris) |
| ⌘V | Coller du texte brut |
| ⇧Entrée (ou ⌥Entrée) | Nouvelle ligne |
| Entrée, ou clic ailleurs | Valider l'étiquette (le clic valide seulement, il n'en commence pas une autre) |
| Échap | Annuler l'étiquette en cours (sans quitter le mode dessin). Un 2ᵉ Échap quitte et efface tout, comme d'habitude |
| Molette | Taille de l'étiquette en cours (bulle « Texte N pt ») |
| ⌃⌥1 … ⌃⌥5 | Couleur de l'étiquette en cours |
| ⌃§ / ⌃⌥A, changement d'écrans | Valident l'étiquette non vide, puis agissent normalement |

- Police système grasse, couleur courante, même ombre légère que les autres annotations. Taille liée à l'épaisseur :
  28 pt à l'épaisseur 8 (16 + 1,5 × épaisseur, de 17,5 à 52 pt).
- L'étiquette grandit en largeur et en hauteur ; près du bord droit ou bas, elle se décale pour rester à l'écran.
- L'éditeur n'est pas un champ système : c'est l'étiquette elle-même (fond transparent, texte dans la couleur
  d'encre, lisible en mode sombre) plus un curseur. À la validation, seul le curseur disparaît : aucune copie en double.
- Une étiquette validée est une annotation comme les autres : Z/⌘Z la retire, C/E/Échap/⌃⌥C/effacement en quittant l'effacent.
- **Focus clavier** : pendant la saisie, les touches du mode dessin sont désenregistrées (sinon T, 1, Échap… seraient
  captées) et DemoInk **s'active** le temps de la saisie (un panneau non activant d'une app jamais active ne reçoit pas
  les frappes). L'app qui était au premier plan est réactivée dès la fin de la saisie (Entrée, clic, Échap, ⌃§,
  changement d'écrans, fin de l'app), et les touches du mode dessin sont réenregistrées. Pendant la saisie, l'app
  présentée apparaît donc inactive (barre de titre grisée). Si l'on change d'app (⌘Tab) en pleine saisie, l'étiquette
  est validée et l'app choisie garde le focus.
- Limites : pas de sélection de texte, pas de modification d'une étiquette après validation, pas de ⌘/⌥-glisser
  depuis l'outil Texte.

### Pointeur laser (L)

- En mode dessin avec l'outil Laser, le curseur est remplacé par un **point lumineux** (cœur plein de 11 pt et halo
  doux) qui suit la souris sur l'écran où elle se trouve. Le curseur système est masqué uniquement au-dessus des
  panneaux (curseur transparent, par le même mécanisme que la croix) : il réapparaît sur la barre des menus.
- Une **courte traînée** de la même couleur suit le point et s'efface en ~0,4 s ; quand la souris s'arrête, elle se
  résorbe dans le point. Rien ne reste à l'écran.
- **Couleur propre au laser**, rouge par défaut et mémorisée à part (`laserColorIndex`) : avec l'outil Laser, 1 … 5,
  ⌃⌥1 … ⌃⌥5 et le menu changent la couleur du laser, jamais celle du dessin (et inversement). La pastille de la barre
  des menus montre la couleur du laser tant que l'outil Laser est actif.
- Clic ou glisser : ne dessinent rien et n'ajoutent rien à l'annulation. ⌘-glisser (rectangle) et ⌥-glisser (flèche)
  restent disponibles, comme depuis les autres outils ; l'outil reste Laser.
- L'animation (CADisplayLink à la fréquence de l'écran, minuterie 60 Hz sous macOS 13) ne tourne que pendant que le
  Laser est actif en mode dessin : changer d'outil, Échap, ⌃§, un changement d'écrans ou la fin de l'app l'arrêtent et
  rendent la croix ou la flèche. Aucun coût CPU sinon ; à l'arrêt de la souris, aucune image n'est redessinée.

### Comment les touches du mode dessin arrivent à l'app

DemoInk ne s'active jamais (l'app présentée garde le focus clavier), sauf le temps de saisir une étiquette Texte (voir plus haut). Les touches ci-dessus sont donc enregistrées
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

L'icône crayon apparaît dans la barre des menus. L'overlay s'arrête juste sous la barre des menus : elle reste visible
et cliquable en mode dessin (tableau et projecteur compris). Hors mode dessin, seule l'icône est affichée (largeur minimale).
En mode dessin, l'icône est cerclée et suivie de l'outil actif (`Arrow`, `Rect.`, `Oval`, `Hilite`, `Spot`, `Pen`, `Count`, `Text`, `Laser`)
et d'une pastille de la couleur courante (celle du laser avec l'outil Laser). Le libellé se met à jour
instantanément (touche, raccourci global ou menu) ; les surcharges temporaires ⌘/⌥-glisser ne le modifient pas.
Il n'y a plus de bulle à l'écran pour l'outil ou la couleur : seule l'épaisseur du trait (molette, - / +) affiche
encore une bulle temporaire.

## Tests développeur

| Variable | Effet |
|---|---|
| `DEMOINK_SELFTEST=1` | Un tracé par outil, ovales/cercles, compteur 1…12 (bords compris), annulation, effacement, ⌘/⌥ depuis Compteur, machine à états clavier, outil Texte (0 touche du mode dessin pendant la saisie et retour exact après validation/annulation/⌃§/changement d'écrans/fin de l'app, app précédente de nouveau au premier plan, ⇧Entrée/⌫/←, Échap n'annule que la saisie, Z, C, molette, bord d'écran ; texte inséré par programme), cycle de vie des raccourcis du mode dessin (0 touche enregistrée après chaque sortie : Échap, bascule, on/off/on, changement de disposition clavier, reconstruction des écrans en plein dessin, fin de l'app), géométrie des panneaux (sous la barre des menus, capturables), coût du stylo sur 1 200 événements, Laser (L/⇧L, rouge par défaut, 1–5 et ⌃⌥5 changent la couleur du laser et pas celle du dessin et inversement, glisser sans calque ni annulation, ⌘-glisser, traînée vide 1 s après l'arrêt, passage d'un écran à l'autre, boucle d'animation et curseur rétablis après changement d'outil, Échap, ⌃§, changement d'écrans, fin de l'app) (PASS/FAIL dans le log). Réglages restaurés à la fin (outil, couleur, couleur du laser, épaisseur, effacement en quittant). Après ce test, les raccourcis globaux du processus sont libérés : relancer l'app. |
| `DEMOINK_SELFTEST=arrows` | Galerie de flèches (épaisseurs 2/4/10/24, 8 directions, glissés courts), reste affichée pour `screencapture`. `DEMOINK_BOARD=white` ou `black` ajoute un tableau derrière. |
| `DEMOINK_SELFTEST=shapes` | Galerie ovales/cercles + bulles 1…15 (chaque bord et coin, épaisseurs 1/8/24), reste affichée pour `screencapture` ; les points cliqués sont dans le log. |
| `DEMOINK_SELFTEST=text` | Galerie d'étiquettes (3 couleurs et tailles, multiligne, une au bord bas-droit) + une étiquette en cours de saisie, reste affichée pour `screencapture`. `DEMOINK_BOARD=white` ou `black` ajoute un tableau. Active l'app (saisie en cours) jusqu'à ce qu'on la quitte. |
| `DEMOINK_SELFTEST=laser` | Outil Laser en mode dessin, point déplacé en huit par des mouseMoved synthétiques (120 Hz), pause de 1 s toutes les 4 s (traînée qui se résorbe), pendant `DEMOINK_LASER_SECONDS` (20 par défaut), puis outil/couleur restaurés et sortie du mode dessin. `DEMOINK_BOARD=white` ou `black`, `DEMOINK_LASER_COLOR=1…5`. |
| `DEMOINK_SELFTEST=menubar` | Passe en mode dessin, fait défiler outil + couleur toutes les secondes, puis quitte le mode dessin (icône seule). |

Lancer le binaire directement : `DEMOINK_SELFTEST=arrows dist/DemoInk.app/Contents/MacOS/DemoInk`.

## Limites

- **Partage d'écran** : les annotations sont visibles quand on partage *l'écran entier* (Zoom, Teams, Meet…).
  Un partage limité à *une fenêtre* ne peut pas les montrer : l'overlay est une fenêtre à part, au-dessus de l'app
  présentée. C'est inhérent au mode « fenêtre », pas contournable.
- **Changement d'écrans** : brancher/débrancher un écran ou changer de résolution reconstruit les overlays et efface
  les annotations en cours (le mode dessin et ses touches restent actifs). La mise en veille, le réveil ou un
  changement de Dock ne les effacent pas.
- **En mode dessin**, les touches listées ci-dessus, ⌘Z et la molette sont captées par DemoInk et n'atteignent
  pas l'app présentée (les raccourcis avec ⌃ ou ⌘ autres que ⌘Z lui parviennent normalement). Hors mode dessin,
  rien n'est intercepté.
- **Barre des menus** : la bande de la barre des menus n'est pas annotable (volontaire : elle doit rester cliquable).
- **Surligneur** : deux traits qui se chevauchent s'additionnent (plus foncés à l'intersection) ; un même trait reste
  uniforme même s'il repasse sur lui-même.
- Les annotations ne sont pas conservées quand l'app quitte.
