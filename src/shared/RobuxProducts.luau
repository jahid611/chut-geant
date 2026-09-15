--!strict

-- Remplacer uniquement les productId après création des produits développeur (docs/PLAN.md).
export type Pack = {
    id: string,
    productId: number,
    cash: number,
    robux: number,
    icon: string,
    label: string,
}

local packs: { Pack } = {
    { id = "Tetines1", productId = 0, cash = 2500, robux = 25, icon = "tetine", label = "Poignée de tétines" },
    { id = "Tetines2", productId = 0, cash = 10000, robux = 79, icon = "tetine", label = "Sac de tétines" },
    { id = "Tetines3", productId = 0, cash = 30000, robux = 199, icon = "tetine", label = "Coffre de tétines" },
    { id = "Tetines4", productId = 0, cash = 100000, robux = 499, icon = "tetine", label = "Montagne de tétines" },
}

local byProductId: { [number]: Pack } = {}
for _, pack in packs do
    assert(pack.productId >= 0 and pack.productId % 1 == 0, "Identifiant de produit invalide")
    if pack.productId > 0 then
        assert(byProductId[pack.productId] == nil, "Identifiant de produit Robux en double")
        byProductId[pack.productId] = pack
    end
    table.freeze(pack)
end

local RobuxProducts = { Packs = table.freeze(packs) }

function RobuxProducts.ByProductId(productId: number): Pack?
    return byProductId[productId]
end

return table.freeze(RobuxProducts)
