/* Title: pokemonGameController
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Thin @AuraEnabled surface for the Pokemon game — onboarding, catch, power-up, mart, trade, release, rename, biome encounters. Server-authoritative economy; results-map contract. Mechanics live in pokemonGameHelper.
 * Test Class: pokemonGameController_Test - 90%
 * Modified: Garrett Kent - 06/20/2026 - S5.8 trainer-scaled encounters + secure catch-level + shiny-on-catch
 * Modified: Garrett Kent - 06/21/2026 - Critical capture on catch, stone purchases + EvolveWithStone, ToLong token coercion
 * Modified: Garrett Kent - 06/25/2026 - Resolve catch level before the throw and feed it into level-banded catch odds
 * Modified: Garrett Kent - 07/04/2026 - Pokemon-like nickname cap (12 characters) on rename
 * Modified: Garrett Kent - 07/05/2026 - Encrypted encounter tokens: patches hide species/level/shiny from the browser, RevealEncounter opens them, CatchPokemon consumes them; minimum wild levels; shiny rolled at patch time; friendly catch-rate multiplier
 * Modified: Garrett Kent - 07/05/2026 - Single-use tokens: a caught or fled encounter is ledgered on the trainer so a captured token cannot be replayed to farm shinies; broke-free stays throwable
 * Modified: Garrett Kent - 07/21/2026 - Added SetRival so a trainer can change (or clear) their rival from the Trainer Hub
 * Modified: Garrett Kent - 07/22/2026 - Mart-only balls: 10 starter Poke Balls, Master Ball milestone grant commented out, trainer ball guard opened around game DML
 */
