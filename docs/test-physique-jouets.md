# Rejouer les corrections C4-R1 et C4-R2

Test serveur : `tools/tests/toy-physics-runtime.luau`, à envoyer comme `code` à
`eval_server_runtime`. Le script n'est pas chargé par Rojo. Il utilise les vrais
services de prise, de lancer et de capture, avec un jouet temporaire du catalogue.

1. Arrêter les générations 3D, lancer un playtest par l'arbitre, attendre le profil.
   Garder les mains et le sac vides, sans cape ni bouclier actif.
2. Envoyer le script avec `scenario = "lancer"` : Top, joueur en `(60, 7, 120)`, face à −Z.
3. Attendre 8 secondes côté appelant, lire les journaux serveur, puis arrêter la session.
4. Recommencer en session neuve avec `scenario = "capture"` : Cactus,
   joueur en `(-60, 5, 60)`, `GiantService:Catch(player, "moved")`.

Chaque essai imprime 71 relevés, espacés de 0,1 s avec l'heure réelle : centre,
vitesse, déplacement depuis le relevé précédent, distance au lâcher, bas de la boîte,
sol mesuré, ancrage et `PhysiqueActive`. Une machine lente peut retarder les relevés :
interpréter les heures réelles. Comparer notamment 0,3 / 0,8 / 1,5 / 2,5 s.

Le script vérifie l'absence de soudure au porteur, la possession réseau serveur au départ,
l'absence de suspension de 0,5 s, de projection à 80 studs et d'ancrage sous le sol,
la fin du vol, le nettoyage des exclusions de collision et la reprise du jouet à portée.
Le message `OK` n'est imprimé qu'après toutes ces assertions. Le personnage est déplacé
pour préparer le scénario et pour tester la reprise ; ne pas le déplacer à la main pendant les mesures.
Le jouet temporaire expire par le service existant après 45 s. Arrêter le playtest après lecture des journaux.

## Compléments de validation en jeu

- Refaire avec mains et sac occupés, un jouet lourd, maman, chien et coups.
  Tous les lâchers forcés passent par `CarryService:Drop` : horizontal `32 / poids`, vertical `18`.
- Depuis le bord de la chambre puis de la cuisine, lancer vers l'extérieur : secours
  au dernier sol sûr de la pièce de départ. Refaire après transport d'un jouet depuis l'autre pièce.
- Pour éprouver le secours sous le sol, dans une session dédiée, imposer une forte vitesse
  verticale descendante à un jouet en vol ; pour la limite de distance, une forte vitesse horizontale.
  Vérifier le retour dans la pièce et un bas au-dessus du sol, puis la reprise à portée.
- Tester au-dessus du tapis MeshPart, près d'un mur, une pose avec G, les apparitions,
  les impacts sur un autre joueur et une prise pendant un lâcher pour vérifier le nettoyage anticipé.

## État de ce passage

Script préparé, **non exécuté dans Studio** : l'appel MCP `solo_playtest status` a été
refusé par la politique d'approbation de l'environnement. Aucune mesure en jeu ni
validation visuelle n'est revendiquée ici.
