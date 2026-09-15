--!strict

--[[
    Assets
    Images de l'interface : PNG sans fond, un seul visuel par chose (retour utilisateur).
    - coffre : rendu de notre coffre 3D (tools/render-icon.py), utilise pour l'onglet, l'article, la jauge et
      la fenetre « Coffre plein ! » ;
    - mes jouets : rendu de notre nounours 3D ;
    - le reste : icones generees sur Higgsfield puis detourees par Higgsfield (assets/ui/propres/).
    Registres : assets/ui/registry-v2.json et registry-v2b.json (Decals) ; valeurs = identifiants d'Image releves.
    « rbxassetid://0 » = pas encore televersee : la place reste vide (aucun emoji dans l'interface).
]]

local COFFRE = "rbxassetid://100871723457501"
local CHAUSSONS = "rbxassetid://90286131605131"
local BRAS = "rbxassetid://85248047436654"

local Assets: { [string]: string } = {
    tetine = "rbxassetid://75557557265633",
    boutonMesJouets = "rbxassetid://107954162066543",
    boutonBoutique = "rbxassetid://110693672979459",
    boutonReglages = "rbxassetid://107335180519846",
    bebeDort = "rbxassetid://84551430648902",
    lune = "rbxassetid://86040169964113",
    articleCoffre = COFFRE,
    articleChaussons = CHAUSSONS,
    articleBras = BRAS,
    coffrePlein = COFFRE,
    ongletCoffres = COFFRE,
    ongletVitesse = CHAUSSONS,
    ongletPorteurs = BRAS,
    ongletSkins = "rbxassetid://129015566188401",
    etoile = "rbxassetid://138761456781140",
    fleche = "rbxassetid://91854452104694",
    retour = "rbxassetid://97948191621308",
    -- kettlebell « objet lourd » (badge au-dessus des jouets lourds, assets/ui/propres/lourd.png)
    lourd = "rbxassetid://105373636987385",

    -- Boutique complete et retention (14/09/2026) : icones FLUX locales + 3 Higgsfield, detourees (assets/ui/propres),
    -- televersees lentement (registre assets/ui/registry-boutique.json ; valeurs = identifiants d'Image releves par
    -- InsertService). « 0 » = pas encore televersee.
    pouvoirFurie = "rbxassetid://98064621011023",
    pouvoirTetine = "rbxassetid://78137565006209",
    pouvoirHochet = "rbxassetid://126020959448999",
    pouvoirDoudou = "rbxassetid://140544929780606",
    pouvoirVentouse = "rbxassetid://130297359868084",
    pouvoirCape = "rbxassetid://127303170357351",
    pouvoirBerceuse = "rbxassetid://90566164976227",
    ameliorationSac = "rbxassetid://98834378870472",
    ameliorationAimant = "rbxassetid://116596197203586",
    ameliorationOreille = "rbxassetid://112355531813405",
    -- rendu de notre coffre dore 3D (Tripo), un seul visuel par chose
    coffreDore = "rbxassetid://110337351315014",
    cosmetiqueTrainee = "rbxassetid://78638078661690",
    cosmetiqueDanse = "rbxassetid://104238668526796",
    cosmetiqueContour = "rbxassetid://103864019240429",
    cosmetiqueDecor = "rbxassetid://88566501095632",
    menuQuetes = "rbxassetid://127737903351911",
    menuCollection = "rbxassetid://133143063194139",
    menuNuits = "rbxassetid://72080320882355",
    menuCadeaux = "rbxassetid://77983460381902",
    menuRoue = "rbxassetid://122173817160461",
    menuPleineLune = "rbxassetid://110426323675509",
    menuAmis = "rbxassetid://121718603706459",
    menuPass = "rbxassetid://76665579291879",
    menuClassement = "rbxassetid://130084621278024",

    -- Une icone propre a chaque article de la boutique (15/09/2026, retour utilisateur : le tipi servait pour tous
    -- les decors). « 0 » tant que non televersee : la carte montre alors l'icone de sa categorie.
    iconeTraineeArc = "rbxassetid://98320351351998",
    iconeTraineeEtoiles = "rbxassetid://94425480362475",
    iconeTraineeCoeurs = "rbxassetid://90582564687291",
    iconeDanseJoie = "rbxassetid://118062556932382",
    iconeDanseRobot = "rbxassetid://90207616126263",
    iconeDanseToupie = "rbxassetid://122496043008407",
    iconeContourDore = "rbxassetid://125697903732986",
    iconeContourArc = "rbxassetid://104140807676586",
    iconeDecorGuirlande = "rbxassetid://73273469272328",
    iconeDecorTipi = "rbxassetid://70721118750540",
    iconeDecorPouf = "rbxassetid://102037191441932",
    iconeDecorLampe = "rbxassetid://85486966314122",
    iconeDecorTrophee = "rbxassetid://116196248944850",
    iconeDecorDino = "rbxassetid://113081320075103",
    iconeOreillesLapin = "rbxassetid://82734500743913",
    -- Decors de la boite a outils Roblox (Shared/CatalogDecor) : rendus a televerser ; « 0 » = icone de categorie.
    iconeDecorCanard = "rbxassetid://0",
    iconeDecorCoussinCoeur = "rbxassetid://0",
    iconeDecorCoussinFraise = "rbxassetid://0",
    iconeDecorCubes = "rbxassetid://0",
    iconeDecorLapin = "rbxassetid://0",
    iconeDecorAlpaga = "rbxassetid://0",
    iconeDecorBoiteMusique = "rbxassetid://0",
    iconeDecorPoufBleu = "rbxassetid://0",
    iconeDecorPoufRouge = "rbxassetid://0",
    iconeDecorBallons = "rbxassetid://0",
    iconeDecorTapis = "rbxassetid://0",
    iconeDecorEtoiles = "rbxassetid://0",
    iconeDecorTrain = "rbxassetid://0",
    iconeDecorMobileEtoile = "rbxassetid://0",
    iconeDecorMobileEspace = "rbxassetid://0",
    iconeDecorEtagere = "rbxassetid://0",
    iconeDecorTente = "rbxassetid://0",
    iconeDecorFusee = "rbxassetid://0",
    iconeDecorChateau = "rbxassetid://0",

    -- Rendus 3D des jouets (collection, fiche d'un jouet) : cle « jouet<ToyId> », « 0 » tant que non televerse.
    jouetBlock = "rbxassetid://88308672077465",
    jouetDuck = "rbxassetid://103641318955562",
    jouetCar = "rbxassetid://94429297039792",
    jouetDino = "rbxassetid://131031453666827",
    jouetTop = "rbxassetid://76387705414291",
    jouetRobot = "rbxassetid://121869672033965",
    jouetTeddy = "rbxassetid://73603446503413",
    jouetTumblerBear = "rbxassetid://103205829916687",
    jouetEmojiBall = "rbxassetid://110365727404693",
    jouetCactus = "rbxassetid://106983425973081",
    jouetRingStack = "rbxassetid://92512583522579",
    jouetRockingHorse = "rbxassetid://80327468734584",
    jouetRocket = "rbxassetid://114546114457132",
    jouetCastle = "rbxassetid://77027238645165",
    jouetConsole = "rbxassetid://123358009023756",

    -- Armes (Shared/CatalogWeapons) : icones a generer/televerser ; « 0 » = tuile de la carte en attendant.
    iconeArmeTapette = "rbxassetid://75932780013909",
    iconeArmeOreiller = "rbxassetid://94740568307496",
    iconeArmeBatte = "rbxassetid://130055521892480",
    iconeArmeEpee = "rbxassetid://97146001242060",
    iconeArmeChausson = "rbxassetid://109884285099014",
    iconeArmePistolet = "rbxassetid://92578920534959",
    iconeArmeMarteau = "rbxassetid://125577589908156",
    iconeArmeBaguette = "rbxassetid://120483477143609",
    iconeLampeFrontale = "rbxassetid://101639883070218",
    iconeTraineeTetineOr = "rbxassetid://117331306464154",
}

return Assets
