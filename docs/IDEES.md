# Carnet d'idées — CHUT ! Vole le Géant

Carnet vivant tenu pendant les sessions autonomes : idées à moi, notées au fil des tests, priorisées, puis
réalisées. « En cours » = un agent y travaille ; « Fait » = codé et vérifié en jeu.

## En cours (nuit du 15-16/09)
- **Rythme de la boucle, lot 1** : réapparition chambre 8 s, Furie 3 s / recharge 20 s / prix 750,
  rampe de bruit 8→13, décroissance 8/s, contributions secondaires à 50 %. Points communs d'accueil créés
  au démarrage devant les sorties réelles, prioritaires pour le tutoriel. Calcul testé hors Studio : saturation
  solo 9,81 s, trois joueurs simulés 5,78 s ; pic à trois sur deux rafales de 3 s = 72 points.
  **Pas encore vérifié en jeu** : MCP refusé par la politique d'approbation. Vérifier les 12 points, captures,
  trajets des six bases, délai réel de remplacement chambre/cuisine et achat de Furie. Marche réelle et
  multijoueur : **à tester à la main par l'utilisateur**.
- **Jouets maudits** : le couinement à chaque pas et le bonus au dépôt restent à tester à la main. Constat du banc
  de test (16/09, 04h) : `Humanoid:Move` lancé par script ne fait pas avancer le personnage (0,4 stud en 3 s,
  direction côté client restée à 0) ; en revanche la direction de marche remonte bien au serveur (1,00), donc la
  chasse du bébé, qui s'appuie dessus, n'est pas cassée.
- **Alerte d'intrusion : détection réelle** à tester à deux joueurs (le message, lui, est vu en jeu).
- **Son non autorisé 6417837881** : l'erreur revient au lancement du jeu alors qu'aucun son ne l'utilise plus dans
  Studio ; probablement une requête gardée en cache par la session Studio, à revérifier après un redémarrage.

## Idées à faire (priorité haute d'abord)
- **Retour éclair — tâche suivante, plan séparé** : prime de retour facultative. Étudier le contrôle simplifié
  proposé par Claude (distance prise → extérieur de base, marge fixe d'intérieur et durée minimale à vitesse
  maximale autorisée, Furie comprise ×1,25), sans échantillonnage ni jeton de porte. Les volumes `Base` sont
  déplacés dans les intérieurs : utiliser la sortie réelle, pas leur position à y = −900. Revoir l'autorité et
  les cas de propulsion/trampoline/ventouse dans ce plan avant implémentation.
1. **Cuisine** (Nuit 3) : 2e pièce avec un géant différent (le chien de la famille qui dort sous la table ?),
   jouets plus rares (dinette, fruits), plus bruyante (carrelage qui résonne).
2. **Fil d'actualité du serveur** en haut à droite : « Léa a volé une Console dorée ! », « Tom s'est fait
   attraper par maman ». Crée de l'émulation et donne envie de tenter les gros jouets.
3. **Combo de discrétion** : voler plusieurs jouets d'affilée sans faire monter la jauge au-dessus de 50 %
   multiplie l'XP (x2, x3...). Barre de combo sous la jauge CHUT.
4. **Mission du jour spéciale** : « Vole la tétine du bébé » (objet unique sur le berceau, pendant un
   réveil = ultra risqué), récompense cosmétique exclusive.
5. **Équipes de voleurs** (2 à 4 amis) : bonus de revenu partagé, gros jouets plus faciles, chat d'équipe rapide
   par émotes (« Chut ! », « Viens ! », « Attention ! »).
6. **Émotes rapides** en roue (touche E maintenue) : « Chut ! », pouce levé, danse, « Au secours » — sans chat
   texte, parfait pour les jeunes joueurs.
7. **Accessoire de nuit** : lampe frontale cosmétique qui éclaire un peu devant soi (utile pendant la panne).
8. **Récompense de retour** : si le joueur revient après 24 h, coffre cadeau animé ; après 3 jours, gros cadeau.
9. **Jouets vivants rares** : un jouet « Épique vivant » s'enfuit quand on approche (poursuite dans la chambre).
10. **Photo souvenir** : bouton qui prend une capture stylisée avec cadre « CHUT ! » pour partager (retention
    virale).
11. **Défis chronométrés** près du berceau : ramener 3 jouets en 60 s sans réveil = badge + tétines.
12. **Coffre du bébé** : la nuit, le coffre à jouets de la chambre s'ouvre 30 s, il contient un jouet
    légendaire ; tout le serveur court.
