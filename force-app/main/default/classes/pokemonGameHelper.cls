/* Title: pokemonGameHelper
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Shared mechanics for pokemonGameController — record builders, FOR UPDATE locks, requeries, settings accessors, ball/cart helpers, weighted encounters, and clamps. Keeps the controller a thin @AuraEnabled surface.
 * Test Class: pokemonGameController_Test
 * Modified: Garrett Kent - 06/20/2026 - S5.8 trainer-scaled encounters + secure catch-level + shiny-on-catch
 * Modified: Garrett Kent - 06/21/2026 - Critical capture, evolution stones (item prices/fields/keys), ToLong coercion, stone fields on trainer queries
 * Modified: Garrett Kent - 06/22/2026 - Lowered wild-encounter level offset fallbacks so wilds sit below the trainer's strongest
 * Modified: Garrett Kent - 06/22/2026 - Added Shiny/Dusk/Dawn evolution stones
 * Modified: Garrett Kent - 06/25/2026 - Fixed mart checkout: JSON round-trip the LWC cart (Map<Object,Object>) before casting to Map<String,Object>
 * Modified: Garrett Kent - 07/05/2026 - Encrypted encounter tokens (anti-inspect grass), minimum wild levels for evolved/legendary species, shiny rolled at patch time, catch-rate multiplier
 * Modified: Garrett Kent - 07/05/2026 - Single-use tokens: consumed (caught/fled) encounter hashes ledgered on the trainer so a captured shiny token cannot be replayed
 * Modified: Garrett Kent - 07/21/2026 - Can_Evolve__c stamped true for stone and friendship evolvers, not just level-up
 */