public with sharing class pokemonGameController {

    // Test-only seams so the three CatchPokemon outcomes (caught / broke free / fled) can be exercised deterministically.
    @TestVisible static Boolean catchOverride;
    @TestVisible static Decimal fleeChanceOverride;
    @TestVisible static Boolean criticalCaptureOverride;

    @AuraEnabled
    public static Map<String,Object> CreateTrainer(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            List<Pokemon_Trainer__c> existingTrainers = [
                SELECT Id, Name FROM Pokemon_Trainer__c WHERE OwnerId = :UserInfo.getUserId() LIMIT 1
            ];
            if(!existingTrainers.isEmpty()){
                results.put('trainer', existingTrainers[0]);
                return Warn(results, 'Trainer already exists for this user');
            }

            if(!params.containsKey('starterPokedexId') || params.get('starterPokedexId') == null) return Fail(results, 'CreateTrainer', 'Starter Pokedex Id Required');
            Integer starterPokedexNumber = pokemonGameHelper.ToInteger(params.get('starterPokedexId'));

            Set<Integer> allowedStarters = new Set<Integer>{ 1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 25, 133, 447, 129, 63 };
            if(!allowedStarters.contains(starterPokedexNumber)) return Fail(results, 'CreateTrainer', starterPokedexNumber + ' is not an allowed starter');

            Map<String,Object> starterSpecies = pokemonGameHelper.Species(starterPokedexNumber);
            if(starterSpecies == null) return Fail(results, 'CreateTrainer', 'Species not found for dex ' + starterPokedexNumber);

            Pokemon_Trainer__c trainer = NewTrainer(params);
            Pokemon_Settings__mdt config = pokemonGameHelper.Settings();
            Integer starterLevel = pokemonGameHelper.RandomCatchLevel(config);
            Boolean starterIsShiny = pokemonCatchLogic.RollShiny(pokemonGameHelper.ShinyRate(config));

            pokemonTrainerOrgHelper.allowBallChanges = true;
            Savepoint savePoint = Database.setSavepoint();
            try{
                INSERT trainer;
                Pokemon__c starter = pokemonGameHelper.BuildPokemon(starterSpecies, starterPokedexNumber, starterLevel, starterIsShiny, trainer.Id);
                INSERT starter;
                results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
                results.put('starter', pokemonGameHelper.RequeryPokemon(starter.Id));
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }
            finally{
                pokemonTrainerOrgHelper.allowBallChanges = false;
            }
        }
        catch(Exception error){
            Fail(results, 'CreateTrainer', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> GetMyTrainer(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            results.put('currentUserName', UserInfo.getName());

            List<Pokemon_Trainer__c> ownedTrainers = [
                SELECT Id FROM Pokemon_Trainer__c WHERE OwnerId = :UserInfo.getUserId() LIMIT 1
            ];
            if(ownedTrainers.isEmpty()){
                results.put('trainer', null);
                return results;
            }

            Id trainerId = ownedTrainers[0].Id;
            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainerId));
            if(IncludePokemon(params)) results.put('pokemon', pokemonGameHelper.QueryRoster(trainerId));
        }
        catch(Exception error){
            Fail(results, 'GetMyTrainer', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> GetTrainer(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('trainerId') || String.isBlank(String.valueOf(params.get('trainerId')))) return Fail(results, 'GetTrainer', 'Trainer Id Required');
            Id trainerId = (Id)params.get('trainerId');

            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainerId));
            if(IncludePokemon(params)) results.put('pokemon', pokemonGameHelper.QueryRoster(trainerId));
        }
        catch(Exception error){
            Fail(results, 'GetTrainer', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> CatchAttempt(Map<String,Object> params){
        return CatchPokemon(params);
    }

    @AuraEnabled
    public static Map<String,Object> CatchPokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('token') || String.isBlank(String.valueOf(params.get('token')))) return Fail(results, 'CatchPokemon', 'Encounter token required');

            String ballType = String.isBlank(String.valueOf(params.get('ballType'))) ? '' : String.valueOf(params.get('ballType')).trim();
            Set<String> validBalls = new Set<String>{ 'pokeball', 'greatball', 'ultraball', 'masterball' };
            if(!validBalls.contains(ballType)) return Fail(results, 'CatchPokemon', 'Invalid ball type');

            // The token was minted server-side by GetBiomePokemon and encrypted, so the browser can neither read
            // nor forge the species, level, or shiny outcome hiding in the grass — it only relays the string back.
            Map<String,Object> encounterPayload = pokemonGameHelper.DecodeEncounterToken(String.valueOf(params.get('token')));
            if(encounterPayload == null) return Fail(results, 'CatchPokemon', 'Invalid encounter token');
            if(!pokemonGameHelper.EncounterTokenOwnedByCurrentUser(encounterPayload)) return Reject(results, 'This encounter belongs to another trainer');
            if(!pokemonGameHelper.EncounterTokenIsFresh(encounterPayload)) return Warn(results, 'The wild Pokemon wandered off — explore the biome again');

            Integer pokedexNumber = pokemonGameHelper.ToInteger(encounterPayload.get('dex'));
            Integer tokenLevel = pokemonGameHelper.ToInteger(encounterPayload.get('level'));
            if(pokedexNumber == null || tokenLevel == null) return Fail(results, 'CatchPokemon', 'Invalid encounter token');
            Integer level = pokemonGameHelper.ClampLevel(tokenLevel);
            Boolean isShiny = encounterPayload.get('shiny') == true;

            Map<String,Object> species = pokemonGameHelper.Species(pokedexNumber);
            if(species == null) return Fail(results, 'CatchPokemon', 'Species not found for dex ' + pokedexNumber);

            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerForCurrentUser();
            if(trainer == null) return Reject(results, 'No trainer for this user');

            // Single-use: a caught or fled encounter is spent — replaying its token (shiny farming) is refused.
            String tokenHash = pokemonGameHelper.EncounterTokenHash(String.valueOf(params.get('token')));
            if(pokemonGameHelper.EncounterAlreadyConsumed(trainer, tokenHash)) return Warn(results, 'This patch of grass has already been searched');

            String ballField = pokemonGameHelper.BallFieldApiName(ballType);
            Decimal ballCount = (Decimal)trainer.get(ballField);
            if(ballCount == null || ballCount < 1){
                results.put('ballCounts', pokemonGameHelper.BallCounts(trainer));
                return Warn(results, 'No ' + ballType + ' remaining');
            }

            Pokemon_Settings__mdt config = pokemonGameHelper.Settings();
            String tier = pokemonGameHelper.TierForCaptureRate((Integer)species.get('captureRate'));

            Decimal catchProbability = pokemonCatchLogic.ComputeCatchProbability((Integer)species.get('captureRate'), ballType, level, pokemonGameHelper.CatchRateMultiplier(config));
            Boolean caught = catchOverride != null ? catchOverride : (Decimal.valueOf(Math.random()) < catchProbability);

            trainer.put(ballField, pokemonGameHelper.ClampToZero(ballCount - 1));

            // A missed catch isn't always the end: the wild Pokemon may break free and stay (the trainer can throw again)
            // or flee for good. The flee chance scales by rarity tier and is rolled server-side so a client can't dodge it.
            Boolean fled = false;
            if(!caught){
                Decimal fleeChance = fleeChanceOverride != null ? fleeChanceOverride : pokemonGameHelper.FleeChanceForTier(tier, config);
                fled = pokemonCatchLogic.RollFlee(fleeChance);
            }

            // Shiny was predetermined when the patch was rolled (it drove the golden tile glow and the shiny artwork);
            // the catch simply honors it. Only the critical-capture flourish is still rolled at throw time.
            Boolean caughtShiny = caught && isShiny;
            Boolean criticalCapture = false;
            Pokemon__c caughtPokemon = null;
            // Master Ball milestone grant disabled 07/22/2026 (Master Balls are unobtainable; the trainer trigger guard also blocks any increase):
            // Integer masterBallsGranted = 0;
            if(caught){
                criticalCapture = criticalCaptureOverride != null ? criticalCaptureOverride : pokemonCatchLogic.RollCriticalCapture(pokemonGameHelper.CriticalCaptureRate(config));
                caughtPokemon = pokemonGameHelper.BuildPokemon(species, pokedexNumber, level, isShiny, trainer.Id);
                // masterBallsGranted = MasterBallsForMilestone(trainer, pokedexNumber, config);
                // if(masterBallsGranted > 0) trainer.Master_Balls__c = pokemonGameHelper.ClampToZero(trainer.Master_Balls__c) + masterBallsGranted;
            }

            // Caught or fled spends the encounter; broke-free leaves it live so the trainer can throw again.
            if(caught || fled) pokemonGameHelper.MarkEncounterConsumed(trainer, tokenHash);

            pokemonTrainerOrgHelper.allowBallChanges = true;
            Savepoint savePoint = Database.setSavepoint();
            try{
                UPDATE trainer;
                if(caught){
                    INSERT caughtPokemon;
                    caughtPokemon = pokemonGameHelper.RequeryPokemon(caughtPokemon.Id);
                }
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }
            finally{
                pokemonTrainerOrgHelper.allowBallChanges = false;
            }

            Pokemon_Trainer__c refreshedTrainer = pokemonGameHelper.RequeryTrainer(trainer.Id);
            results.put('caught', caught);
            results.put('fled', fled);
            results.put('pokemon', caughtPokemon);
            results.put('isShiny', caughtShiny);
            results.put('criticalCapture', criticalCapture);
            results.put('probability', catchProbability);
            results.put('ballCounts', pokemonGameHelper.BallCounts(refreshedTrainer));
            // results.put('masterBallsGranted', masterBallsGranted);
            results.put('message', caught ? 'Gotcha! Pokemon caught.' : (fled ? 'Oh no! The Pokemon fled!' : 'The Pokemon broke free!'));
        }
        catch(Exception error){
            Fail(results, 'CatchPokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> PowerUpPokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'PowerUpPokemon', 'Pokemon Id Required');
            if(!params.containsKey('tokensToSpend') || params.get('tokensToSpend') == null) return Fail(results, 'PowerUpPokemon', 'Tokens To Spend Required');

            Id pokemonId = (Id)params.get('pokemonId');
            Long tokensToSpend = pokemonGameHelper.ToLong(params.get('tokensToSpend'));

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'PowerUpPokemon', pokemonId);
            if(pokemon == null) return results;

            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerById(pokemon.Pokemon_Trainer__c);
            Decimal heldTokens = pokemonGameHelper.ClampToZero(trainer.Experience_Tokens__c);
            if(tokensToSpend <= 0 || tokensToSpend > heldTokens) return Warn(results, 'Not enough experience tokens');

            Map<String,Object> species = pokemonGameHelper.Species((Integer)pokemon.Pokedex_Number__c);
            if(species == null) return Fail(results, 'PowerUpPokemon', 'Species not found for dex ' + pokemon.Pokedex_Number__c);
            String growthRate = String.valueOf(species.get('growthRate'));

            Long maxExp = pokemonCatchLogic.ExpForLevel(growthRate, 100);
            Long currentExp = pokemon.EXP_Points__c == null ? 0 : pokemon.EXP_Points__c.longValue();
            Long roomToMax = maxExp - currentExp;
            Long tokensSpent = tokensToSpend < roomToMax ? tokensToSpend : roomToMax;
            if(tokensSpent <= 0) return Warn(results, 'Already at max level');

            Long updatedExp = currentExp + tokensSpent;
            pokemon.EXP_Points__c = updatedExp;
            pokemon.Level__c = pokemonCatchLogic.LevelForExp(growthRate, updatedExp);
            trainer.Experience_Tokens__c = pokemonGameHelper.ClampToZero(heldTokens - tokensSpent);

            Savepoint savePoint = Database.setSavepoint();
            try{
                UPDATE trainer;
                UPDATE pokemon;
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }

            results.put('pokemon', pokemonGameHelper.RequeryPokemon(pokemon.Id));
            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
            results.put('tokensSpent', tokensSpent);
        }
        catch(Exception error){
            Fail(results, 'PowerUpPokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> BuyItem(Map<String,Object> params){
        return PurchaseItems(params);
    }

    @AuraEnabled
    public static Map<String,Object> PurchaseItems(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            Map<String,Integer> cart = pokemonGameHelper.NormalizeCart(params);
            if(cart.isEmpty()) return Fail(results, 'PurchaseItems', 'No items to purchase');

            Pokemon_Settings__mdt config = pokemonGameHelper.Settings();
            Map<String,Decimal> itemPrices = pokemonGameHelper.ItemPrices(config);
            Decimal totalCost = 0;
            for(String itemType : cart.keySet()){
                if(!itemPrices.containsKey(itemType)) return Reject(results, 'Item not purchasable');
                totalCost += itemPrices.get(itemType) * cart.get(itemType);
            }

            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerForCurrentUser();
            if(trainer == null) return Reject(results, 'No trainer for this user');

            Decimal availableCurrency = pokemonGameHelper.ClampToZero(trainer.Currency__c);
            if(availableCurrency < totalCost) return Warn(results, 'Not enough currency');

            trainer.Currency__c = pokemonGameHelper.ClampToZero(availableCurrency - totalCost);
            for(String itemType : cart.keySet()){
                String itemField = pokemonGameHelper.ItemFieldApiName(itemType);
                Decimal currentCount = pokemonGameHelper.ClampToZero((Decimal)trainer.get(itemField));
                trainer.put(itemField, currentCount + cart.get(itemType));
            }

            pokemonTrainerOrgHelper.allowBallChanges = true;
            Savepoint savePoint = Database.setSavepoint();
            try{
                UPDATE trainer;
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }
            finally{
                pokemonTrainerOrgHelper.allowBallChanges = false;
            }

            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
            results.put('totalSpent', totalCost);
        }
        catch(Exception error){
            Fail(results, 'PurchaseItems', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> TradePokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'TradePokemon', 'Pokemon Id Required');
            if(!params.containsKey('targetTrainerId') || String.isBlank(String.valueOf(params.get('targetTrainerId')))) return Fail(results, 'TradePokemon', 'Target Trainer Id Required');

            Id pokemonId = (Id)params.get('pokemonId');
            Id targetTrainerId = (Id)params.get('targetTrainerId');

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'TradePokemon', pokemonId);
            if(pokemon == null) return results;
            if(pokemon.Pokemon_Trainer__c == targetTrainerId) return Warn(results, 'Pokemon already belongs to that trainer');

            // Lock the source trainer first so a concurrent trade/release cannot both pass the roster guard and drain it to zero.
            pokemonGameHelper.LockTrainerById(pokemon.Pokemon_Trainer__c);
            Integer sourceRosterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :pokemon.Pokemon_Trainer__c];
            if(sourceRosterCount <= 1) return Warn(results, 'You cannot trade away your last Pokemon');

            // The target must be another active player who holds the perm set — same eligibility as rivals.
            // With the object now Public Read Only, an ungated target would let a tampered client reparent a Pokemon onto any trainer.
            Set<Id> eligibleOwnerIds = pokemonGameHelper.EligibleRivalOwnerIds();
            List<Pokemon_Trainer__c> targetTrainers = [
                SELECT Id FROM Pokemon_Trainer__c
                WHERE Id = :targetTrainerId AND OwnerId != :UserInfo.getUserId() AND OwnerId IN :eligibleOwnerIds LIMIT 1
            ];
            if(targetTrainers.isEmpty()) return Fail(results, 'TradePokemon', 'Target trainer not found');

            pokemon.Pokemon_Trainer__c = targetTrainerId;
            pokemon.Is_Traded__c = true;
            UPDATE pokemon;

            results.put('pokemon', pokemonGameHelper.RequeryPokemon(pokemon.Id));
        }
        catch(Exception error){
            Fail(results, 'TradePokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> ReleasePokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'ReleasePokemon', 'Pokemon Id Required');
            Id pokemonId = (Id)params.get('pokemonId');

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'ReleasePokemon', pokemonId);
            if(pokemon == null) return results;

            Id parentTrainerId = pokemon.Pokemon_Trainer__c;
            // Lock the trainer first so two concurrent releases serialize — otherwise both could read the same
            // roster count, both pass the guard, and drain the roster to zero.
            pokemonGameHelper.LockTrainerById(parentTrainerId);
            Integer rosterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :parentTrainerId];
            if(rosterCount <= 1) return Warn(results, 'You cannot release your last Pokemon');

            DELETE pokemon;

            results.put('trainerId', parentTrainerId);
        }
        catch(Exception error){
            Fail(results, 'ReleasePokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> RenamePokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'RenamePokemon', 'Pokemon Id Required');
            Id pokemonId = (Id)params.get('pokemonId');
            String nickname = String.valueOf(params.get('nickname'));

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'RenamePokemon', pokemonId);
            if(pokemon == null) return results;
            if(pokemon.Is_Traded__c == true) return Warn(results, 'A traded Pokemon cannot be renamed');

            String trimmedNickname = String.isBlank(nickname) ? null : nickname.trim();
            if(trimmedNickname != null && trimmedNickname.length() > 12) return Warn(results, 'Nicknames are limited to 12 characters');

            pokemon.Nickname__c = trimmedNickname;
            UPDATE pokemon;

            results.put('pokemon', pokemonGameHelper.RequeryPokemon(pokemon.Id));
        }
        catch(Exception error){
            Fail(results, 'RenamePokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> EvolvePokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'EvolvePokemon', 'Pokemon Id Required');
            Id pokemonId = (Id)params.get('pokemonId');

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'EvolvePokemon', pokemonId);
            if(pokemon == null) return results;

            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerById(pokemon.Pokemon_Trainer__c);

            Map<String,Object> species = pokemonGameHelper.Species((Integer)pokemon.Pokedex_Number__c);
            if(species == null) return Fail(results, 'EvolvePokemon', 'Species not found for dex ' + pokemon.Pokedex_Number__c);

            // Re-validate eligibility server-side — never trust the client.
            if(!species.containsKey('evolveLevel')) return Warn(results, 'This Pokemon cannot evolve');
            Integer evolveLevel = pokemonGameHelper.ToInteger(species.get('evolveLevel'));
            if(pokemon.Level__c == null || pokemon.Level__c < evolveLevel) return Warn(results, 'Not high enough level to evolve yet');

            Integer evolvesToDex = pokemonGameHelper.ToInteger(species.get('evolvesToDex'));
            Map<String,Object> evolvedSpecies = pokemonGameHelper.Species(evolvesToDex);
            if(evolvedSpecies == null) return Fail(results, 'EvolvePokemon', 'Evolved species not found for dex ' + evolvesToDex);

            Integer oldLevel = (Integer)pokemon.Level__c;
            Pokemon__c evolved = pokemonGameHelper.BuildPokemon(evolvedSpecies, evolvesToDex, oldLevel, pokemon.Is_Shiny__c, trainer.Id);
            evolved.EXP_Points__c = pokemon.EXP_Points__c;
            evolved.Is_Traded__c = pokemon.Is_Traded__c;
            if(String.isNotBlank(pokemon.Nickname__c) && pokemon.Nickname__c != pokemon.Species_Name__c) evolved.Nickname__c = pokemon.Nickname__c;

            Savepoint savePoint = Database.setSavepoint();
            try{
                INSERT evolved;
                DELETE pokemon;
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }

            results.put('pokemon', pokemonGameHelper.RequeryPokemon(evolved.Id));
            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
            results.put('message', 'Congratulations! Your Pokemon evolved.');
        }
        catch(Exception error){
            Fail(results, 'EvolvePokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> EvolveWithStone(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokemonId') || String.isBlank(String.valueOf(params.get('pokemonId')))) return Fail(results, 'EvolveWithStone', 'Pokemon Id Required');
            Id pokemonId = (Id)params.get('pokemonId');

            String stone = String.isBlank(String.valueOf(params.get('stone'))) ? '' : String.valueOf(params.get('stone')).toLowerCase().trim();
            if(!pokemonGameHelper.StoneKeys().contains(stone)) return Fail(results, 'EvolveWithStone', 'Invalid stone');

            Pokemon__c pokemon = LoadOwnedPokemon(results, 'EvolveWithStone', pokemonId);
            if(pokemon == null) return results;

            Map<String,Object> species = pokemonGameHelper.Species((Integer)pokemon.Pokedex_Number__c);
            if(species == null) return Fail(results, 'EvolveWithStone', 'Species not found for dex ' + pokemon.Pokedex_Number__c);

            // Re-validate eligibility server-side — never trust the client.
            if(!species.containsKey('stoneEvolutions')) return Warn(results, 'This Pokemon cannot evolve with a stone');
            Map<String,Object> stoneEvolutions = (Map<String,Object>)species.get('stoneEvolutions');
            String seedName = pokemonGameHelper.StoneSeedName(stone);
            if(!stoneEvolutions.containsKey(seedName)) return Warn(results, 'That stone has no effect on this Pokemon');

            Integer evolvesToDex = pokemonGameHelper.ToInteger(stoneEvolutions.get(seedName));
            Map<String,Object> evolvedSpecies = pokemonGameHelper.Species(evolvesToDex);
            if(evolvedSpecies == null) return Fail(results, 'EvolveWithStone', 'Evolved species not found for dex ' + evolvesToDex);

            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerById(pokemon.Pokemon_Trainer__c);
            String stoneField = pokemonGameHelper.StoneFieldApiName(stone);
            Decimal stoneCount = pokemonGameHelper.ClampToZero((Decimal)trainer.get(stoneField));
            if(stoneCount < 1) return Warn(results, 'You do not have that stone');

            Integer currentLevel = (Integer)pokemon.Level__c;
            Pokemon__c evolved = pokemonGameHelper.BuildPokemon(evolvedSpecies, evolvesToDex, currentLevel, pokemon.Is_Shiny__c, trainer.Id);
            evolved.EXP_Points__c = pokemon.EXP_Points__c;
            evolved.Is_Traded__c = pokemon.Is_Traded__c;
            if(String.isNotBlank(pokemon.Nickname__c) && pokemon.Nickname__c != pokemon.Species_Name__c) evolved.Nickname__c = pokemon.Nickname__c;
            trainer.put(stoneField, pokemonGameHelper.ClampToZero(stoneCount - 1));

            Savepoint savePoint = Database.setSavepoint();
            try{
                INSERT evolved;
                UPDATE trainer;
                DELETE pokemon;
            }
            catch(Exception dmlError){
                Database.rollback(savePoint);
                throw dmlError;
            }

            results.put('pokemon', pokemonGameHelper.RequeryPokemon(evolved.Id));
            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
            results.put('message', 'Congratulations! Your Pokemon evolved.');
        }
        catch(Exception error){
            Fail(results, 'EvolveWithStone', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> GetBiomePokemon(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('biome') || String.isBlank(String.valueOf(params.get('biome')))) return Fail(results, 'GetBiomePokemon', 'Biome Required');
            String biomeName = String.valueOf(params.get('biome')).trim();

            Pokemon_Biome__mdt biome = FindBiome(biomeName);
            if(biome == null || biome.Active__c != true) return Fail(results, 'GetBiomePokemon', 'Biome not found or inactive');

            List<Object> encounters = (List<Object>)JSON.deserializeUntyped(biome.Encounters_Json__c);
            Integer patchCount = ResolvePatchCount(params, biome, encounters.size());

            Pokemon_Settings__mdt config = pokemonGameHelper.Settings();
            Decimal trainerHighestLevel = CurrentTrainerHighestLevel();
            Integer anchor = pokemonGameHelper.AnchorLevel(trainerHighestLevel, config);

            // Evolved forms, powerhouses, and legendaries wait until the trainer's band can reach their minimum
            // wild level — a rookie never meets a Kingdra in the starter grass.
            List<Object> eligibleEncounters = new List<Object>();
            for(Object entry : encounters){
                Map<String,Object> encounter = (Map<String,Object>)entry;
                String tier = String.valueOf(encounter.get('tier'));
                Map<String,Integer> band = pokemonGameHelper.LevelBandForTier(tier, anchor, config);
                if(pokemonGameHelper.MinWildLevel(pokemonGameHelper.ToInteger(encounter.get('dex'))) <= band.get('max')) eligibleEncounters.add(entry);
            }
            if(eligibleEncounters.isEmpty()) eligibleEncounters = encounters; // pathological config fallback — better a strong spawn than an empty meadow

            Decimal totalWeight = 0;
            for(Object entry : eligibleEncounters){
                totalWeight += pokemonGameHelper.TierWeight(String.valueOf(((Map<String,Object>)entry).get('tier')));
            }

            List<Map<String,Object>> patches = new List<Map<String,Object>>();
            for(Integer patchIndex = 0; patchIndex < patchCount; patchIndex++){
                patches.add(BuildPatch(pokemonGameHelper.WeightedEncounter(eligibleEncounters, totalWeight), anchor, config));
            }

            results.put('patches', patches);
            results.put('backgroundImageUrl', biome.Background_Image_Url__c);
        }
        catch(Exception error){
            Fail(results, 'GetBiomePokemon', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> RevealEncounter(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('token') || String.isBlank(String.valueOf(params.get('token')))) return Fail(results, 'RevealEncounter', 'Encounter token required');

            Map<String,Object> encounterPayload = pokemonGameHelper.DecodeEncounterToken(String.valueOf(params.get('token')));
            if(encounterPayload == null) return Fail(results, 'RevealEncounter', 'Invalid encounter token');
            if(!pokemonGameHelper.EncounterTokenOwnedByCurrentUser(encounterPayload)) return Reject(results, 'This encounter belongs to another trainer');
            if(!pokemonGameHelper.EncounterTokenIsFresh(encounterPayload)) return Warn(results, 'The wild Pokemon wandered off — explore the biome again');

            // Already caught or fled? The grass is empty — keep the reveal honest with the catch path.
            List<Pokemon_Trainer__c> ownedTrainers = [SELECT Consumed_Encounters__c FROM Pokemon_Trainer__c WHERE OwnerId = :UserInfo.getUserId() LIMIT 1];
            if(!ownedTrainers.isEmpty() && pokemonGameHelper.EncounterAlreadyConsumed(ownedTrainers[0], pokemonGameHelper.EncounterTokenHash(String.valueOf(params.get('token'))))){
                return Warn(results, 'This patch of grass has already been searched');
            }

            Integer pokedexNumber = pokemonGameHelper.ToInteger(encounterPayload.get('dex'));
            Integer level = pokemonGameHelper.ToInteger(encounterPayload.get('level'));
            if(pokedexNumber == null || level == null) return Fail(results, 'RevealEncounter', 'Invalid encounter token');
            Boolean isShiny = encounterPayload.get('shiny') == true;

            Map<String,Object> species = pokemonGameHelper.Species(pokedexNumber);
            if(species == null) return Fail(results, 'RevealEncounter', 'Species not found for dex ' + pokedexNumber);

            results.put('dex', pokedexNumber);
            results.put('name', species.get('name'));
            results.put('image', pokemonGameHelper.ArtworkUrl(species, pokedexNumber, isShiny));
            results.put('type1', species.get('type1'));
            results.put('type2', species.containsKey('type2') ? species.get('type2') : null);
            results.put('level', level);
            results.put('isShiny', isShiny);
        }
        catch(Exception error){
            Fail(results, 'RevealEncounter', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> GetOtherTrainers(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            List<Map<String,Object>> otherTrainers = new List<Map<String,Object>>();
            Set<Id> eligibleOwnerIds = pokemonGameHelper.EligibleRivalOwnerIds();
            for(Pokemon_Trainer__c trainer : [
                SELECT Id, Name FROM Pokemon_Trainer__c
                WHERE OwnerId != :UserInfo.getUserId() AND OwnerId IN :eligibleOwnerIds ORDER BY Name LIMIT 200
            ]){
                otherTrainers.add(new Map<String,Object>{ 'label' => trainer.Name, 'value' => trainer.Id });
            }
            results.put('otherTrainers', otherTrainers);
        }
        catch(Exception error){
            Fail(results, 'GetOtherTrainers', error);
        }
        return results;
    }

    @AuraEnabled
    public static Map<String,Object> SetRival(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            Pokemon_Trainer__c trainer = pokemonGameHelper.LockTrainerForCurrentUser();
            if(trainer == null) return Reject(results, 'You do not have a trainer yet');

            // ResolveRivalId validates the pick server-side (another user's trainer whose owner holds the perm set)
            // and returns null for a blank value, which clears the rival — the N/A option.
            trainer.Rival__c = pokemonGameHelper.ResolveRivalId(params);
            UPDATE trainer;

            results.put('trainer', pokemonGameHelper.RequeryTrainer(trainer.Id));
        }
        catch(Exception error){
            Fail(results, 'SetRival', error);
        }
        return results;
    }

    // ---- Private orchestration helpers ----

    static Pokemon_Trainer__c NewTrainer(Map<String,Object> params){
        String requestedName = String.valueOf(params.get('trainerName'));
        return new Pokemon_Trainer__c(
            Name = String.isBlank(requestedName) ? UserInfo.getName() : requestedName.trim(),
            Currency__c = 500,
            Poke_Balls__c = 10,
            Great_Balls__c = 0,
            Ultra_Balls__c = 0,
            Master_Balls__c = 0,
            Experience_Tokens__c = 0,
            Automation_Opt_In__c = true,
            Rival__c = pokemonGameHelper.ResolveRivalId(params)
        );
    }

    // Master Ball milestone grant disabled 07/22/2026 — to re-enable, restore this with the commented CatchPokemon lines,
    // the pokemonGameHelper accessors, and relax the Master Ball block in pokemonTrainerOrgHelper.GuardBallFields.
    // static Integer MasterBallsForMilestone(Pokemon_Trainer__c trainer, Integer pokedexNumber, Pokemon_Settings__mdt config){
    //     Set<Integer> ownedSpecies = pokemonGameHelper.OwnedSpeciesNumbers(trainer.Id);
    //     Integer milestone = pokemonGameHelper.MasterBallMilestone(config);
    //     Integer beforeUnique = ownedSpecies.size();
    //     Integer afterUnique = beforeUnique + (ownedSpecies.contains(pokedexNumber) ? 0 : 1);
    //     return (afterUnique / milestone) - (beforeUnique / milestone);
    // }

    static Pokemon__c LoadOwnedPokemon(Map<String,Object> results, String methodName, Id pokemonId){
        Pokemon__c pokemon = pokemonGameHelper.FetchPokemon(pokemonId);
        if(pokemon == null){
            Fail(results, methodName, 'Pokemon not found');
            return null;
        }
        if(!pokemonGameHelper.OwnedByCurrentUser(pokemon)){
            Reject(results, 'You do not own this Pokemon');
            return null;
        }
        return pokemon;
    }

    static Pokemon_Biome__mdt FindBiome(String biomeName){
        // Custom Metadata SOQL does not support OR (disjunctions) — query by DeveloperName, then fall back to Label.
        List<Pokemon_Biome__mdt> biomes = [
            SELECT DeveloperName, Label, Active__c, Grass_Patch_Count__c, Background_Image_Url__c, Encounters_Json__c
            FROM Pokemon_Biome__mdt WHERE DeveloperName = :biomeName LIMIT 1
        ];
        if(biomes.isEmpty()){
            biomes = [
                SELECT DeveloperName, Label, Active__c, Grass_Patch_Count__c, Background_Image_Url__c, Encounters_Json__c
                FROM Pokemon_Biome__mdt WHERE Label = :biomeName LIMIT 1
            ];
        }
        return biomes.isEmpty() ? null : biomes[0];
    }

    static Integer ResolvePatchCount(Map<String,Object> params, Pokemon_Biome__mdt biome, Integer available){
        Integer biomeMax = biome.Grass_Patch_Count__c == null ? 1 : biome.Grass_Patch_Count__c.intValue();
        Integer ceiling = Math.min(biomeMax, available);

        if(!params.containsKey('patchCount') || params.get('patchCount') == null) return ceiling;

        Integer patchCount = pokemonGameHelper.ToInteger(params.get('patchCount'));
        return Math.min(Math.max(patchCount, 1), ceiling);
    }

    static Decimal CurrentTrainerHighestLevel(){
        List<Pokemon_Trainer__c> ownedTrainers = [
            SELECT Id, Highest_Level__c FROM Pokemon_Trainer__c WHERE OwnerId = :UserInfo.getUserId() LIMIT 1
        ];
        return ownedTrainers.isEmpty() ? null : ownedTrainers[0].Highest_Level__c;
    }

    static Map<String,Object> BuildPatch(Map<String,Object> encounter, Integer anchor, Pokemon_Settings__mdt config){
        Integer pokedexNumber = pokemonGameHelper.ToInteger(encounter.get('dex'));
        String tier = String.valueOf(encounter.get('tier'));
        Map<String,Integer> band = pokemonGameHelper.LevelBandForTier(tier, anchor, config);

        // Even inside a legal band, an evolved/legendary species never spawns below its minimum wild level.
        Integer floorLevel = pokemonGameHelper.MinWildLevel(pokedexNumber);
        if(floorLevel > band.get('min')){
            band = new Map<String,Integer>{ 'min' => Math.min(floorLevel, band.get('max')), 'max' => band.get('max') };
        }

        Integer level = pokemonGameHelper.RandomLevelInBand(band);
        Boolean isShiny = pokemonCatchLogic.RollShiny(pokemonGameHelper.ShinyRate(config));

        // The browser only learns "shiny or not" (for the golden tile glow) plus an encrypted token holding
        // everything else — species, level, and the shiny outcome cannot be inspected or edited before the click.
        return new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(pokedexNumber, level, isShiny),
            'isShiny' => isShiny
        };
    }

    static Boolean IncludePokemon(Map<String,Object> params){
        if(!params.containsKey('includePokemon') || params.get('includePokemon') == null) return true;
        return (Boolean)params.get('includePokemon');
    }

    static Map<String,Object> Fail(Map<String,Object> results, String methodName, String reason){
        results.put('status', 'error');
        results.put('message', 'ERROR in pokemonGameController.' + methodName + ': ' + reason);
        return results;
    }

    static Map<String,Object> Fail(Map<String,Object> results, String methodName, Exception error){
        return Fail(results, methodName, error.getLineNumber() + ' - ' + error.getMessage());
    }

    static Map<String,Object> Reject(Map<String,Object> results, String message){
        results.put('status', 'error');
        results.put('message', message);
        return results;
    }

    static Map<String,Object> Warn(Map<String,Object> results, String message){
        results.put('status', 'warning');
        results.put('message', message);
        return results;
    }
}