13. **Codes cadeaux** (tétines, cosmétique) pour les réseaux sociaux.
14. **Paramètres** (bouton engrenage) : volume musique/sons, qualité, cacher les noms.
15. **Veilleuse à remonter** : la veilleuse musicale s'épuise ; un joueur qui la remonte (clic maintenu, bruit
    léger) calme le bébé 20 s pour tout le serveur. Coopération spontanée entre inconnus.
16. **Jouets maudits** : rare, un jouet « qui couine » à chaque pas quand on le porte ; très cher au dépôt.
    Risque/récompense lisible sans texte.
17. **Chaussettes glissantes** (objet actif) : glissade rapide et silencieuse sur le parquet, mais impossible
    de s'arrêter net ; drôle en vidéo.
18. **Tableau des records de la nuit** dans la chambre (panneau physique au mur) : plus gros vol, plus long sans
    réveil, plus de propulsions. Remis à zéro à chaque serveur.
19. **Réveil en douceur** : quand la jauge dépasse 80 %, le bébé se retourne et marmonne (animation + son)
    avant de se réveiller vraiment ; dernière chance lisible pour s'immobiliser.
20. **Carte des bases** dans le couloir : aperçu des bases des autres joueurs et de leur richesse, pour choisir
    qui voler.
21. **Jouets de la cuisine** : dinette, fruits en plastique, biberon doré ; plus rares que ceux de la chambre pour
    donner une vraie raison d'affronter le chien.
22. **Événements propres à la cuisine** : le frigo qui s'ouvre tout seul (lumière qui balaie le carrelage), la
    gamelle renversée (bruit fort), le chien qui rêve et aboie en dormant.
23. **File d'annonces** : un seul grand message au centre à la fois (niveau, événement, cadeau), les autres
    attendent leur tour. Leçon du test « écran chargé » de la nuit du 16/09.
24. **Coffre de base qui brille** quand un voleur approche : le propriétaire, où qu'il soit, voit une alerte
    discrète et peut revenir défendre sa base.
25. **Mode photo du tableau des records** : poser à côté du tableau quand on bat un record, avec un cadre doré
    le temps de faire une capture d'écran à partager.

## Fait
- **Audit de débordement de l'interface** (16/09, ~04h30) : écran 2288 × 1201, collection ouverte, tous les éléments
  de la nuit visibles. Aucun élément hors de l'écran ; un seul texte signalé qui ne tient pas, le « Verrouiller » de
  l'invite par défaut de Roblox (pas notre interface, affiché en entier sur les captures). Taille téléphone non
  vérifiable par script : à regarder sur mobile.
- **Test d'endurance** (16/09, ~04h20) : plus de 3 min 20 de jeu sans intervention avec tous les systèmes de la nuit
  (veilleuse, événements, jouets maudits et vivants, records, défis, cuisine, alerte d'intrusion, aperçus de
  collection). Seul message anormal dans les journaux : le son non autorisé 6417837881 (2 fois), déjà connu. Aucune
  autre erreur ni avertissement.
- **Vraies images dans la collection**, vu en jeu (captures `collection-apercus3d`, `collection-apercus3d-trouves`) :
  seuls 15 jouets sur 129 avaient une image téléversée, les autres montraient une lettre. Aperçu 3D du modèle à la
  demande (ToyPreviewService, remote ToyPreview, copies légères dans ReplicatedStorage.ApercusJouets, en cache pour
  tous) : 114 aperçus 3D + 15 images = les 129 jouets. En couleur quand le jouet est trouvé (10 marqués trouvés pour
  le test), silhouette sombre sinon, vus de trois quarts face avant. Les 3 cartes restées en lettre sont les
  mutations (or, arc-en-ciel, cosmique), pas des jouets.
- **Mode photo du tableau des records** (idée 25), vu en jeu (capture `record-photo`) : quand le joueur prend le
  record « Plus gros vol » ou « Plus de jouets », message « Nouveau record : Plus gros vol ! Va poser devant le
  tableau », fanfare et cadre du tableau qui pulse (épaisseur 10 -> 22, blanc/doré) pendant 6 s. Ne se déclenche
  qu'au moment où le record passe au joueur, pas à chaque dépôt ensuite.
- **Tutoriel masqué dans la cuisine**, testé en jeu (capture `tutoriel-cache-cuisine`) : la bulle « Chut ! Le bébé
  dort. » parlait du bébé alors que c'est le chien qui dort. TutorialController la cache quand Piece vaut « Cuisine » :
  visible dans la chambre, cachée après téléportation dans ZoneCuisine, de nouveau visible au retour.
