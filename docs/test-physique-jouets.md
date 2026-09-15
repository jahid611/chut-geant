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

### Tétine sur le matelas (15/09)

Le même banc accepte `scenario = "mission"` après apparition de la mission. Cette branche ne modifie
aucune instance : elle vérifie les neuf appuis sous la pose retenue près de Target, la taille ×1,7, l'unicité,
l'ancrage et la stabilité après 7 s. Elle vérifie aussi que `ToyPlacement.Ground` refuse toujours ce
point aux appels ordinaires. Lire `[TEST-PHYSIQUE] OK mission` après 8 s et capturer le contact avec
le matelas, puis une vue incluant le joueur pour l'échelle.

Après G2-R1, le centre peut se décaler de ±9 studs sur X/Z. Le banc imprime les neuf sondes
(instance, normale, écart de hauteur au repère et jeu sous la base), même si l'une est refusée.
La base doit toucher le plus haut appui ; le jeu sous les autres sondes ne dépasse pas 0,25 stud.
Les sondes ne remplacent pas la capture : vérifier aussi visuellement les reliefs entre les points.

Pour le retour, envoyer `scenario = "mission_retour"` avant un dépôt réel ou une disparition par le jeu
(dans les 120 s). Ce scénario observe `Destroying` sans détruire le jouet lui-même ; il exige un seul
remplacement entre 20 et 23 s, avec 0,05 s de tolérance pour la livraison différée de `Destroying`.
Il ne prouve pas le retour après une simple capture laissant la tétine libre. Rejouer `mission` après
chaque remplacement pour vérifier contact et stabilité. Répéter au moins cinq cycles et lire les journaux
de démarrage : aucun avertissement de pose ne doit apparaître dans le scénario normal.
Si aucune mission n'apparaît, relever le diagnostic des neuf sondes du meilleur candidat après les
392 poses refusées au maximum ; distinguer instance étrangère, normale, écartY, dispersion et obstacle.
La reprise après 20 s doit rester unique. Ne pas élargir les seuils sans les mesures du vrai matelas.

Compléter avec la prise pendant `Hunting` (main, ventouse, sac), les refus pendant le sommeil,
hors portée et après réussite quotidienne, puis le dépôt coffre/tipi et le retour unique 20 s
après destruction. Une capture qui laisse la tétine au sol ne programme pas de retour : cycle conservé.
Tester aussi la disparition du modèle ou du berceau au démarrage et les refus de support non horizontal.
Ces branches et ces scénarios n'ont pas été exécutés lors de la correction, y compris G2-R1 : les appels MCP
`execute_luau` et `solo_playtest status` ont été refusés par la politique d'approbation.

Script préparé, **non exécuté dans Studio** : l'appel MCP `solo_playtest status` a été
refusé par la politique d'approbation de l'environnement. Aucune mesure en jeu ni
validation visuelle n'est revendiquée ici.
