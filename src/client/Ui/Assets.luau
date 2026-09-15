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

local COFFRE = "rbxassetid://95879419648698"
local CHAUSSONS = "rbxassetid://87140632236955"
local BRAS = "rbxassetid://90967024116965"

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
    pouvoirFurie = "rbxassetid://92871761535786",
    pouvoirTetine = "rbxassetid://78137565006209",
    pouvoirHochet = "rbxassetid://126020959448999",
    pouvoirDoudou = "rbxassetid://140544929780606",
    pouvoirVentouse = "rbxassetid://126850161419156",
    pouvoirCape = "rbxassetid://127303170357351",
    pouvoirBerceuse = "rbxassetid://90566164976227",
    ameliorationSac = "rbxassetid://107683777053459",
    ameliorationAimant = "rbxassetid://134414419532870",
    ameliorationOreille = "rbxassetid://115243667055987",
    -- rendu de notre coffre dore 3D (Tripo), un seul visuel par chose
    coffreDore = "rbxassetid://84339907965296",
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
    iconeTraineeArc = "rbxassetid://123940325069868",
    iconeTraineeEtoiles = "rbxassetid://121676432579481",
    iconeTraineeCoeurs = "rbxassetid://93417719882168",
    iconeDanseJoie = "rbxassetid://79681702863021",
    iconeDanseRobot = "rbxassetid://70962427264002",
    iconeDanseToupie = "rbxassetid://82476150966759",
    iconeContourDore = "rbxassetid://121516826341967",
    iconeContourArc = "rbxassetid://113186214970336",
    iconeDecorGuirlande = "rbxassetid://136274084632623",
    iconeDecorTipi = "rbxassetid://135722238943421",
    iconeDecorPouf = "rbxassetid://135263649869208",
    iconeDecorLampe = "rbxassetid://93928971371009",
    iconeDecorTrophee = "rbxassetid://114132502678694",
    iconeDecorDino = "rbxassetid://72046075111710",
    iconeOreillesLapin = "rbxassetid://86785158843521",
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
    iconeArmeTapette = "rbxassetid://111576275835621",
    iconeArmeOreiller = "rbxassetid://75242060205545",
    iconeArmeBatte = "rbxassetid://84595873222274",
    iconeArmeEpee = "rbxassetid://74442360162081",
    iconeArmeChausson = "rbxassetid://81049975920705",
    iconeArmePistolet = "rbxassetid://125515778134583",
    iconeArmeMarteau = "rbxassetid://88534571810461",
    iconeArmeBaguette = "rbxassetid://116063935188388",
}

return Assets