- **Jouets de la cuisine** (idée 21), testés en jeu : 12 jouets propres à la cuisine (`src/shared/ToysKitchen.luau`,
  champ `kitchenOnly`), modèles gratuits du Creator Store de créateurs vérifiés, sans scripts ni sons, pivot au centre,
  rangés dans `ServerStorage.ToyModels` : banane, pomme, tomate, grille-pain (peu communs), orange, mixeur, fruit du
  dragon, service à thé fraise (rares), pomme dorée, mini-cuisine kawaii, biberon doré (épiques), cuisine de poupée
  (légendaire, 3 porteurs). Environ deux fois plus rentables que ceux de la chambre à rareté égale. ToySpawnService
  tire les jouets de la cuisine seulement sur les points de `workspace.Cuisine` : en jeu, 11 jouets de cuisine dans la
  cuisine, 0 dans la chambre, 38 jouets de chambre dans la chambre, aucun modèle manquant. Théière de dînette rejetée
  (tasses minuscules illisibles), rangée dans l'archive. Captures `cuisine2-jouets-rang1`, `cuisine2-jouets-rang2`,
  `cuisine2-jouets-en-jeu`.
- **Événements de la cuisine** (idée 22), testés en jeu (KitchenEventService, KitchenEventController, remote
  KitchenEvent), un toutes les 55 à 100 s quand le chien dort et qu'un joueur est dans la cuisine :
  - Frigo qui s'ouvre : faisceau qui balaie le carrelage 8 s. Contrôle hors du faisceau (derrière la table) : chien
    endormi, jauge 0 -> 0. Dans l'axe : « Le frigo t'a éclairé : le chien se réveille ! » au bout de 2,4 s, chien qui
    grogne, jauge à 100. Captures `cuisine2-frigo`, `cuisine2-frigo-eclaire`.
  - Gamelle renversée : elle tremble 3 s puis tombe avec fracas, jauge du chien 0 -> 41,8, bandeau « BADABOUM ! ».
    Capture `cuisine2-gamelle`.
  - Chien qui rêve : aboiements en dormant, bandeau « LE CHIEN RÊVE... », jauge inchangée (fausse alerte). Capture
    `cuisine2-reve`.
  - Bandeaux seulement dans la cuisine ; ceux du bébé y restent masqués.
  - Messages courts sous le bandeau de la cuisine : au réveil par le frigo, « Le frigo t'a éclairé » et « Il chasse ! »
    recouvraient le compte à rebours. `Theme.toast` évite maintenant aussi le bandeau de la cuisine et empile les
    messages de tous les écrans. Mesuré en jeu : bandeau jusqu'à 268 px, messages à 276-359 et 369-452, sans
    chevauchement. Capture `cuisine2-messages-sous-bandeau`.
- **Alerte d'intrusion** (idée 24), message vu en jeu (capture `alerte-intrus`) : « Léa est dans ta base : reviens
  défendre tes coffres ! » avec contour rouge et alarme (BaseAlertService, BaseAlertController). Quand un autre
  joueur entre dans la base d'un joueur absent, une alerte par intrus toutes les 30 s.
- **Son non autorisé** (6417837881) dans les journaux : il venait de deux koalas importés puis archivés
  (`ServerStorage.Archive.VitrineJouets7_*`) ; identifiant de son vidé (ancien gardé en attribut SoundIdAvant).
- **Écran moins chargé après un dépôt**, testé en jeu : un message court envoyé pendant la célébration « NIVEAU N ! »
  n'apparaît pas pendant ses 4,2 s puis s'affiche 0,07 s après sa fin (au lieu de se superposer au centre, capture
  `combo-fil` avant).
- **Intérieurs carton et chaussures**, vérifiés en jeu :
  - Carton : l'arrivée (-135, -45) était à l'intérieur d'un tas de chips de calage (TasChips), le joueur apparaissait
    dans le polystyrène. Tas déplacé au centre ; arrivée sur le fond en carton, rien autour ; sortie testée : retour
    dans la chambre à y = 3, sans chute. Captures `interieur-carton-avant` / `interieur-carton-apres`.
  - Chaussures : parois du fond et couvercle noirs. 10 lampes chaudes à mi-hauteur le long des parois, 9 lueurs sous
    le couvercle, ambiance remontée (150,122,98, exposition 0,45). Boîte, chaussure géante et papier de soie lisibles
    même pendant la panne de veilleuse. Captures `interieur-chaussures-avant` / `interieur-chaussures-apres2`.
