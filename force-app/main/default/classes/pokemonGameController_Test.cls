/* Title: pokemonGameController_Test
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Tests pokemonGameController against the deployed CMDT, biome metadata, and pokemonSpeciesSeed Static Resource — onboarding, catch, power-up, mart, trade, release, rename, biome, roster.
 * Test Class: pokemonGameController_Test
 * Modified: Garrett Kent - 06/22/2026 - Updated veteran/fresh biome-level bounds for lowered wild-encounter level offsets
 * Modified: Garrett Kent - 06/22/2026 - Added Shiny/Dusk/Dawn evolution stones
 * Modified: Garrett Kent - 07/05/2026 - Encounter tokens: catches mint/decode encrypted tokens, RevealEncounter coverage, minimum-wild-level floors, anti-inspect patch payload
 * Modified: Garrett Kent - 07/21/2026 - SetRival coverage (set/clear/ineligible/no-trainer) and Can_Evolve for stone + friendship evolvers
 * Modified: Garrett Kent - 07/22/2026 - Mart-only balls: starter grant is 10, milestone grant disabled, ball-guard wiring coverage (opt-in enforcement)
 */
@isTest
private class pokemonGameController_Test {

    static User BuildTestUser(String aliasSeed){
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = aliasSeed + DateTime.now().getTime();
        User testUser = new User(
            FirstName = 'Poke',
            LastName = aliasSeed,
            Alias = aliasSeed.left(8),
            Email = unique + '@example.com',
            Username = unique + '@pokemon.test',
            ProfileId = standardProfile.Id,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Chicago'
        );
        return testUser;
    }

    static Pokemon_Trainer__c CreateTrainerAsCurrentUser(String trainerName, Integer starterDex){
        Map<String,Object> params = new Map<String,Object>{
            'trainerName' => trainerName,
            'starterPokedexId' => starterDex
        };
        Map<String,Object> results = pokemonGameController.CreateTrainer(params);
        System.assertEquals('success', results.get('status'), 'CreateTrainer should succeed: ' + results.get('message'));
        return (Pokemon_Trainer__c)results.get('trainer');
    }