public with sharing class pokemonGameHelper {

    // ---- Param coercion ----

    // @AuraEnabled deserializes JSON numbers as runtime Decimal — a fractional value like "6.0" throws on a direct Integer cast, so floor it down to a valid Integer.
    public static Integer ToInteger(Object value){
        return value == null ? null : Decimal.valueOf(String.valueOf(value)).round(System.RoundingMode.DOWN).intValue();
    }

    // Decimal.round(System.RoundingMode.DOWN) already returns a Long — return it directly.
    public static Long ToLong(Object value){
        return value == null ? null : Decimal.valueOf(String.valueOf(value)).round(System.RoundingMode.DOWN);
    }

    // ---- Species ----

    public static Map<String,Object> Species(Integer pokedexNumber){
        Map<String,Object> speciesResult = PokemonSpeciesService.GetSpecies(pokedexNumber);
        if(speciesResult.get('status') != 'success') return null;
        return (Map<String,Object>)speciesResult.get('species');
    }

    public static String ArtworkUrl(Map<String,Object> species, Integer pokedexNumber, Boolean isShiny){
        return isShiny
            ? 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/shiny/' + pokedexNumber + '.png'
            : String.valueOf(species.get('image'));
    }

    public static Pokemon__c BuildPokemon(Map<String,Object> species, Integer pokedexNumber, Integer level, Boolean isShiny, Id trainerId){
        String artworkUrl = ArtworkUrl(species, pokedexNumber, isShiny);

        return new Pokemon__c(
            Name = String.valueOf(species.get('name')),
            Pokemon_Trainer__c = trainerId,
            Pokedex_Number__c = pokedexNumber,
            Species_Name__c = String.valueOf(species.get('name')),
            Image__c = artworkUrl,
            Type__c = String.valueOf(species.get('type1')),
            Type_2__c = species.containsKey('type2') ? String.valueOf(species.get('type2')) : null,
            HP__c = (Integer)species.get('hp'),
            Attack__c = (Integer)species.get('attack'),
            Defense__c = (Integer)species.get('defense'),
            Special_Attack__c = (Integer)species.get('spAtk'),
            Special_Defense__c = (Integer)species.get('spDef'),
            Speed__c = (Integer)species.get('speed'),
            Capture_Rate__c = (Integer)species.get('captureRate'),
            Level__c = level,
            EXP_Points__c = pokemonCatchLogic.ExpForLevel(String.valueOf(species.get('growthRate')), level),
            Is_Shiny__c = isShiny,
            Is_Traded__c = false,
            Can_Evolve__c = species.containsKey('evolveLevel') || species.containsKey('stoneEvolutions') || species.containsKey('evolvesByFriendship')
        );
    }

    // ---- Trainer queries ----

    public static Pokemon_Trainer__c LockTrainerForCurrentUser(){
        Id ownerId = UserInfo.getUserId();
        List<Pokemon_Trainer__c> ownedTrainers = [
            SELECT Id, Name, Currency__c, Experience_Tokens__c, Poke_Balls__c, Great_Balls__c,
                   Ultra_Balls__c, Master_Balls__c, Fire_Stones__c, Water_Stones__c, Thunder_Stones__c,
                   Leaf_Stones__c, Moon_Stones__c, Shiny_Stones__c, Dusk_Stones__c, Dawn_Stones__c,
                   Rival__c, Automation_Opt_In__c, Consumed_Encounters__c,
                   Total_Pokemon__c, Shiny_Pokemon__c, Highest_Level__c, Total_EXP_Points__c
            FROM Pokemon_Trainer__c WHERE OwnerId = :ownerId LIMIT 1 FOR UPDATE
        ];
        return ownedTrainers.isEmpty() ? null : ownedTrainers[0];
    }

    public static Pokemon_Trainer__c LockTrainerById(Id trainerId){
        List<Pokemon_Trainer__c> trainers = [
            SELECT Id, Name, Currency__c, Experience_Tokens__c, Poke_Balls__c, Great_Balls__c,
                   Ultra_Balls__c, Master_Balls__c, Fire_Stones__c, Water_Stones__c, Thunder_Stones__c,
                   Leaf_Stones__c, Moon_Stones__c, Shiny_Stones__c, Dusk_Stones__c, Dawn_Stones__c,
                   Rival__c, Automation_Opt_In__c,
                   Total_Pokemon__c, Shiny_Pokemon__c, Highest_Level__c, Total_EXP_Points__c
            FROM Pokemon_Trainer__c WHERE Id = :trainerId LIMIT 1 FOR UPDATE
        ];
        return trainers.isEmpty() ? null : trainers[0];
    }

    public static Pokemon_Trainer__c RequeryTrainer(Id trainerId){
        return [
            SELECT Id, Name, Currency__c, Experience_Tokens__c, Poke_Balls__c, Great_Balls__c,
                   Ultra_Balls__c, Master_Balls__c, Fire_Stones__c, Water_Stones__c, Thunder_Stones__c,
                   Leaf_Stones__c, Moon_Stones__c, Shiny_Stones__c, Dusk_Stones__c, Dawn_Stones__c,
                   Rival__c, Automation_Opt_In__c,
                   Total_Pokemon__c, Shiny_Pokemon__c, Highest_Level__c, Total_EXP_Points__c
            FROM Pokemon_Trainer__c WHERE Id = :trainerId LIMIT 1
        ];
    }

    // ---- Pokemon queries ----

    public static Pokemon__c FetchPokemon(Id pokemonId){
        List<Pokemon__c> matches = [
            SELECT Id, Pokemon_Trainer__c, Pokemon_Trainer__r.OwnerId, Nickname__c, Is_Traded__c,
                   Pokedex_Number__c, Level__c, EXP_Points__c, Is_Shiny__c, Species_Name__c
            FROM Pokemon__c WHERE Id = :pokemonId LIMIT 1
        ];
        return matches.isEmpty() ? null : matches[0];
    }

    public static Boolean OwnedByCurrentUser(Pokemon__c pokemon){
        return pokemon.Pokemon_Trainer__r.OwnerId == UserInfo.getUserId();
    }

    public static Pokemon__c RequeryPokemon(Id pokemonId){
        return [
            SELECT Id, Name, Pokemon_Trainer__c, Species_Name__c, Nickname__c, Pokedex_Number__c,
                   Level__c, EXP_Points__c, Image__c, Type__c, Type_2__c, HP__c, Attack__c, Defense__c,
                   Special_Attack__c, Special_Defense__c, Speed__c, Is_Traded__c, Is_Shiny__c, Capture_Rate__c, Can_Evolve__c
            FROM Pokemon__c WHERE Id = :pokemonId LIMIT 1
        ];
    }

    public static List<Pokemon__c> QueryRoster(Id trainerId){
        return [
            SELECT Id, Name, Pokemon_Trainer__c, Species_Name__c, Nickname__c, Pokedex_Number__c,
                   Level__c, EXP_Points__c, Image__c, Type__c, Type_2__c, HP__c, Attack__c, Defense__c,
                   Special_Attack__c, Special_Defense__c, Speed__c, Is_Traded__c, Is_Shiny__c, Capture_Rate__c, Can_Evolve__c
            FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainerId
            ORDER BY Level__c DESC, Pokedex_Number__c ASC
        ];
    }

    public static Set<Integer> OwnedSpeciesNumbers(Id trainerId){
        Set<Integer> pokedexNumbers = new Set<Integer>();
        for(Pokemon__c owned : [SELECT Pokedex_Number__c FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainerId]){
            if(owned.Pokedex_Number__c != null) pokedexNumbers.add((Integer)owned.Pokedex_Number__c);
        }
        return pokedexNumbers;
    }

    // ---- Rival ----

    // Owners eligible to be a rival: users who currently hold the Pokemon Full Access permission set
    // (this also covers assignment via a Permission Set Group, which creates a PermissionSetAssignment row for the member set).
    public static Set<Id> EligibleRivalOwnerIds(){
        Set<Id> eligibleOwnerIds = new Set<Id>();
        for(PermissionSetAssignment assignment : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'Pokemon_Full_Access' AND Assignee.IsActive = true
        ]){
            eligibleOwnerIds.add(assignment.AssigneeId);
        }
        return eligibleOwnerIds;
    }

    public static Id ResolveRivalId(Map<String,Object> params){
        String rivalValue = String.valueOf(params.get('rivalName'));
        if(String.isBlank(rivalValue) && params.containsKey('rivalTrainerId')) rivalValue = String.valueOf(params.get('rivalTrainerId'));
        if(String.isBlank(rivalValue)) return null;

        Id rivalId;
        try{
            rivalId = (Id)rivalValue.trim();
        }
        catch(Exception notAnId){
            return null;
        }

        // Enforce the rival rule server-side: only another user's trainer whose owner holds the perm set is valid,
        // so a tampered client cannot wire a non-permissioned trainer as a rival.
        Set<Id> eligibleOwnerIds = EligibleRivalOwnerIds();
        List<Pokemon_Trainer__c> rivals = [
            SELECT Id FROM Pokemon_Trainer__c
            WHERE Id = :rivalId AND OwnerId != :UserInfo.getUserId() AND OwnerId IN :eligibleOwnerIds LIMIT 1
        ];
        return rivals.isEmpty() ? null : rivals[0].Id;
    }

    // ---- Balls ----

    public static Map<String,Object> BallCounts(Pokemon_Trainer__c trainer){
        return new Map<String,Object>{
            'pokeball' => ClampToZero(trainer.Poke_Balls__c),
            'greatball' => ClampToZero(trainer.Great_Balls__c),
            'ultraball' => ClampToZero(trainer.Ultra_Balls__c),
            'masterball' => ClampToZero(trainer.Master_Balls__c)
        };
    }

    public static String BallFieldApiName(String ballType){
        if(ballType == 'greatball') return 'Great_Balls__c';
        if(ballType == 'ultraball') return 'Ultra_Balls__c';
        if(ballType == 'masterball') return 'Master_Balls__c';
        return 'Poke_Balls__c';
    }

    // ---- Stones ----

    public static Set<String> StoneKeys(){
        return new Set<String>{ 'firestone', 'waterstone', 'thunderstone', 'leafstone', 'moonstone', 'shinystone', 'duskstone', 'dawnstone' };
    }

    public static String StoneFieldApiName(String stoneKey){
        if(stoneKey == 'waterstone') return 'Water_Stones__c';
        if(stoneKey == 'thunderstone') return 'Thunder_Stones__c';
        if(stoneKey == 'leafstone') return 'Leaf_Stones__c';
        if(stoneKey == 'moonstone') return 'Moon_Stones__c';
        if(stoneKey == 'shinystone') return 'Shiny_Stones__c';
        if(stoneKey == 'duskstone') return 'Dusk_Stones__c';
        if(stoneKey == 'dawnstone') return 'Dawn_Stones__c';
        return 'Fire_Stones__c';
    }

    public static String StoneSeedName(String stoneKey){
        if(stoneKey == 'waterstone') return 'water-stone';
        if(stoneKey == 'thunderstone') return 'thunder-stone';
        if(stoneKey == 'leafstone') return 'leaf-stone';
        if(stoneKey == 'moonstone') return 'moon-stone';
        if(stoneKey == 'shinystone') return 'shiny-stone';
        if(stoneKey == 'duskstone') return 'dusk-stone';
        if(stoneKey == 'dawnstone') return 'dawn-stone';
        return 'fire-stone';
    }

    // ---- Mart ----

    public static Map<String,Decimal> BallPrices(Pokemon_Settings__mdt config){
        return new Map<String,Decimal>{
            'pokeball' => config.Poke_Ball_Price__c == null ? 50 : config.Poke_Ball_Price__c,
            'greatball' => config.Great_Ball_Price__c == null ? 150 : config.Great_Ball_Price__c,
            'ultraball' => config.Ultra_Ball_Price__c == null ? 400 : config.Ultra_Ball_Price__c
        };
    }

    public static Map<String,Decimal> ItemPrices(Pokemon_Settings__mdt config){
        Map<String,Decimal> itemPrices = BallPrices(config);
        for(String stoneKey : StoneKeys()){
            itemPrices.put(stoneKey, StonePrice(config));
        }
        return itemPrices;
    }

    public static String ItemFieldApiName(String itemType){
        return StoneKeys().contains(itemType) ? StoneFieldApiName(itemType) : BallFieldApiName(itemType);
    }

    public static Map<String,Integer> NormalizeCart(Map<String,Object> params){
        Map<String,Integer> cart = new Map<String,Integer>();

        if(params.containsKey('cart') && params.get('cart') != null){
            // LWC marshals the cart as Map<Object,Object>; round-trip through JSON so the cast to Map<String,Object> holds.
            Map<String,Object> requestedCart = (Map<String,Object>)JSON.deserializeUntyped(JSON.serialize(params.get('cart')));
            for(String itemType : requestedCart.keySet()){
                Integer quantity = ToInteger(requestedCart.get(itemType));
                if(quantity != null && quantity > 0) cart.put(itemType, quantity);
            }
            return cart;
        }

        if(params.containsKey('itemType') && String.isNotBlank(String.valueOf(params.get('itemType')))){
            String itemType = String.valueOf(params.get('itemType')).trim();
            Integer quantity = params.get('quantity') == null ? 1 : ToInteger(params.get('quantity'));
            if(quantity > 0) cart.put(itemType, quantity);
        }
        return cart;
    }

    // ---- Encounter tokens ----
    // Everything the browser must not see or edit (species, level, shiny) rides inside an AES-encrypted token.
    // GetBiomePokemon mints them; RevealEncounter and CatchPokemon decode them — the client only relays the string.

    static Blob EncounterTokenKey(){
        return Blob.valueOf('pkmn-wild-grass1');
    }

    public static String EncounterToken(Integer pokedexNumber, Integer level, Boolean isShiny){
        return EncryptEncounterPayload(new Map<String,Object>{
            'dex' => pokedexNumber,
            'level' => level,
            'shiny' => isShiny,
            'owner' => UserInfo.getUserId(),
            'issued' => Datetime.now().getTime()
        });
    }

    @TestVisible
    static String EncryptEncounterPayload(Map<String,Object> payload){
        Blob encrypted = Crypto.encryptWithManagedIV('AES128', EncounterTokenKey(), Blob.valueOf(JSON.serialize(payload)));
        return EncodingUtil.base64Encode(encrypted);
    }

    // Returns null for a missing, forged, or malformed token.
    public static Map<String,Object> DecodeEncounterToken(String token){
        if(String.isBlank(token)) return null;
        try{
            Blob decrypted = Crypto.decryptWithManagedIV('AES128', EncounterTokenKey(), EncodingUtil.base64Decode(token));
            return (Map<String,Object>)JSON.deserializeUntyped(decrypted.toString());
        }
        catch(Exception badToken){
            return null;
        }
    }

    public static Boolean EncounterTokenOwnedByCurrentUser(Map<String,Object> payload){
        return String.valueOf(payload.get('owner')) == String.valueOf(UserInfo.getUserId());
    }

    public static Boolean EncounterTokenIsFresh(Map<String,Object> payload){
        Long issued = ToLong(payload.get('issued'));
        if(issued == null) return false;
        return Datetime.now().getTime() - issued <= 3600000; // tokens live 60 minutes — plenty for a biome session
    }

    // Single-use ledger: a caught or fled encounter's token hash is recorded on the trainer (under the FOR UPDATE
    // lock), so replaying a captured token — e.g. a predetermined shiny — is refused. Broke-free stays live on
    // purpose: the trainer throws again at the same patch. Entries prune themselves past the token TTL.

    public static String EncounterTokenHash(String token){
        return EncodingUtil.base64Encode(Crypto.generateDigest('SHA-256', Blob.valueOf(token)));
    }

    public static Boolean EncounterAlreadyConsumed(Pokemon_Trainer__c trainer, String tokenHash){
        if(String.isBlank(trainer.Consumed_Encounters__c)) return false;
        return trainer.Consumed_Encounters__c.contains(tokenHash);
    }

    public static void MarkEncounterConsumed(Pokemon_Trainer__c trainer, String tokenHash){
        Long pruneCutoff = Datetime.now().getTime() - 3600000;
        List<String> keptEntries = new List<String>();
        if(String.isNotBlank(trainer.Consumed_Encounters__c)){
            for(String entry : trainer.Consumed_Encounters__c.split('\n')){
                List<String> entryParts = entry.split('\\|');
                if(entryParts.size() != 2) continue;
                try{
                    if(Long.valueOf(entryParts[1]) >= pruneCutoff) keptEntries.add(entry);
                }
                catch(Exception badEntry){
                    continue;
                }
            }
        }
        keptEntries.add(tokenHash + '|' + Datetime.now().getTime());
        trainer.Consumed_Encounters__c = String.join(keptEntries, '\n');
    }

    // ---- Minimum wild levels ----
    // A fresh trainer should never meet a Kingdra in the starter grass. Each species gets a floor derived from the
    // seed: its evolution chain (level evolutions), a stage floor for stone evolutions, a base-stat-total floor
    // (which also catches trade evolutions the seed does not link, like Seadra -> Kingdra), and a legendary floor.

    static Map<Integer,Integer> minWildLevelsByDex;

    public static Integer MinWildLevel(Integer pokedexNumber){
        if(minWildLevelsByDex == null) minWildLevelsByDex = BuildMinWildLevels();
        Integer minLevel = minWildLevelsByDex.get(pokedexNumber);
        return minLevel == null ? 1 : minLevel;
    }

    static Map<Integer,Integer> BuildMinWildLevels(){
        Map<Integer,Integer> floors = new Map<Integer,Integer>();
        Map<String,Object> catalog = PokemonSpeciesService.GetCatalog();

        for(String dexKey : catalog.keySet()){
            Map<String,Object> species = (Map<String,Object>)catalog.get(dexKey);

            // Level evolutions: the child never spawns below the level its line evolves at.
            if(species.get('evolveLevel') != null && species.get('evolvesToDex') != null){
                Integer childDex = ToInteger(species.get('evolvesToDex'));
                Integer evolveLevel = ToInteger(species.get('evolveLevel'));
                RaiseFloor(floors, childDex, evolveLevel);
            }

            // Stone evolutions: no level in the games, so give the evolved form a mid-game floor.
            if(species.get('stoneEvolutions') != null){
                Map<String,Object> stoneTargets = (Map<String,Object>)species.get('stoneEvolutions');
                for(String stoneName : stoneTargets.keySet()){
                    RaiseFloor(floors, ToInteger(stoneTargets.get(stoneName)), 25);
                }
            }

            // Powerhouses and legendaries: base-stat totals flag late-game species even when the seed
            // has no evolution link for them (trade evolutions) or no line at all (legendaries).
            Integer statTotal = StatValue(species, 'hp') + StatValue(species, 'attack') + StatValue(species, 'defense')
                + StatValue(species, 'spAtk') + StatValue(species, 'spDef') + StatValue(species, 'speed');
            Integer dex = Integer.valueOf(dexKey);
            if(statTotal >= 570) RaiseFloor(floors, dex, 45);
            else if(statTotal >= 500) RaiseFloor(floors, dex, 30);
            else if(statTotal >= 420) RaiseFloor(floors, dex, 15);

            if(species.get('isLegendary') == true || species.get('isMythical') == true) RaiseFloor(floors, dex, 45);
        }
        return floors;
    }

    static void RaiseFloor(Map<Integer,Integer> floors, Integer dex, Integer floorLevel){
        if(dex == null || floorLevel == null) return;
        Integer existing = floors.get(dex);
        if(existing == null || floorLevel > existing) floors.put(dex, floorLevel);
    }

    static Integer StatValue(Map<String,Object> species, String statKey){
        Integer value = ToInteger(species.get(statKey));
        return value == null ? 0 : value;
    }

    // ---- Biome encounters ----

    public static Map<String,Object> WeightedEncounter(List<Object> encounters, Decimal totalWeight){
        Decimal roll = Decimal.valueOf(Math.random()) * totalWeight;
        Decimal runningWeight = 0;
        for(Object entry : encounters){
            Map<String,Object> encounter = (Map<String,Object>)entry;
            runningWeight += TierWeight(String.valueOf(encounter.get('tier')));
            if(roll < runningWeight) return encounter;
        }
        return (Map<String,Object>)encounters[encounters.size() - 1];
    }

    // ---- Tiers (thresholds + weights shared with the species seed generator) ----

    public static String TierForCaptureRate(Integer captureRate){
        if(captureRate == null) return 'uncommon';
        if(captureRate >= 120) return 'common';
        if(captureRate <= 44) return 'rare';
        return 'uncommon';
    }

    public static Integer TierWeight(String tier){
        if(tier == 'common') return 12;
        if(tier == 'rare') return 2;
        return 6;
    }

    // ---- Trainer-scaled level bands ----

    public static Integer LevelOffsetMin(String tier, Pokemon_Settings__mdt config){
        if(tier == 'common') return config.Common_Level_Offset_Min__c == null ? -8 : config.Common_Level_Offset_Min__c.intValue();
        if(tier == 'rare') return config.Rare_Level_Offset_Min__c == null ? -4 : config.Rare_Level_Offset_Min__c.intValue();
        return config.Uncommon_Level_Offset_Min__c == null ? -6 : config.Uncommon_Level_Offset_Min__c.intValue();
    }

    public static Integer LevelOffsetMax(String tier, Pokemon_Settings__mdt config){
        if(tier == 'common') return config.Common_Level_Offset_Max__c == null ? -4 : config.Common_Level_Offset_Max__c.intValue();
        if(tier == 'rare') return config.Rare_Level_Offset_Max__c == null ? -1 : config.Rare_Level_Offset_Max__c.intValue();
        return config.Uncommon_Level_Offset_Max__c == null ? -3 : config.Uncommon_Level_Offset_Max__c.intValue();
    }

    public static Integer AnchorLevel(Decimal highestRosterLevel, Pokemon_Settings__mdt config){
        Integer floor = config.Catch_Level_Min__c == null ? 2 : config.Catch_Level_Min__c.intValue();
        Integer highest = highestRosterLevel == null ? 0 : highestRosterLevel.intValue();
        return highest > floor ? highest : floor;
    }

    public static Map<String,Integer> LevelBandForTier(String tier, Integer anchor, Pokemon_Settings__mdt config){
        Integer minLevel = ClampLevel(anchor + LevelOffsetMin(tier, config));
        Integer maxLevel = ClampLevel(anchor + LevelOffsetMax(tier, config));
        if(minLevel > maxLevel) minLevel = maxLevel;
        return new Map<String,Integer>{ 'min' => minLevel, 'max' => maxLevel };
    }

    public static Integer RandomLevelInBand(Map<String,Integer> band){
        Integer minLevel = band.get('min');
        Integer maxLevel = band.get('max');
        return minLevel + (Integer)Math.floor(Math.random() * (maxLevel - minLevel + 1));
    }

    // ---- Level range clamp (1..100) ----

    public static Integer ClampLevel(Integer level){
        if(level < 1) return 1;
        if(level > 100) return 100;
        return level;
    }

    public static Integer ClampToBand(Integer level, Map<String,Integer> band){
        return Math.min(Math.max(level, band.get('min')), band.get('max'));
    }

    // ---- Settings ----

    public static Pokemon_Settings__mdt Settings(){
        Pokemon_Settings__mdt config = Pokemon_Settings__mdt.getInstance('Default');
        return config == null ? new Pokemon_Settings__mdt() : config;
    }

    public static Integer RandomCatchLevel(Pokemon_Settings__mdt config){
        Integer minLevel = config.Catch_Level_Min__c == null ? 2 : config.Catch_Level_Min__c.intValue();
        Integer maxLevel = config.Catch_Level_Max__c == null ? 6 : config.Catch_Level_Max__c.intValue();
        return minLevel + (Integer)Math.floor(Math.random() * (maxLevel - minLevel + 1));
    }

    public static Integer ShinyRate(Pokemon_Settings__mdt config){
        return config.Shiny_Rate__c == null ? 512 : config.Shiny_Rate__c.intValue();
    }

    public static Integer CriticalCaptureRate(Pokemon_Settings__mdt config){
        return config.Critical_Capture_Rate__c == null ? 20 : config.Critical_Capture_Rate__c.intValue();
    }

    public static Decimal CatchRateMultiplier(Pokemon_Settings__mdt config){
        return config.Catch_Rate_Multiplier__c == null ? 1.0 : config.Catch_Rate_Multiplier__c;
    }

    public static Decimal StonePrice(Pokemon_Settings__mdt config){
        return config.Stone_Price__c == null ? 1200 : config.Stone_Price__c;
    }

    public static Decimal FleeChanceForTier(String tier, Pokemon_Settings__mdt config){
        if(tier == 'rare') return config != null && config.Flee_Chance_Rare__c != null ? config.Flee_Chance_Rare__c : 15;
        if(tier == 'uncommon') return config != null && config.Flee_Chance_Uncommon__c != null ? config.Flee_Chance_Uncommon__c : 12.5;
        return config != null && config.Flee_Chance_Common__c != null ? config.Flee_Chance_Common__c : 10;
    }

    public static Integer MasterBallMilestone(Pokemon_Settings__mdt config){
        return config.Master_Ball_Dex_Milestone__c == null ? 10 : config.Master_Ball_Dex_Milestone__c.intValue();
    }

    // ---- Clamp ----

    public static Decimal ClampToZero(Decimal value){
        return value == null || value < 0 ? 0 : value;
    }
}