- **Combo de discrétion** (idée 3), testé en jeu : deux jouets Rares déposés, combo x1 -> x2 -> x3, record x3,
  +3 600 tétines ; badge de combo visible.
- **Fil d'actualité** (idée 2), testé en jeu : message « jahidsayad432 a volé Voiture de course ! » reçu, nom du
  jouet coloré selon la rareté ; le 2e dépôt dans les 8 s est bien filtré par l'anti-spam.
- **Émotes** (idée 6), testées en jeu : « Bravo » joue le geste et affiche la bulle au-dessus du personnage.
- **Paramètres** (idée 14), testés en jeu : cacher les noms et régler la musique à 30 % sont enregistrés. Le
  masquage ne visait que les autres joueurs : il cache maintenant aussi sa propre étiquette (vérifié en jeu :
  étiquette NiveauJoueur désactivée).
- **Célébration de niveau sous le bandeau d'événement**, vue en jeu (capture `celebration-bandeau`) : « BOÎTE À
  MUSIQUE » et son compte à rebours en haut, « NIVEAU 3 ! », « +1 250 » et la prochaine récompense plus bas, sans
  chevauchement.
- **Événements du bébé masqués dans la cuisine**, testé en jeu : joueur téléporté dans ZoneCuisine (pièce
  « Cuisine »), événement « chat » lancé, aucun bandeau affiché ; le bandeau en cours disparaît en entrant.
- **Réveil en douceur** (idée 19), vu en jeu (capture `bebe-remue`) : jauge à 84,7 %, attribut Remue vrai au bout de
  2,3 s, le bébé endormi se retourne à moitié d'un côté puis de l'autre et la bulle « Mmh... » s'affiche au-dessus
  du berceau (BabyVisualService, EventController). Au-delà de 100 %, il se réveille normalement.