    static Id CreateTrainerForOtherUser(String trainerName){
        User otherUser = BuildTestUser('rival');
        // A trainer is only eligible as a rival if its owner holds Pokemon_Full_Access, so grant it before the trainer exists.
        PermissionSet fullAccess = [SELECT Id FROM PermissionSet WHERE Name = 'Pokemon_Full_Access' LIMIT 1];
        // Setup-object DML stays inside its own runAs block so later trainer DML in the test doesn't hit MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())){
            INSERT otherUser;
            INSERT new PermissionSetAssignment(AssigneeId = otherUser.Id, PermissionSetId = fullAccess.Id);
        }
        Id trainerId;
        System.runAs(otherUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser(trainerName, 1);
            trainerId = trainer.Id;
        }
        return trainerId;
    }

    @isTest static void testCreateTrainerSuccess(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => 25
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'CreateTrainer should succeed');
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(500, trainer.Currency__c, 'Starting currency should be 500');
        System.assertEquals(10, trainer.Poke_Balls__c, 'Starting Poke Balls should be 10');
        System.assertEquals('Ash', trainer.Name, 'Trainer name should be set');

        Pokemon__c starter = (Pokemon__c)results.get('starter');
        System.assertNotEquals(null, starter, 'A starter Pokemon should be returned');
        System.assertEquals(25, starter.Pokedex_Number__c, 'Starter dex should be 25');

        Integer rosterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];
        System.assertEquals(1, rosterCount, 'Trainer should own exactly one starter');
    }

    @isTest static void testCreateTrainerDuplicate(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash Again',
            'starterPokedexId' => 4
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'Second create should warn');
        System.assertNotEquals(null, results.get('trainer'), 'Existing trainer should be returned');
    }

    @isTest static void testCreateTrainerInvalidStarter(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => 99
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Disallowed starter should error');
    }

    @isTest static void testCreateTrainerWithRival(){
        Id rivalTrainerId = CreateTrainerForOtherUser('Gary');

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => 7,
            'rivalName' => rivalTrainerId
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'CreateTrainer with rival should succeed');
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(rivalTrainerId, trainer.Rival__c, 'Rival should be wired to the other trainer');
    }

    @isTest static void testGetMyTrainerNoTrainer(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetMyTrainer(new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'GetMyTrainer should succeed with no trainer');
        System.assertEquals(null, results.get('trainer'), 'Trainer should be null when none exists');
        System.assertNotEquals(null, results.get('currentUserName'), 'Current user name should be populated');
    }

    @isTest static void testGetMyTrainerWithRoster(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetMyTrainer(new Map<String,Object>{ 'includePokemon' => true });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'GetMyTrainer should succeed');
        System.assertNotEquals(null, results.get('trainer'), 'Trainer should be returned');
        List<Pokemon__c> roster = (List<Pokemon__c>)results.get('pokemon');
        System.assertEquals(1, roster.size(), 'Roster should contain the starter');
    }

    @isTest static void testGetTrainerById(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetTrainer(new Map<String,Object>{ 'trainerId' => trainer.Id });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'GetTrainer should succeed');
        Pokemon_Trainer__c fetched = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(trainer.Id, fetched.Id, 'Returned trainer should match the requested Id');
    }

    @isTest static void testGetTrainerMissingId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetTrainer(new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'GetTrainer without an Id should error');
    }

    @isTest static void testCatchWithMasterBall(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchAttempt(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Master ball catch should succeed');
        System.assertEquals(true, results.get('caught'), 'Master ball always catches');
        System.assertNotEquals(null, results.get('pokemon'), 'A caught Pokemon should be returned');

        Map<String,Object> ballCounts = (Map<String,Object>)results.get('ballCounts');
        System.assertEquals(0, (Decimal)ballCounts.get('masterball'), 'Master ball count should be decremented to 0');
    }

    @isTest static void testCatchBrokeFreeKeepsThePokemon(){
        CreateTrainerAsCurrentUser('Ash', 1);
        pokemonGameController.catchOverride = false;
        pokemonGameController.fleeChanceOverride = 0;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'pokeball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'A broke-free throw is still a successful call');
        System.assertEquals(false, results.get('caught'), 'The throw missed, so nothing is caught');
        System.assertEquals(false, results.get('fled'), 'With a 0% flee chance the Pokemon breaks free but stays');
        System.assertEquals(null, results.get('pokemon'), 'No Pokemon is created on a miss');
        Map<String,Object> ballCounts = (Map<String,Object>)results.get('ballCounts');
        System.assertEquals(9, (Decimal)ballCounts.get('pokeball'), 'A thrown Poke Ball is consumed even when the catch fails (10 -> 9)');
    }

    @isTest static void testCatchFleeEndsTheEncounter(){
        CreateTrainerAsCurrentUser('Ash', 1);
        pokemonGameController.catchOverride = false;
        pokemonGameController.fleeChanceOverride = 100;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'pokeball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'A flee is still a successful call');
        System.assertEquals(false, results.get('caught'), 'A fled Pokemon is not caught');
        System.assertEquals(true, results.get('fled'), 'With a 100% flee chance the Pokemon flees');
        System.assertEquals(null, results.get('pokemon'), 'No Pokemon is created when it flees');
        Map<String,Object> ballCounts = (Map<String,Object>)results.get('ballCounts');
        System.assertEquals(9, (Decimal)ballCounts.get('pokeball'), 'The thrown ball is still consumed on a flee (10 -> 9)');
    }

    @isTest static void testCatchSuccessNeverFlees(){
        CreateTrainerAsCurrentUser('Ash', 1);
        pokemonGameController.catchOverride = true;
        pokemonGameController.fleeChanceOverride = 100;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'pokeball'
        });
        Test.stopTest();

        System.assertEquals(true, results.get('caught'), 'A forced catch should succeed');
        System.assertEquals(false, results.get('fled'), 'A caught Pokemon never flees, even at a 100% flee chance');
        System.assertNotEquals(null, results.get('pokemon'), 'A caught Pokemon is returned');
    }

    @isTest static void testCatchNoBall(){
        CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'No master ball should warn');
        System.assertNotEquals(null, results.get('ballCounts'), 'Ball counts should still be returned');
    }

    @isTest static void testCatchInvalidBall(){
        CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'rockball'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Invalid ball type should error');
    }

    @isTest static void testCatchMasterBallMilestoneDisabled(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);

        // Starter is dex 1 — add 8 more distinct species to reach 9 distinct on the roster.
        List<Pokemon__c> filler = new List<Pokemon__c>();
        List<Integer> fillerDexes = new List<Integer>{ 4, 7, 10, 13, 16, 19, 25, 43 };
        for(Integer dex : fillerDexes){
            filler.add(new Pokemon__c(
                Pokemon_Trainer__c = trainer.Id,
                Pokedex_Number__c = dex,
                Name = 'Filler' + dex,
                Species_Name__c = 'Filler' + dex,
                Level__c = 5,
                EXP_Points__c = 100,
                Type__c = 'normal'
            ));
        }
        INSERT filler;

        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        // Catch a 10th NEW species (dex 63 Abra) via master ball — crosses what used to be the 10-species milestone.
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(63, 5, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Milestone catch should succeed');
        System.assertEquals(true, results.get('caught'), 'Master ball should catch the 10th species');
        System.assertEquals(null, results.get('masterBallsGranted'), 'The milestone grant is disabled — no master balls are granted');

        Pokemon_Trainer__c refreshed = [SELECT Master_Balls__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
        // Started with 1, spent 1 to catch, nothing granted back — Master Balls are unobtainable.
        System.assertEquals(0, refreshed.Master_Balls__c, 'Master ball balance reflects the spend with no milestone grant');
    }

    // ---- Trainer ball guard wiring (mart-only balls) ----

    @isTest static void testBallGuardAllowsGameGrants(){
        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        try{
            Test.startTest();
            Map<String,Object> createResults = pokemonGameController.CreateTrainer(new Map<String,Object>{
                'trainerName' => 'Ash',
                'starterPokedexId' => 25
            });
            Map<String,Object> purchaseResults = pokemonGameController.PurchaseItems(new Map<String,Object>{
                'cart' => new Map<String,Object>{ 'pokeball' => 2 }
            });
            Test.stopTest();

            System.assertEquals('success', createResults.get('status'), 'CreateTrainer should succeed with the ball guard enforced');
            Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)createResults.get('trainer');
            System.assertEquals(10, trainer.Poke_Balls__c, 'The starter grant passes the guard because CreateTrainer flags its insert as game DML');
            System.assertEquals(0, trainer.Master_Balls__c, 'Master Balls are zero on insert');

            System.assertEquals('success', purchaseResults.get('status'), 'Purchase should succeed with the ball guard enforced');
            Pokemon_Trainer__c updated = (Pokemon_Trainer__c)purchaseResults.get('trainer');
            System.assertEquals(12, updated.Poke_Balls__c, 'The purchase passes the guard because PurchaseItems flags its update as game DML');
        }
        finally{
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }
    }

    @isTest static void testBallGuardAllowsThrowDecrement(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        try{
            Test.startTest();
            Map<String,Object> results = pokemonGameController.CatchAttempt(new Map<String,Object>{
                'token' => pokemonGameHelper.EncounterToken(4, 5, false),
                'ballType' => 'masterball'
            });
            Test.stopTest();

            System.assertEquals('success', results.get('status'), 'Catch should succeed with the ball guard enforced');
            System.assertEquals(true, results.get('caught'), 'Master ball always catches');
            Map<String,Object> ballCounts = (Map<String,Object>)results.get('ballCounts');
            System.assertEquals(0, (Decimal)ballCounts.get('masterball'), 'The throw decrement passes the guard — spending is allowed, gaining is not');
        }
        finally{
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }
    }

    @isTest static void testPowerUpSuccess(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);
        trainer.Experience_Tokens__c = 100000;
        UPDATE trainer;

        Pokemon__c starter = [SELECT Id, Level__c FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        Decimal startingLevel = starter.Level__c;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'tokensToSpend' => 50000
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Power up should succeed');
        Pokemon__c leveled = (Pokemon__c)results.get('pokemon');
        System.assert(leveled.Level__c > startingLevel, 'Level should rise after spending tokens');

        Pokemon_Trainer__c refreshed = [SELECT Experience_Tokens__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
        System.assertEquals(50000, refreshed.Experience_Tokens__c, 'Tokens should be debited by the spent amount');
    }

    @isTest static void testPowerUpNotEnoughTokens(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'tokensToSpend' => 999999
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'Spending more than held should warn');
    }

    @isTest static void testPowerUpOverflowRefund(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        // Pikachu is medium growth (n^3). Max cumulative EXP at L100 = 1,000,000.
        trainer.Experience_Tokens__c = 5000000;
        UPDATE trainer;

        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        // Push it to near max first so the second spend overflows.
        starter.EXP_Points__c = 999000;
        starter.Level__c = 99;
        UPDATE starter;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'tokensToSpend' => 4000000
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Power up near max should succeed');
        Long tokensSpent = (Long)results.get('tokensSpent');
        System.assertEquals(1000, tokensSpent, 'Spend should be capped to the room remaining to L100 (1,000,000 - 999,000)');

        Pokemon_Trainer__c refreshed = [SELECT Experience_Tokens__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
        System.assertEquals(4999000, refreshed.Experience_Tokens__c, 'Only the capped amount should be debited; overflow refunded');

        Pokemon__c leveled = (Pokemon__c)results.get('pokemon');
        System.assertEquals(100, leveled.Level__c, 'Pokemon should reach L100');
    }

    @isTest static void testPurchaseItemsSuccess(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'pokeball' => 2 }
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Purchase should succeed');
        Pokemon_Trainer__c updated = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(12, updated.Poke_Balls__c, 'Two Poke Balls should be added to the starting 10');
        System.assertEquals(100, updated.Currency__c, 'Currency should be debited by 400 (2 x 200)');
    }

    @isTest static void testPurchaseItemsCartFromLwcMarshalling(){
        // The LWC marshals the cart as Map<Object,Object>; this guards the JSON round-trip in NormalizeCart against an invalid-conversion error.
        CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<Object,Object>{ 'pokeball' => 1 }
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Cart marshalled as Map<Object,Object> should purchase: ' + results.get('message'));
        Pokemon_Trainer__c updated = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(11, updated.Poke_Balls__c, 'One Poke Ball should be added to the starting 10');
    }

    @isTest static void testPurchaseItemsInsufficientCurrency(){
        CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.BuyItem(new Map<String,Object>{
            'itemType' => 'ultraball',
            'quantity' => 100
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'Not enough currency should warn');
    }

    @isTest static void testPurchaseMasterBallRejected(){
        CreateTrainerAsCurrentUser('Ash', 1);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'masterball' => 1 }
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Master ball cannot be purchased');
        System.assertEquals('Item not purchasable', results.get('message'), 'Message should flag the unpurchasable item');
    }

    @isTest static void testTradeAndLatch(){
        Id targetTrainerId = CreateTrainerForOtherUser('Gary');
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        // Give the trainer a second Pokemon so trading the starter away does not hit the last-Pokemon guard.
        InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 5, false, false, 'Charmander');
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 25 LIMIT 1];

        Test.startTest();
        Map<String,Object> tradeResults = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'targetTrainerId' => targetTrainerId
        });
        Test.stopTest();

        System.assertEquals('success', tradeResults.get('status'), 'Trade should succeed');
        Pokemon__c traded = (Pokemon__c)tradeResults.get('pokemon');
        System.assertEquals(true, traded.Is_Traded__c, 'Traded latch should be set');
        System.assertEquals(targetTrainerId, traded.Pokemon_Trainer__c, 'Pokemon should be reparented to the target trainer');

        // Original owner no longer owns it; rename should fail ownership before the latch matters.
        Map<String,Object> renameResults = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'nickname' => 'Sparky'
        });
        System.assertEquals('error', renameResults.get('status'), 'Former owner cannot rename a traded-away Pokemon');
    }

    @isTest static void testTradedLatchBlocksRename(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        starter.Is_Traded__c = true;
        UPDATE starter;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'nickname' => 'Sparky'
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'A traded Pokemon cannot be renamed');
    }

    @isTest static void testReleaseSuccess(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        // Give the trainer a second Pokemon so releasing the starter does not hit the last-Pokemon guard.
        InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 5, false, false, 'Charmander');
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 25 LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>{ 'pokemonId' => starter.Id });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Release should succeed');
        System.assertEquals(trainer.Id, (Id)results.get('trainerId'), 'Parent trainer Id should be returned');
        Integer remaining = [SELECT COUNT() FROM Pokemon__c WHERE Id = :starter.Id];
        System.assertEquals(0, remaining, 'Released Pokemon should be deleted');
    }

    @isTest static void testRenameSuccess(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'nickname' => 'Sparky'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Rename should succeed');
        Pokemon__c renamed = (Pokemon__c)results.get('pokemon');
        System.assertEquals('Sparky', renamed.Nickname__c, 'Nickname should be updated');
    }

    @isTest static void testRenameTooLongWarns(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'nickname' => 'ThirteenChars'
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'A 13-character nickname should warn');
        Pokemon__c unchanged = [SELECT Nickname__c FROM Pokemon__c WHERE Id = :starter.Id];
        System.assertEquals(null, unchanged.Nickname__c, 'Nickname should not be saved when over the 12-character cap');
    }

    @isTest static void testGetBiomePokemon(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Verdant_Meadow' });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Biome lookup should succeed');
        List<Map<String,Object>> patches = (List<Map<String,Object>>)results.get('patches');
        System.assert(!patches.isEmpty(), 'Verdant Meadow should return at least one patch');
        Map<String,Object> firstPatch = patches[0];
        System.assertNotEquals(null, firstPatch.get('token'), 'Each patch should carry an encrypted encounter token');
        System.assertNotEquals(null, firstPatch.get('isShiny'), 'Each patch should carry a shiny flag for the tile glow');

        // The reveal opens the token server-side and returns the display payload.
        Map<String,Object> reveal = pokemonGameController.RevealEncounter(new Map<String,Object>{ 'token' => firstPatch.get('token') });
        System.assertEquals('success', reveal.get('status'), 'Reveal should succeed for a freshly minted token: ' + reveal.get('message'));
        System.assertNotEquals(null, reveal.get('name'), 'Reveal should carry the species name');
        System.assertNotEquals(null, reveal.get('image'), 'Reveal should carry the species image');
        System.assertNotEquals(null, reveal.get('level'), 'Reveal should carry the rolled level');
    }

    @isTest static void testGetBiomeNotFound(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Nonexistent_Biome' });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Unknown biome should error');
    }

    @isTest static void testGetOtherTrainers(){
        CreateTrainerForOtherUser('Gary');
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetOtherTrainers(new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'GetOtherTrainers should succeed');
        List<Map<String,Object>> otherTrainers = (List<Map<String,Object>>)results.get('otherTrainers');
        System.assert(!otherTrainers.isEmpty(), 'The other trainer should be returned');
        System.assertNotEquals(null, otherTrainers[0].get('label'), 'Combobox option should have a label');
        System.assertNotEquals(null, otherTrainers[0].get('value'), 'Combobox option should have a value');
    }

    // Builds a trainer owned by a brand-new user who does NOT hold Pokemon_Full_Access, so it is ineligible as a rival.
    // Models a trainer whose owner does NOT currently hold Pokemon_Full_Access — e.g. a player who created a trainer
    // and later lost access. The user must hold the perm set to create/own the record, so we grant it, create the
    // trainer as them, then revoke the assignment. A direct OwnerId transfer to a permission-less user fails with
    // TRANSFER_REQUIRES_READ, so this is the realistic path.
    static Id CreateTrainerForNonPermissionedUser(String trainerName){
        User plainUser = BuildTestUser('noperm');
        PermissionSet fullAccess = [SELECT Id FROM PermissionSet WHERE Name = 'Pokemon_Full_Access' LIMIT 1];
        PermissionSetAssignment assignment;
        System.runAs(new User(Id = UserInfo.getUserId())){
            INSERT plainUser;
            assignment = new PermissionSetAssignment(AssigneeId = plainUser.Id, PermissionSetId = fullAccess.Id);
            INSERT assignment;
        }
        Id trainerId;
        System.runAs(plainUser){
            trainerId = CreateTrainerAsCurrentUser(trainerName, 1).Id;
        }
        // Revoke the perm set so this owner is no longer rival-eligible.
        System.runAs(new User(Id = UserInfo.getUserId())){
            DELETE assignment;
        }
        return trainerId;
    }

    @isTest static void testGetOtherTrainersExcludesNonPermissioned(){
        Id nonPermissionedTrainerId = CreateTrainerForNonPermissionedUser('Silph Grunt');
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetOtherTrainers(new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'GetOtherTrainers should succeed');
        List<Map<String,Object>> otherTrainers = (List<Map<String,Object>>)results.get('otherTrainers');
        Set<String> returnedTrainerIds = new Set<String>();
        for(Map<String,Object> option : otherTrainers){
            returnedTrainerIds.add(String.valueOf(option.get('value')));
        }
        System.assert(!returnedTrainerIds.contains(String.valueOf(nonPermissionedTrainerId)), 'A trainer whose owner lacks Pokemon_Full_Access must be excluded from the rival list');
    }

    @isTest static void testCreateTrainerRivalNonPermissionedIgnored(){
        Id nonPermissionedTrainerId = CreateTrainerForNonPermissionedUser('Silph Grunt');

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => 25,
            'rivalName' => nonPermissionedTrainerId
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'CreateTrainer should still succeed when the rival is ineligible: ' + results.get('message'));
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(null, trainer.Rival__c, 'A rival whose owner lacks Pokemon_Full_Access must be rejected on save');
    }

    @isTest static void testSetRivalSuccess(){
        Id rivalTrainerId = CreateTrainerForOtherUser('Gary');
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.SetRival(new Map<String,Object>{ 'rivalTrainerId' => rivalTrainerId });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'SetRival should succeed: ' + results.get('message'));
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(rivalTrainerId, trainer.Rival__c, 'Rival should be wired to the chosen trainer');
    }

    @isTest static void testSetRivalClearsWithBlank(){
        Id rivalTrainerId = CreateTrainerForOtherUser('Gary');
        CreateTrainerAsCurrentUser('Ash', 25);
        pokemonGameController.SetRival(new Map<String,Object>{ 'rivalTrainerId' => rivalTrainerId });

        Test.startTest();
        Map<String,Object> results = pokemonGameController.SetRival(new Map<String,Object>{ 'rivalTrainerId' => '' });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Clearing the rival should succeed');
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(null, trainer.Rival__c, 'Selecting N/A (blank) should clear the rival');
    }

    @isTest static void testSetRivalIneligibleRejected(){
        Id nonPermissionedTrainerId = CreateTrainerForNonPermissionedUser('Silph Grunt');
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.SetRival(new Map<String,Object>{ 'rivalTrainerId' => nonPermissionedTrainerId });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'SetRival should still succeed even when the pick is ineligible');
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(null, trainer.Rival__c, 'A rival whose owner lacks Pokemon_Full_Access must be rejected');
    }

    @isTest static void testSetRivalNoTrainerRejected(){
        Id rivalTrainerId = CreateTrainerForOtherUser('Gary');

        Test.startTest();
        Map<String,Object> results = pokemonGameController.SetRival(new Map<String,Object>{ 'rivalTrainerId' => rivalTrainerId });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'SetRival should reject when the current user has no trainer');
    }

    @isTest static void testCanEvolveStoneAndFriendship(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Pokemon__c stoneEvolver = pokemonGameHelper.BuildPokemon(pokemonGameHelper.Species(25), 25, 20, false, trainer.Id);      // Pikachu — thunder stone
        Pokemon__c friendshipEvolver = pokemonGameHelper.BuildPokemon(pokemonGameHelper.Species(42), 42, 30, false, trainer.Id); // Golbat — friendship
        Pokemon__c levelEvolver = pokemonGameHelper.BuildPokemon(pokemonGameHelper.Species(1), 1, 10, false, trainer.Id);        // Bulbasaur — level-up
        Pokemon__c nonEvolver = pokemonGameHelper.BuildPokemon(pokemonGameHelper.Species(132), 132, 10, false, trainer.Id);      // Ditto — never evolves
        Test.stopTest();

        System.assertEquals(true, stoneEvolver.Can_Evolve__c, 'A stone evolver (Pikachu) should be flagged Can Evolve');
        System.assertEquals(true, friendshipEvolver.Can_Evolve__c, 'A friendship evolver (Golbat) should be flagged Can Evolve');
        System.assertEquals(true, levelEvolver.Can_Evolve__c, 'A level-up evolver (Bulbasaur) should be flagged Can Evolve');
        System.assertEquals(false, nonEvolver.Can_Evolve__c, 'A non-evolving species (Ditto) should not be flagged');
    }

    @isTest static void testIsMineScopedToOwner(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Pokemon_Trainer__c myTrainer = CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Pokemon__c minePoke = [SELECT Is_Mine__c FROM Pokemon__c WHERE Pokemon_Trainer__c = :myTrainer.Id LIMIT 1];
        Pokemon__c otherPoke = [SELECT Is_Mine__c FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1];
        Test.stopTest();

        System.assertEquals(true, minePoke.Is_Mine__c, 'My Pokemon should be flagged Is Mine for me — the My Pokemon list view relies on this');
        System.assertEquals(false, otherPoke.Is_Mine__c, 'Another user\'s Pokemon must NOT be flagged Is Mine for me');
    }

    @isTest static void testReleaseLastPokemonBlocked(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>{ 'pokemonId' => starter.Id });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'Releasing the last Pokemon should warn, not delete');
        System.assert(String.valueOf(results.get('message')).contains('last Pokemon'), 'Message should flag the last-Pokemon guard: ' + results.get('message'));
        Integer rosterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];
        System.assertEquals(1, rosterCount, 'The last Pokemon should still be on the roster');
    }

    @isTest static void testTradeLastPokemonBlocked(){
        Id targetTrainerId = CreateTrainerForOtherUser('Gary');
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'targetTrainerId' => targetTrainerId
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'Trading away the last Pokemon should warn, not reassign');
        System.assert(String.valueOf(results.get('message')).contains('last Pokemon'), 'Message should flag the last-Pokemon guard: ' + results.get('message'));
        Integer sourceRosterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];
        System.assertEquals(1, sourceRosterCount, 'The last Pokemon should still belong to the source trainer');
    }

    @isTest static void testTradeToNonPermissionedTargetRejected(){
        Id nonPermissionedTrainerId = CreateTrainerForNonPermissionedUser('Silph Grunt');
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        // Give the trainer a second Pokemon so the trade clears the last-Pokemon guard and reaches the target check.
        InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 5, false, false, 'Charmander');
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 25 LIMIT 1];

        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'targetTrainerId' => nonPermissionedTrainerId
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A trade to a non-permissioned owner must be rejected');
        Pokemon__c unchanged = [SELECT Pokemon_Trainer__c FROM Pokemon__c WHERE Id = :starter.Id LIMIT 1];
        System.assertEquals(trainer.Id, unchanged.Pokemon_Trainer__c, 'The Pokemon must stay with the source trainer when the target is ineligible');
    }

    static Id FakePokemonId(){
        return ((String)Pokemon__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000001';
    }

    static Id FakeTrainerId(){
        return ((String)Pokemon_Trainer__c.SObjectType.getDescribe().getKeyPrefix()) + '000000000001';
    }

    @isTest static void testCreateTrainerMissingStarter(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{ 'trainerName' => 'Ash' });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing starter id should error');
    }

    @isTest static void testCreateTrainerBadRivalIgnored(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => 25,
            'rivalName' => 'not-an-id'
        });
        Test.stopTest();
        System.assertEquals('success', results.get('status'), 'A non-Id rival value is ignored, not fatal');
        Pokemon_Trainer__c trainer = (Pokemon_Trainer__c)results.get('trainer');
        System.assertEquals(null, trainer.Rival__c, 'Bad rival value leaves Rival__c blank');
    }

    @isTest static void testGetTrainerBadId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetTrainer(new Map<String,Object>{ 'trainerId' => 'not-an-id' });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'A malformed trainer Id should error');
    }

    @isTest static void testCatchMissingToken(){
        CreateTrainerAsCurrentUser('Ash', 1);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'ballType' => 'pokeball' });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing encounter token should error');
    }

    @isTest static void testCatchSpeciesNotFound(){
        CreateTrainerAsCurrentUser('Ash', 1);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(99999, 5, false),
            'ballType' => 'pokeball'
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'An unknown species should error');
    }

    @isTest static void testCatchNoTrainer(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'pokeball'
        });
        Test.stopTest();
        System.assertNotEquals('success', results.get('status'), 'Catching with no trainer should not succeed');
    }

    @isTest static void testPowerUpMissingPokemonId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{ 'tokensToSpend' => 10 });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing pokemon id should error');
    }

    @isTest static void testPowerUpMissingTokens(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{ 'pokemonId' => starter.Id });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing tokens to spend should error');
    }

    @isTest static void testPowerUpPokemonNotFound(){
        CreateTrainerAsCurrentUser('Ash', 25);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => FakePokemonId(),
            'tokensToSpend' => 10
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'A non-existent Pokemon should error');
    }

    @isTest static void testPowerUpNotOwned(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Id othersPokemonId = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1].Id;
        CreateTrainerAsCurrentUser('Ash', 25);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => othersPokemonId,
            'tokensToSpend' => 10
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Powering up a Pokemon you do not own should error');
    }

    @isTest static void testPowerUpAlreadyMax(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Experience_Tokens__c = 100;
        UPDATE trainer;
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        starter.EXP_Points__c = 1000000;
        starter.Level__c = 100;
        UPDATE starter;
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'tokensToSpend' => 50
        });
        Test.stopTest();
        System.assertEquals('warning', results.get('status'), 'A maxed Pokemon cannot be powered up further');
    }

    @isTest static void testPurchaseEmptyCart(){
        CreateTrainerAsCurrentUser('Ash', 1);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>());
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'An empty cart should error');
    }

    @isTest static void testPurchaseNoTrainer(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'pokeball' => 1 }
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Purchasing with no trainer should error');
    }

    @isTest static void testTradeMissingPokemonId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{ 'targetTrainerId' => FakeTrainerId() });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing pokemon id should error');
    }

    @isTest static void testTradeMissingTarget(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{ 'pokemonId' => starter.Id });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing target trainer should error');
    }

    @isTest static void testTradePokemonNotFound(){
        CreateTrainerAsCurrentUser('Ash', 25);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => FakePokemonId(),
            'targetTrainerId' => FakeTrainerId()
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Trading a non-existent Pokemon should error');
    }

    @isTest static void testTradeNotOwned(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Id othersPokemonId = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1].Id;
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => othersPokemonId,
            'targetTrainerId' => trainer.Id
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Trading a Pokemon you do not own should error');
    }

    @isTest static void testTradeAlreadyBelongs(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id LIMIT 1];
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'targetTrainerId' => trainer.Id
        });
        Test.stopTest();
        System.assertEquals('warning', results.get('status'), 'Trading to the current owner should warn');
    }

    @isTest static void testTradeTargetNotFound(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        // A second Pokemon clears the last-Pokemon guard so the missing-target error path is reached.
        InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 5, false, false, 'Charmander');
        Pokemon__c starter = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 25 LIMIT 1];
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => starter.Id,
            'targetTrainerId' => FakeTrainerId()
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'A non-existent target trainer should error');
    }

    @isTest static void testReleaseMissingId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>());
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing pokemon id should error');
    }

    @isTest static void testReleaseNotFound(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>{ 'pokemonId' => FakePokemonId() });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Releasing a non-existent Pokemon should error');
    }

    @isTest static void testReleaseNotOwned(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Id othersPokemonId = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1].Id;
        CreateTrainerAsCurrentUser('Ash', 25);
        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>{ 'pokemonId' => othersPokemonId });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Releasing a Pokemon you do not own should error');
    }

    @isTest static void testRenameMissingId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{ 'nickname' => 'Sparky' });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing pokemon id should error');
    }

    @isTest static void testRenameNotFound(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => FakePokemonId(),
            'nickname' => 'Sparky'
        });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Renaming a non-existent Pokemon should error');
    }

    @isTest static void testGetBiomeMissingParam(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>());
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing biome should error');
    }

    @isTest static void testGetBiomeByLabel(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{
            'biome' => 'Verdant Meadow',
            'patchCount' => 2
        });
        Test.stopTest();
        System.assertEquals('success', results.get('status'), 'Biome lookup by Label should succeed');
    }

    // ---- Decimal->Integer param coercion regression (① bugfix) ----

    @isTest static void testNumericParamsArriveAsDecimal(){
        // @AuraEnabled hands numeric JSON in as runtime Decimal — controller must coerce, not hard-cast.
        Test.startTest();
        Map<String,Object> createResults = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => 'Ash',
            'starterPokedexId' => (Object)Decimal.valueOf(25)
        });
        System.assertEquals('success', createResults.get('status'), 'CreateTrainer must coerce a Decimal starter id without an Invalid conversion error');

        Map<String,Object> catchResults = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(25, 5, false),
            'ballType' => 'pokeball'
        });
        System.assertNotEquals('error', catchResults.get('status'), 'CatchPokemon must decode the token payload numbers without an Invalid conversion error: ' + catchResults.get('message'));

        Map<String,Object> biomeResults = pokemonGameController.GetBiomePokemon(new Map<String,Object>{
            'biome' => 'Verdant_Meadow',
            'patchCount' => (Object)Decimal.valueOf(3)
        });
        System.assertEquals('success', biomeResults.get('status'), 'GetBiomePokemon must coerce a Decimal patch count without an Invalid conversion error: ' + biomeResults.get('message'));
        Test.stopTest();
    }

    // ---- Evolution (② server-authoritative) ----

    static Pokemon__c InsertPokemonForTrainer(Id trainerId, Integer dex, String speciesName, Integer level, Boolean isShiny, Boolean isTraded, String nickname){
        Pokemon__c pokemon = new Pokemon__c(
            Pokemon_Trainer__c = trainerId,
            Pokedex_Number__c = dex,
            Name = speciesName,
            Species_Name__c = speciesName,
            Nickname__c = nickname,
            Level__c = level,
            EXP_Points__c = 100,
            Type__c = 'fire',
            Is_Shiny__c = isShiny,
            Is_Traded__c = isTraded
        );
        INSERT pokemon;
        return pokemon;
    }

    @isTest static void testEvolveHappyPath(){
        User trainerUser = BuildTestUser('evolver');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c charmander = InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 16, false, false, 'Charmander');
            Integer beforeCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];

            Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => charmander.Id });

            System.assertEquals('success', results.get('status'), 'Charmander at L16 should evolve: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(5, evolved.Pokedex_Number__c, 'Should evolve to dex 5');
            System.assertEquals('Charmeleon', evolved.Species_Name__c, 'Species should become Charmeleon');
            System.assertEquals(58, evolved.HP__c, 'HP should be the evolved base stat');
            System.assertEquals(16, evolved.Level__c, 'Level should carry over unchanged');

            Integer remainingOriginal = [SELECT COUNT() FROM Pokemon__c WHERE Id = :charmander.Id];
            System.assertEquals(0, remainingOriginal, 'The pre-evolution record should be deleted');
            Integer afterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];
            System.assertEquals(beforeCount, afterCount, 'Roster count should be unchanged (replace-and-delete)');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveNotEligible(){
        User trainerUser = BuildTestUser('toolow');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c charmander = InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 10, false, false, 'Charmander');

            Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => charmander.Id });

            System.assertEquals('warning', results.get('status'), 'Charmander below evolveLevel should warn');
            Pokemon__c stillThere = [SELECT Pokedex_Number__c FROM Pokemon__c WHERE Id = :charmander.Id];
            System.assertEquals(4, stillThere.Pokedex_Number__c, 'Species should be unchanged when not eligible');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveNonEvolvingSpecies(){
        User trainerUser = BuildTestUser('pikaonly');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 4);
            Pokemon__c pikachu = InsertPokemonForTrainer(trainer.Id, 25, 'Pikachu', 30, false, false, 'Pikachu');

            Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => pikachu.Id });

            System.assertEquals('warning', results.get('status'), 'A species with no evolveLevel cannot evolve');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveNotOwned(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Id othersPokemonId = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1].Id;
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => othersPokemonId });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Evolving a Pokemon you do not own should error');
    }

    @isTest static void testEvolveCarryOvers(){
        User trainerUser = BuildTestUser('carry');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            // Shiny + traded + a real rename, set in the same insert so any trade latch is satisfied.
            Pokemon__c charmander = InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 20, true, true, 'Flamey');
            Decimal preEvolutionExp = [SELECT EXP_Points__c FROM Pokemon__c WHERE Id = :charmander.Id].EXP_Points__c;

            Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => charmander.Id });

            System.assertEquals('success', results.get('status'), 'Carry-over evolve should succeed: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(5, evolved.Pokedex_Number__c, 'Should evolve to dex 5');
            System.assertEquals(20, evolved.Level__c, 'Level should carry over');
            System.assertEquals(true, evolved.Is_Shiny__c, 'Shiny flag should carry over');
            System.assertEquals(true, evolved.Is_Traded__c, 'Traded flag should carry over');
            System.assertEquals('Flamey', evolved.Nickname__c, 'A real nickname should carry over');
            System.assertEquals(preEvolutionExp, evolved.EXP_Points__c, 'Exact pre-evolution EXP should carry over');
        }
        Test.stopTest();
    }

    // ---- Stone evolution (B1, server-authoritative) ----

    @isTest static void testEvolveWithStoneHappyPath(){
        User trainerUser = BuildTestUser('stoner');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c vulpix = InsertPokemonForTrainer(trainer.Id, 37, 'Vulpix', 20, false, false, 'Vulpix');
            trainer.Fire_Stones__c = 1;
            UPDATE trainer;
            Integer beforeCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => vulpix.Id,
                'stone' => 'firestone'
            });

            System.assertEquals('success', results.get('status'), 'Vulpix should evolve with a Fire Stone: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(38, evolved.Pokedex_Number__c, 'Should evolve to dex 38');
            System.assertEquals('Ninetales', evolved.Species_Name__c, 'Species should become Ninetales');

            Integer remainingOriginal = [SELECT COUNT() FROM Pokemon__c WHERE Id = :vulpix.Id];
            System.assertEquals(0, remainingOriginal, 'The pre-evolution record should be deleted');
            Integer afterCount = [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id];
            System.assertEquals(beforeCount, afterCount, 'Roster count should be unchanged (replace-and-delete)');

            Pokemon_Trainer__c refreshed = [SELECT Fire_Stones__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
            System.assertEquals(0, refreshed.Fire_Stones__c, 'The Fire Stone should be consumed (1 -> 0)');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithStoneWrongStone(){
        User trainerUser = BuildTestUser('wrongstone');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c vulpix = InsertPokemonForTrainer(trainer.Id, 37, 'Vulpix', 20, false, false, 'Vulpix');
            trainer.Water_Stones__c = 1;
            UPDATE trainer;

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => vulpix.Id,
                'stone' => 'waterstone'
            });

            System.assertEquals('warning', results.get('status'), 'A Water Stone has no effect on Vulpix');
            System.assert(String.valueOf(results.get('message')).contains('no effect'), 'Message should flag that the stone has no effect: ' + results.get('message'));
            Pokemon__c stillThere = [SELECT Pokedex_Number__c FROM Pokemon__c WHERE Id = :vulpix.Id];
            System.assertEquals(37, stillThere.Pokedex_Number__c, 'Species should be unchanged when the stone has no effect');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithStoneNoStoneOwned(){
        User trainerUser = BuildTestUser('nostone');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c eevee = InsertPokemonForTrainer(trainer.Id, 133, 'Eevee', 20, false, false, 'Eevee');

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => eevee.Id,
                'stone' => 'firestone'
            });

            System.assertEquals('warning', results.get('status'), 'Evolving without owning the stone should warn');
            System.assert(String.valueOf(results.get('message')).contains('do not have that stone'), 'Message should flag the missing stone: ' + results.get('message'));
            Pokemon__c stillThere = [SELECT Pokedex_Number__c FROM Pokemon__c WHERE Id = :eevee.Id];
            System.assertEquals(133, stillThere.Pokedex_Number__c, 'Species should be unchanged without the stone');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithStoneNonStoneSpecies(){
        User trainerUser = BuildTestUser('nostonespecies');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c charmander = InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 20, false, false, 'Charmander');
            trainer.Fire_Stones__c = 1;
            UPDATE trainer;

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => charmander.Id,
                'stone' => 'firestone'
            });

            System.assertEquals('warning', results.get('status'), 'A species with no stoneEvolutions cannot evolve with a stone');
            System.assert(String.valueOf(results.get('message')).contains('cannot evolve with a stone'), 'Message should flag the non-stone species: ' + results.get('message'));
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithStoneInvalidStone(){
        User trainerUser = BuildTestUser('badstone');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c vulpix = InsertPokemonForTrainer(trainer.Id, 37, 'Vulpix', 20, false, false, 'Vulpix');

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => vulpix.Id,
                'stone' => 'rockstone'
            });

            System.assertEquals('error', results.get('status'), 'An unrecognized stone should error');
            System.assert(String.valueOf(results.get('message')).contains('Invalid stone'), 'Message should flag the invalid stone: ' + results.get('message'));
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithStoneMissingId(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{ 'stone' => 'firestone' });
        Test.stopTest();
        System.assertEquals('error', results.get('status'), 'Missing pokemon id should error');
    }

    @isTest static void testEvolveWithStoneNotOwned(){
        Id otherTrainerId = CreateTrainerForOtherUser('Gary');
        Id othersPokemonId = [SELECT Id FROM Pokemon__c WHERE Pokemon_Trainer__c = :otherTrainerId LIMIT 1].Id;
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
            'pokemonId' => othersPokemonId,
            'stone' => 'firestone'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Evolving a Pokemon you do not own should error');
    }

    // ---- Stone purchase (B1) ----

    @isTest static void testPurchaseStones(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Currency__c = 6000;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'firestone' => 1 }
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Purchasing a Fire Stone should succeed: ' + results.get('message'));
        Pokemon_Trainer__c refreshed = [SELECT Fire_Stones__c, Currency__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
        System.assertEquals(1, refreshed.Fire_Stones__c, 'One Fire Stone should be added');
        System.assertEquals(1000, refreshed.Currency__c, 'Currency should be debited by the 5000 stone price (6000 -> 1000)');
    }

    @isTest static void testEvolveWithShinyStone(){
        User trainerUser = BuildTestUser('shinystoner');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c togetic = InsertPokemonForTrainer(trainer.Id, 176, 'Togetic', 20, false, false, 'Togetic');
            trainer.Shiny_Stones__c = 1;
            UPDATE trainer;

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => togetic.Id,
                'stone' => 'shinystone'
            });

            System.assertEquals('success', results.get('status'), 'Togetic should evolve with a Shiny Stone: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(468, evolved.Pokedex_Number__c, 'Should evolve to dex 468');
            System.assertEquals('Togekiss', evolved.Species_Name__c, 'Species should become Togekiss');

            Integer remainingOriginal = [SELECT COUNT() FROM Pokemon__c WHERE Id = :togetic.Id];
            System.assertEquals(0, remainingOriginal, 'The pre-evolution record should be deleted');

            Pokemon_Trainer__c refreshed = [SELECT Shiny_Stones__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
            System.assertEquals(0, refreshed.Shiny_Stones__c, 'The Shiny Stone should be consumed (1 -> 0)');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithDuskStone(){
        User trainerUser = BuildTestUser('duskstoner');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c murkrow = InsertPokemonForTrainer(trainer.Id, 198, 'Murkrow', 20, false, false, 'Murkrow');
            trainer.Dusk_Stones__c = 1;
            UPDATE trainer;

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => murkrow.Id,
                'stone' => 'duskstone'
            });

            System.assertEquals('success', results.get('status'), 'Murkrow should evolve with a Dusk Stone: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(430, evolved.Pokedex_Number__c, 'Should evolve to dex 430');
            System.assertEquals('Honchkrow', evolved.Species_Name__c, 'Species should become Honchkrow');

            Integer remainingOriginal = [SELECT COUNT() FROM Pokemon__c WHERE Id = :murkrow.Id];
            System.assertEquals(0, remainingOriginal, 'The pre-evolution record should be deleted');

            Pokemon_Trainer__c refreshed = [SELECT Dusk_Stones__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
            System.assertEquals(0, refreshed.Dusk_Stones__c, 'The Dusk Stone should be consumed (1 -> 0)');
        }
        Test.stopTest();
    }

    @isTest static void testEvolveWithDawnStone(){
        User trainerUser = BuildTestUser('dawnstoner');
        INSERT trainerUser;
        Test.startTest();
        System.runAs(trainerUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
            Pokemon__c kirlia = InsertPokemonForTrainer(trainer.Id, 281, 'Kirlia', 20, false, false, 'Kirlia');
            trainer.Dawn_Stones__c = 1;
            UPDATE trainer;

            Map<String,Object> results = pokemonGameController.EvolveWithStone(new Map<String,Object>{
                'pokemonId' => kirlia.Id,
                'stone' => 'dawnstone'
            });

            System.assertEquals('success', results.get('status'), 'Kirlia should evolve with a Dawn Stone: ' + results.get('message'));
            Pokemon__c evolved = (Pokemon__c)results.get('pokemon');
            System.assertEquals(475, evolved.Pokedex_Number__c, 'Should evolve to dex 475');
            System.assertEquals('Gallade', evolved.Species_Name__c, 'Species should become Gallade');

            Integer remainingOriginal = [SELECT COUNT() FROM Pokemon__c WHERE Id = :kirlia.Id];
            System.assertEquals(0, remainingOriginal, 'The pre-evolution record should be deleted');

            Pokemon_Trainer__c refreshed = [SELECT Dawn_Stones__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
            System.assertEquals(0, refreshed.Dawn_Stones__c, 'The Dawn Stone should be consumed (1 -> 0)');
        }
        Test.stopTest();
    }

    @isTest static void testPurchaseNewStones(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Currency__c = 16000;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'shinystone' => 1, 'duskstone' => 1, 'dawnstone' => 1 }
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Purchasing the new stones should succeed: ' + results.get('message'));
        Pokemon_Trainer__c refreshed = [SELECT Shiny_Stones__c, Dusk_Stones__c, Dawn_Stones__c, Currency__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
        System.assertEquals(1, refreshed.Shiny_Stones__c, 'One Shiny Stone should be added');
        System.assertEquals(1, refreshed.Dusk_Stones__c, 'One Dusk Stone should be added');
        System.assertEquals(1, refreshed.Dawn_Stones__c, 'One Dawn Stone should be added');
        System.assertEquals(1000, refreshed.Currency__c, 'Currency should be debited by three 5000 stone prices (16000 -> 1000)');
    }

    // ---- S5.8 tier classification + weights ----

    @isTest static void testTierForCaptureRateBoundaries(){
        System.assertEquals('common', pokemonGameHelper.TierForCaptureRate(120), 'cr 120 is the common floor');
        System.assertEquals('common', pokemonGameHelper.TierForCaptureRate(255), 'cr 255 is solidly common');
        System.assertEquals('uncommon', pokemonGameHelper.TierForCaptureRate(119), 'cr 119 is just below common');
        System.assertEquals('uncommon', pokemonGameHelper.TierForCaptureRate(45), 'cr 45 is the uncommon floor');
        System.assertEquals('rare', pokemonGameHelper.TierForCaptureRate(44), 'cr 44 is the rare ceiling');
        System.assertEquals('rare', pokemonGameHelper.TierForCaptureRate(3), 'cr 3 is solidly rare');
    }

    @isTest static void testTierWeightsOrdered(){
        Integer commonWeight = pokemonGameHelper.TierWeight('common');
        Integer uncommonWeight = pokemonGameHelper.TierWeight('uncommon');
        Integer rareWeight = pokemonGameHelper.TierWeight('rare');
        System.assertEquals(12, commonWeight, 'Common weight should be 12');
        System.assertEquals(6, uncommonWeight, 'Uncommon weight should be 6');
        System.assertEquals(2, rareWeight, 'Rare weight should be 2');
        System.assert(commonWeight > uncommonWeight && uncommonWeight > rareWeight, 'Weights should descend common > uncommon > rare');
    }

    @isTest static void testFleeChanceForTierDefaults(){
        Pokemon_Settings__mdt config = new Pokemon_Settings__mdt();
        System.assertEquals(10, pokemonGameHelper.FleeChanceForTier('common', config), 'Common flee chance should default to 10');
        System.assertEquals(12.5, pokemonGameHelper.FleeChanceForTier('uncommon', config), 'Uncommon flee chance should default to 12.5');
        System.assertEquals(15, pokemonGameHelper.FleeChanceForTier('rare', config), 'Rare flee chance should default to 15');
    }

    // ---- S5.8 trainer-scaled encounter levels ----

    @isTest static void testBiomeLevelsScaleWithVeteranAnchor(){
        User veteranUser = BuildTestUser('veteran');
        INSERT veteranUser;
        Test.startTest();
        System.runAs(veteranUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Veteran', 25);
            // A high-level Pokemon pushes Highest_Level__c (a roll-up) to 50, lifting the anchor.
            InsertPokemonForTrainer(trainer.Id, 4, 'Charmander', 50, false, false, 'Charmander');

            Pokemon_Trainer__c rolledUp = [SELECT Highest_Level__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id];
            System.assertEquals(50, rolledUp.Highest_Level__c, 'Highest_Level__c should roll up to the veteran Pokemon level');

            Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Verdant_Meadow' });
            System.assertEquals('success', results.get('status'), 'Veteran biome lookup should succeed: ' + results.get('message'));
            List<Map<String,Object>> patches = (List<Map<String,Object>>)results.get('patches');
            System.assert(!patches.isEmpty(), 'Veteran should see at least one patch');
            for(Map<String,Object> patch : patches){
                // The level rides inside the encrypted token — decode it server-side the way CatchPokemon does.
                Map<String,Object> payload = pokemonGameHelper.DecodeEncounterToken(String.valueOf(patch.get('token')));
                Integer patchLevel = pokemonGameHelper.ToInteger(payload.get('level'));
                Integer patchDex = pokemonGameHelper.ToInteger(payload.get('dex'));
                // Wilds now sit a few levels below the anchor: common min offset -8 -> band floor 42, rare max offset -1 -> band ceiling 49.
                System.assert(patchLevel < 50, 'Veteran patch levels should now sit below the highest roster level (50), got ' + patchLevel);
                System.assert(patchLevel >= 42, 'Every veteran patch level should still scale with the anchor (50 + common min offset -8 = 42), got ' + patchLevel);
                System.assert(patchLevel <= 49, 'Every veteran patch level should sit a few levels below the anchor (50 + rare max offset -1 = 49), got ' + patchLevel);
                System.assert(patchLevel >= pokemonGameHelper.MinWildLevel(patchDex), 'A wild Pokemon must never spawn below its minimum wild level, got ' + patchLevel + ' for dex ' + patchDex);
            }
        }
        Test.stopTest();
    }

    @isTest static void testFreshTrainerBiomeLevelsAreLow(){
        User rookieUser = BuildTestUser('rookie');
        INSERT rookieUser;
        Test.startTest();
        System.runAs(rookieUser){
            // Starter-only trainer — Highest_Level__c is the starter level (2..6), so the anchor floor governs.
            CreateTrainerAsCurrentUser('Rookie', 25);

            Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Verdant_Meadow' });
            System.assertEquals('success', results.get('status'), 'Rookie biome lookup should succeed: ' + results.get('message'));
            List<Map<String,Object>> patches = (List<Map<String,Object>>)results.get('patches');
            System.assert(!patches.isEmpty(), 'Rookie should see at least one patch');
            // Starter level tops out at Catch_Level_Max (6); rare offset max is -1 -> band max of starter(<=6) - 1 = 5.
            for(Map<String,Object> patch : patches){
                Map<String,Object> payload = pokemonGameHelper.DecodeEncounterToken(String.valueOf(patch.get('token')));
                Integer patchLevel = pokemonGameHelper.ToInteger(payload.get('level'));
                Integer patchDex = pokemonGameHelper.ToInteger(payload.get('dex'));
                System.assert(patchLevel >= 1, 'Patch level floor is 1, got ' + patchLevel);
                System.assert(patchLevel <= 5, 'Fresh-trainer patch levels should stay low (<= starter max 6 + rare offset -1 = 5), got ' + patchLevel);
                System.assert(patchLevel < 50, 'Fresh-trainer patches should be clearly lower than a veteran anchor of 50, got ' + patchLevel);
                // The Kingdra rule: a rookie's grass never hides an evolved form, powerhouse, or legendary.
                System.assert(pokemonGameHelper.MinWildLevel(patchDex) <= 5, 'A rookie should only meet species whose minimum wild level fits the starter band, got dex ' + patchDex);
            }
        }
        Test.stopTest();
    }

    // ---- Encounter token security (anti-inspect grass) ----

    @isTest static void testCatchLegacyDexParamsRejected(){
        // The old client shape (pokedexNumber/level, no token) must never mint a Pokemon — this was the
        // console-summon hole. Only a server-minted encrypted token opens the catch path now.
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'pokedexNumber' => 150,
            'ballType' => 'masterball',
            'level' => 99
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Legacy dex/level params without a token must error');
        System.assertEquals(0, [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 150], 'No Mewtwo should be minted from raw params');
    }

    @isTest static void testCatchForgedTokenRejected(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => 'bm90LWEtcmVhbC10b2tlbg==',
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A forged token must fail to decode and error');
    }

    @isTest static void testCatchStaleTokenWanders(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        // Mint a token whose issued stamp is two hours old — past the 60-minute freshness window.
        String staleToken = pokemonGameHelper.EncryptEncounterPayload(new Map<String,Object>{
            'dex' => 4,
            'level' => 5,
            'shiny' => false,
            'owner' => UserInfo.getUserId(),
            'issued' => Datetime.now().getTime() - 7200000
        });

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => staleToken,
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('warning', results.get('status'), 'A stale token should warn that the Pokemon wandered off');
        System.assertEquals(0, [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 4], 'No Pokemon should be minted from a stale token');
    }

    @isTest static void testCatchCrossUserTokenRejected(){
        User otherUser = BuildTestUser('tokenthief');
        INSERT otherUser;

        String foreignToken;
        System.runAs(otherUser){
            foreignToken = pokemonGameHelper.EncounterToken(4, 5, false);
        }

        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => foreignToken,
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertNotEquals('success', results.get('status'), 'Another trainer\'s token must be rejected');
    }

    @isTest static void testCatchHonorsTokenLevelExactly(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(10, 4, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Token catch should succeed: ' + results.get('message'));
        Pokemon__c caught = (Pokemon__c)results.get('pokemon');
        System.assertEquals(4, (Integer)caught.Level__c, 'The caught level must be exactly the level rolled into the token');
    }

    @isTest static void testCatchEndToEndFromBiomeToken(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> biomeResults = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Verdant_Meadow' });
        System.assertEquals('success', biomeResults.get('status'), 'Biome lookup should succeed');
        List<Map<String,Object>> patches = (List<Map<String,Object>>)biomeResults.get('patches');
        String token = String.valueOf(patches[0].get('token'));
        Map<String,Object> payload = pokemonGameHelper.DecodeEncounterToken(token);

        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => token,
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'End-to-end token catch should succeed: ' + results.get('message'));
        System.assertEquals(true, results.get('caught'), 'Master ball guarantees the catch');
        Pokemon__c caught = (Pokemon__c)results.get('pokemon');
        System.assertEquals(pokemonGameHelper.ToInteger(payload.get('dex')), (Integer)caught.Pokedex_Number__c, 'The caught species must be the one rolled into the patch token');
        System.assertEquals(pokemonGameHelper.ToInteger(payload.get('level')), (Integer)caught.Level__c, 'The caught level must be the one rolled into the patch token');
    }

    @isTest static void testCatchShinyPredeterminedByToken(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, true),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Shiny token catch should succeed: ' + results.get('message'));
        System.assertEquals(true, results.get('isShiny'), 'The predetermined shiny flag should ride through the catch');
        Pokemon__c caught = (Pokemon__c)results.get('pokemon');
        System.assertEquals(true, caught.Is_Shiny__c, 'The caught Pokemon should be shiny');
        System.assert(caught.Image__c.contains('/shiny/'), 'A shiny catch should use the shiny artwork');
    }

    @isTest static void testRevealEncounterOpensToken(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> reveal = pokemonGameController.RevealEncounter(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(25, 5, true)
        });
        Test.stopTest();

        System.assertEquals('success', reveal.get('status'), 'Reveal should succeed: ' + reveal.get('message'));
        System.assertEquals(25, reveal.get('dex'), 'Reveal should carry the dex');
        System.assertEquals('Pikachu', String.valueOf(reveal.get('name')), 'Reveal should carry the species name');
        System.assertEquals(5, reveal.get('level'), 'Reveal should carry the token level');
        System.assertEquals(true, reveal.get('isShiny'), 'Reveal should carry the predetermined shiny flag');
        System.assert(String.valueOf(reveal.get('image')).contains('/shiny/'), 'A shiny encounter should reveal the shiny artwork');
    }

    @isTest static void testRevealEncounterRejectsBadToken(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> missing = pokemonGameController.RevealEncounter(new Map<String,Object>());
        Map<String,Object> forged = pokemonGameController.RevealEncounter(new Map<String,Object>{ 'token' => 'bm90LWEtcmVhbC10b2tlbg==' });
        Test.stopTest();

        System.assertEquals('error', missing.get('status'), 'Reveal without a token should error');
        System.assertEquals('error', forged.get('status'), 'Reveal with a forged token should error');
    }

    @isTest static void testCatchTokenSingleUseAfterCatch(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 2;
        UPDATE trainer;
        String token = pokemonGameHelper.EncounterToken(4, 5, false);

        Test.startTest();
        Map<String,Object> firstThrow = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'masterball' });
        Map<String,Object> replay = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'masterball' });
        Map<String,Object> reveal = pokemonGameController.RevealEncounter(new Map<String,Object>{ 'token' => token });
        Test.stopTest();

        System.assertEquals('success', firstThrow.get('status'), 'The first throw should succeed: ' + firstThrow.get('message'));
        System.assertEquals(true, firstThrow.get('caught'), 'Master ball guarantees the first catch');
        System.assertEquals('warning', replay.get('status'), 'Replaying a consumed token must warn, not catch again');
        System.assert(String.valueOf(replay.get('message')).contains('already been searched'), 'Replay should explain the patch is spent, got: ' + replay.get('message'));
        System.assertEquals('warning', reveal.get('status'), 'Revealing a consumed token should warn too');
        System.assertEquals(1, [SELECT COUNT() FROM Pokemon__c WHERE Pokemon_Trainer__c = :trainer.Id AND Pokedex_Number__c = 4], 'Only one Pokemon should exist — no replay farming');
        System.assertEquals(1, [SELECT Master_Balls__c FROM Pokemon_Trainer__c WHERE Id = :trainer.Id].Master_Balls__c, 'The refused replay must not consume the second master ball');
    }

    @isTest static void testCatchTokenStaysLiveAfterBrokeFree(){
        CreateTrainerAsCurrentUser('Ash', 25);
        String token = pokemonGameHelper.EncounterToken(4, 5, false);

        Test.startTest();
        pokemonGameController.catchOverride = false;
        pokemonGameController.fleeChanceOverride = 0;
        Map<String,Object> brokeFree = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'pokeball' });

        pokemonGameController.catchOverride = true;
        Map<String,Object> secondThrow = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'pokeball' });
        Test.stopTest();

        System.assertEquals(false, brokeFree.get('caught'), 'The first throw misses');
        System.assertEquals(false, brokeFree.get('fled'), 'With 0% flee the Pokemon breaks free and stays');
        System.assertEquals('success', secondThrow.get('status'), 'A broke-free token must stay throwable: ' + secondThrow.get('message'));
        System.assertEquals(true, secondThrow.get('caught'), 'The second throw at the same patch should catch');
    }

    @isTest static void testCatchTokenConsumedOnFlee(){
        CreateTrainerAsCurrentUser('Ash', 25);
        String token = pokemonGameHelper.EncounterToken(4, 5, false);

        Test.startTest();
        pokemonGameController.catchOverride = false;
        pokemonGameController.fleeChanceOverride = 100;
        Map<String,Object> fledThrow = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'pokeball' });

        pokemonGameController.catchOverride = true;
        Map<String,Object> replay = pokemonGameController.CatchPokemon(new Map<String,Object>{ 'token' => token, 'ballType' => 'pokeball' });
        Test.stopTest();

        System.assertEquals(true, fledThrow.get('fled'), 'The Pokemon flees on the first throw');
        System.assertEquals('warning', replay.get('status'), 'A fled encounter is spent — its token must not be throwable again');
    }

    @isTest static void testMinWildLevelFloors(){
        // Derived from the species seed: chain evolutions, stone stages, stat totals, and legendary flags.
        System.assertEquals(1, pokemonGameHelper.MinWildLevel(10), 'Caterpie is a base bug — floor 1');
        System.assertEquals(36, pokemonGameHelper.MinWildLevel(6), 'Charizard floors at its evolution level (36)');
        System.assert(pokemonGameHelper.MinWildLevel(26) >= 25, 'Raichu (stone evolution) floors at the stone stage');
        System.assert(pokemonGameHelper.MinWildLevel(230) >= 30, 'Kingdra (unlinked trade evolution) is floored by its stat total');
        System.assert(pokemonGameHelper.MinWildLevel(150) >= 45, 'Mewtwo is floored as a legendary');
    }

    // ---- Shiny is predetermined at patch time; a flee still never reports one ----

    @isTest static void testFleeNeverReturnsShiny(){
        CreateTrainerAsCurrentUser('Ash', 25);
        // Force a deterministic flee: the throw misses and the Pokemon always flees — even a shiny token stays hidden.
        pokemonGameController.catchOverride = false;
        pokemonGameController.fleeChanceOverride = 100;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(150, 5, true),
            'ballType' => 'pokeball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Catch attempt should resolve cleanly: ' + results.get('message'));
        System.assertEquals(false, results.get('isShiny'), 'A flee must never report shiny');
        System.assertEquals(null, results.get('pokemon'), 'A flee should not mint a Pokemon');
    }

    @isTest static void testCatchReturnsShinyBoolean(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);
        trainer.Master_Balls__c = 1;
        UPDATE trainer;

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Master ball catch should succeed: ' + results.get('message'));
        System.assertEquals(true, results.get('caught'), 'Master ball always catches');
        System.assertNotEquals(null, results.get('isShiny'), 'A catch should report an isShiny flag');
        System.assert(results.get('isShiny') instanceof Boolean, 'isShiny should be a Boolean');
    }

    // ---- Critical capture flag (A2) ----

    @isTest static void testCriticalCaptureFlag(){
        Pokemon_Trainer__c critTrainer = CreateTrainerAsCurrentUser('Critter', 25);
        critTrainer.Master_Balls__c = 1;
        UPDATE critTrainer;
        pokemonGameController.criticalCaptureOverride = true;

        Test.startTest();
        Map<String,Object> critResults = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(4, 5, false),
            'ballType' => 'masterball'
        });

        System.assertEquals(true, critResults.get('caught'), 'Master ball always catches');
        System.assertEquals(true, critResults.get('criticalCapture'), 'A forced critical capture should report true');

        // Top the master ball back up and force a non-critical catch on the same trainer.
        Pokemon_Trainer__c refreshed = [SELECT Id FROM Pokemon_Trainer__c WHERE Id = :critTrainer.Id];
        refreshed.Master_Balls__c = 1;
        UPDATE refreshed;
        pokemonGameController.criticalCaptureOverride = false;

        Map<String,Object> normalResults = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => pokemonGameHelper.EncounterToken(7, 5, false),
            'ballType' => 'masterball'
        });
        Test.stopTest();

        System.assertEquals(true, normalResults.get('caught'), 'Master ball always catches');
        System.assertEquals(false, normalResults.get('criticalCapture'), 'A forced non-critical catch should report false');
    }

    // ---- ToLong coercion (C1) ----

    @isTest static void testToLongCoercesDecimalIntegerAndNull(){
        System.assertEquals(50000L, pokemonGameHelper.ToLong((Object)Decimal.valueOf('50000.0')), 'A Decimal 50000.0 should floor to 50000');
        System.assertEquals(6L, pokemonGameHelper.ToLong((Object)6), 'An Integer 6 should pass through as 6');
        System.assertEquals(null, pokemonGameHelper.ToLong(null), 'Null should remain null');
    }

    @isTest static void testMinPermissionSpend(){
        User minUser = BuildTestUser('minperm');
        INSERT minUser;
        PermissionSet permissionSet = [SELECT Id FROM PermissionSet WHERE Name = 'Pokemon_Full_Access' LIMIT 1];
        INSERT new PermissionSetAssignment(AssigneeId = minUser.Id, PermissionSetId = permissionSet.Id);

        Test.startTest();
        System.runAs(minUser){
            Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Least Privilege', 25);

            Map<String,Object> purchaseResults = pokemonGameController.PurchaseItems(new Map<String,Object>{
                'cart' => new Map<String,Object>{ 'pokeball' => 1 }
            });
            System.assertEquals('success', purchaseResults.get('status'), 'Spend should succeed under least privilege');
            Pokemon_Trainer__c updated = (Pokemon_Trainer__c)purchaseResults.get('trainer');
            System.assertEquals(11, updated.Poke_Balls__c, 'Purchased ball should land under least privilege');
        }
        Test.stopTest();
    }

    // ---- S5.9 patchCount hard-cap (B1) ----

    @isTest static void testPatchCountClampsToBiomeCap(){
        // Verdant Meadow's Grass_Patch_Count__c is 4 — an oversized client patchCount must never exceed that cap.
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{
            'biome' => 'Verdant_Meadow',
            'patchCount' => 50
        });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Biome lookup should succeed: ' + results.get('message'));
        List<Map<String,Object>> patches = (List<Map<String,Object>>)results.get('patches');
        System.assert(patches.size() <= 4, 'A patchCount of 50 must clamp to the biome cap of 4, got ' + patches.size());
    }

    // ---- S5.9 ToInteger graceful floor (B2) ----

    @isTest static void testToIntegerCoercesDecimalIntegerAndNull(){
        // ToInteger is public on the helper, so assert it directly.
        System.assertEquals(6, pokemonGameHelper.ToInteger((Object)Decimal.valueOf('6.0')), 'A Decimal 6.0 should floor to 6');
        System.assertEquals(6, pokemonGameHelper.ToInteger((Object)6), 'An Integer 6 should pass through as 6');
        System.assertEquals(null, pokemonGameHelper.ToInteger(null), 'Null should remain null');
    }

    @isTest static void testNormalizeCartSkipsNullQuantity(){
        // NormalizeCart is public on the helper; a null cart quantity should be skipped, not NPE, while valid items survive.
        Map<String,Object> params = new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'pokeball' => null, 'greatball' => 2 }
        };
        Map<String,Integer> cart = pokemonGameHelper.NormalizeCart(params);
        System.assertEquals(false, cart.containsKey('pokeball'), 'A null cart quantity should be skipped, not throw');
        System.assertEquals(2, cart.get('greatball'), 'A valid cart quantity should survive alongside the skipped null');
    }

    // ---- Anti-inspect: the patch payload must not leak what is hiding in the grass ----

    @isTest static void testPatchesDoNotLeakEncounterDetails(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{ 'biome' => 'Verdant_Meadow' });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Biome lookup should succeed: ' + results.get('message'));
        List<Map<String,Object>> patches = (List<Map<String,Object>>)results.get('patches');
        System.assert(!patches.isEmpty(), 'Verdant Meadow should return at least one patch');
        for(Map<String,Object> patch : patches){
            System.assertEquals(false, patch.containsKey('dex'), 'The patch payload must not expose the species dex to the browser');
            System.assertEquals(false, patch.containsKey('name'), 'The patch payload must not expose the species name to the browser');
            System.assertEquals(false, patch.containsKey('level'), 'The patch payload must not expose the level to the browser');
            System.assertEquals(false, patch.containsKey('tier'), 'The patch payload must not expose the tier to the browser');
            System.assertNotEquals(null, patch.get('token'), 'The patch payload should carry only the encrypted token and shiny flag');
        }
    }

    // ---- S5.9 self-rival validation rule ----

    @isTest static void testTrainerCannotBeOwnRival(){
        Pokemon_Trainer__c trainer = CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Boolean dmlBlocked = false;
        try{
            trainer.Rival__c = trainer.Id;
            UPDATE trainer;
        }
        catch(DmlException error){
            dmlBlocked = true;
        }
        Test.stopTest();

        System.assertEquals(true, dmlBlocked, 'A Trainer set as its own rival must be blocked by the validation rule');
    }

    // ---- S6 exception-path coverage: the defensive catch blocks (savepoint rollback + rethrow, and the outer Fail) ----

    @isTest static void testCreateTrainerNameTooLongRollsBack(){
        // A Trainer Name past the 80-char Text limit fails the INSERT, exercising the savepoint rollback + rethrow.
        String overlongName = 'A'.repeat(300);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CreateTrainer(new Map<String,Object>{
            'trainerName' => overlongName,
            'starterPokedexId' => 25
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'An over-length trainer name should roll back and error');
        Integer trainerCount = [SELECT COUNT() FROM Pokemon_Trainer__c WHERE OwnerId = :UserInfo.getUserId()];
        System.assertEquals(0, trainerCount, 'The rolled-back insert should leave no trainer behind');
    }

    @isTest static void testGetMyTrainerBadIncludeFlagErrors(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetMyTrainer(new Map<String,Object>{ 'includePokemon' => 'not-a-boolean' });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A non-Boolean includePokemon flag should hit the catch and error');
    }

    @isTest static void testCatchGarbageTokenErrors(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.CatchPokemon(new Map<String,Object>{
            'token' => 'not-even-base64!!',
            'ballType' => 'pokeball'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A garbage token should fail to decode and error');
    }

    @isTest static void testPowerUpBadPokemonIdErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.PowerUpPokemon(new Map<String,Object>{
            'pokemonId' => 'not-an-id',
            'tokensToSpend' => 10
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A malformed pokemon Id should hit the catch and error');
    }

    @isTest static void testPurchaseBadCartQuantityErrors(){
        CreateTrainerAsCurrentUser('Ash', 25);

        Test.startTest();
        Map<String,Object> results = pokemonGameController.PurchaseItems(new Map<String,Object>{
            'cart' => new Map<String,Object>{ 'pokeball' => 'not-a-number' }
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A non-numeric cart quantity should hit the catch and error');
    }

    @isTest static void testTradeBadPokemonIdErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.TradePokemon(new Map<String,Object>{
            'pokemonId' => 'not-an-id',
            'targetTrainerId' => FakeTrainerId()
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A malformed pokemon Id should hit the catch and error');
    }

    @isTest static void testReleaseBadPokemonIdErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.ReleasePokemon(new Map<String,Object>{ 'pokemonId' => 'not-an-id' });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A malformed pokemon Id should hit the catch and error');
    }

    @isTest static void testRenameBadPokemonIdErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.RenamePokemon(new Map<String,Object>{
            'pokemonId' => 'not-an-id',
            'nickname' => 'Sparky'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A malformed pokemon Id should hit the catch and error');
    }

    @isTest static void testEvolveBadPokemonIdErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.EvolvePokemon(new Map<String,Object>{ 'pokemonId' => 'not-an-id' });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A malformed pokemon Id should hit the catch and error');
    }

    @isTest static void testGetBiomeBadPatchCountErrors(){
        Test.startTest();
        Map<String,Object> results = pokemonGameController.GetBiomePokemon(new Map<String,Object>{
            'biome' => 'Verdant_Meadow',
            'patchCount' => 'not-a-number'
        });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A non-numeric patch count should hit the catch and error');
    }
}