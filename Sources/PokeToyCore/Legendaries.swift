/// Legendary and mythical Pokémon by national dex number (Gen 1–9), so rarity works offline.
public enum Legendaries {
    public static let dexNumbers: Set<Int> = [
        144, 145, 146, 150, 151,
        243, 244, 245, 249, 250, 251,
        377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
        480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493,
        494, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649,
        716, 717, 718, 719, 720, 721,
        772, 773, 785, 786, 787, 788, 789, 790, 791, 792, 800, 801, 802, 807, 808, 809,
        888, 889, 890, 891, 892, 893, 894, 895, 896, 897, 898,
        905, 1001, 1002, 1003, 1004, 1007, 1008, 1014, 1015, 1016, 1017, 1024, 1025,
    ]

    public static func isLegendary(dex: Int) -> Bool {
        dexNumbers.contains(dex)
    }

    /// Whether the Pokémon at SpriteCollab `path` is legendary or mythical.
    public static func isLegendary(path: String) -> Bool {
        Evolution.dexNumber(of: path).map(isLegendary(dex:)) ?? false
    }
}