- **Revue en images des 118 jouets** (captures `revue-jouets-lot*`, gros plans `gros-plan-*`, pose comme en jeu
  `jeu-*` et après correction `apres-*`). Sauvegarde des modèles d'origine : `ServerStorage.Archive.ToyModels_avant_revue`.
  - Cause principale : 32 modèles avaient un pivot tourné (PrimaryPart incliné), donc posés couchés ou de travers
    en jeu (Cupcake à l'envers, dinosaures, voilier, gâteau...). Pivot remis droit, PrimaryPart retiré.
  - Remis debout / de face : Nounours géant (était de profil), Husky, Tricératops (étaient de dos), Bateau de
    course (était vertical), Grande girafe et Girafe en peluche (étaient couchées), Singe.
  - Remplacés (Creator Store, scripts retirés) : Chausson de bébé (l'ancien était un personnage invisible), Singe en
    peluche. Soucoupe volante : corps de personnage retiré, il ne reste que la soucoupe. Pièce de puzzle : rose au
    lieu de gris.
  - Suite (nuit du 16/09, captures `jouets7-candidats-*` et `jouets7-final*`) : Singe en peluche remplacé (Creator
    Store 18982171470, singe assis mignon) ; Koala remplacé (6415033728 réduit à la tête de koala, corps de
    personnage archivé) ; Dominos remplacés (11547303046, dominos noirs debout en rangées) ; Baguette de fée
    remplacée (1101601612, étoile jaune sur bâton noir, posée debout, étoile en haut) ; Soucoupe volante teintée
    vert menthe ; Harmonica agrandi (9 studs) et légèrement incliné. Anciens modèles dans `ServerStorage.Archive`
    (suffixe `_avant_jouets7`).
  - Clavier rose corrigé (16/09, 04h) : ses 4 unions avaient `UsePartColor` à faux, donc la teinte était ignorée et le
    corps restait lilas délavé. `UsePartColor` activé, corps rose franc (255,140,195), bordures framboise, molette
    jaune ; touches et boutons intacts, taille inchangée (13 studs). Aucun modèle du Creator Store n'était meilleur
    (les 3 claviers roses trouvés sont le même modèle, le 4e un bloc jaune). Original dans
    `ServerStorage.Archive.PinkKeyboard_avant_clavier`. Captures `clavier-candidats`, `clavier-avant`, `clavier-apres`.
- **Veilleuse à remonter** (idée 15), testée en jeu : veilleuses des commodes qui s'épuisent en 4 min (lueurs qui
  baissent, bruit x1,3 à vide) ; remontoir au pied de chaque commode (maintenir 2,5 s) : énergie de 10 à 99,
  -15 de bruit, bruit divisé par deux 20 s pour tout le serveur, +40 XP, message « Tu as remonté la veilleuse : le
  bébé se calme ! ». Jauge lune au-dessus du remontoir (taille réduite après la capture).
- **Tableau des records de la nuit** (idée 18), vu en jeu : panneau à droite de la fenêtre du mur du fond (à gauche,
  la bibliothèque le cachait) ; plus gros vol, nuit la plus calme (mise à jour en direct), plus de jouets, plus
  attrapé, sans débordement.
- **Jouets maudits** (idée 16) : jouet maudit en jeu, lueur violette au sol et volutes (5 % des jouets Peu communs
  à Épiques, couinement et +1,5 de bruit par pas du porteur, bonus de 60 s de revenu au dépôt).
- **Cuisine** (idée 1), testée en jeu : refusée avant la Nuit 3 (« La cuisine s'ouvre à la Nuit 3 »), entrée par un
  trou de souris à la Nuit 3, jauge du chien à la place de celle du bébé, 5 s de course = 57/100.
  Finitions (vues en captures `k2-*`) : chien tourné vers la pièce (le modèle avait la tête vers le mur), couché sur
  un vrai panier rond en boudin rouge, tête visible depuis le sol ; veilleuse chaude qui atteint enfin le chien
  (l'ancienne était hors de portée), lueurs de nuit à hauteur de joueur, reflet du frigo et rai de lune éclairés ;
  gamelles, os à mâchouiller et bocal à biscuits (Creator Store). Ronflement chargé (11 s, joue quand il dort).
  Attrape du chien testé : raison « dog », grand « OUAF ! » à l'écran sous « ATTRAPÉ ! » (sans chevauchement), sans le cri du bébé, propulsion de 89 studs.
- **Messages courts** vus en jeu : sous le bandeau d'événement quand il est affiché, empilés, taille de texte
  identique.
- **Mission du jour « Vole la tétine du bébé »** (idée 4), testée en jeu : tétine géante dorée avec panneau
  « MISSION » posée sur le matelas du berceau ; refus quand le bébé dort (« ne se vole que quand le bébé est
  réveillé ») ; prise pendant la chasse ; déposée en base : +20 000 tétines, +400 XP, traînée exclusive « tétine
  d'or » équipée, stat de quête ; revenue sur le berceau 20 s plus tard et refusée (« déjà volée aujourd'hui »).
  Traînée exclusive non achetable en boutique (bouton « Mission »). Nouvelle quête « Vole la tétine du bébé ».
- **Lampe frontale** (idée 7) : cosmétique à 18 000 tétines (onglet Cosmétiques), faisceau chaud incliné devant la
  tête, vu en jeu dans une chambre plongée dans le noir.
- **Blocage au démarrage corrigé** (02h05) : StealService attendait BaseChests et bloquait tous les services suivants,
  donc aucun profil ne se chargeait. Main lance maintenant chaque phase dans son propre fil.
- **Codes cadeaux** testés en jeu : CHUT/BEBEDORT créditent, « Déjà utilisé » au 2e essai, anti-spam au 3e raté.
- **Coffre du bébé** vu en jeu (bandeau « LE COFFRE S'OUVRE ! » + compte à rebours) ; **jouet vivant** réveillé.
- **Récompense de retour** vue en jeu (fenêtre « Bon retour, voleur ! », gros cadeau 3 jours : 15 000 tétines,
  500 XP, traînée d'étoiles). **Défi chronométré** lancé depuis la plaque ; plaque moins éblouissante, chrono
  remis dans l'écran.
- **8 nouveaux événements**, vus en jeu en captures : orage (attrapé à l'éclair hors de l'ombre), panne de
  veilleuse (chambre sombre, lampe torche), chat de la maison, jouet doré géant (faisceau doré), pluie de
  jouets, boîte à musique, cauchemar, papa ronfle.
- **Lot A de 50 jouets**, soit 118 jouets en tout (16 au départ) ; imports bruts rangés dans l'archive.
- **Fil d'actualité** et **roue d'émotes** (touche Z) : codés, bouton « Émotes » visible en jeu, reste à les
  tester.
- **Vol entre joueurs + verrou de base**, testé en jeu : le jouet volé sort du coffre, le voleur est surligné,
  un jouet lâché revient à la victime, une base verrouillée refuse le vol.
- **Tutoriel** en 7 étapes, vu en jeu : faisceau de guidage et mise en avant du compteur. Bulle agrandie.
- **Trampoline**, testé en jeu : le personnage suit une cloche jusqu'au matelas (le Humanoid freinait la vitesse
  en l'air).
- **Lot B de 52 jouets** importé et sauvegardé.
- Voir docs/PLAN.md pour l'historique détaillé.
