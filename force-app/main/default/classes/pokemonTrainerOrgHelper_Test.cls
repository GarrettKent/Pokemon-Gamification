/* Title: pokemonTrainerOrgHelper_Test
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Tests pokemonTrainerOrgHelper — verifies negative currency/XP/ball/stone counts clamp to 0 and Trainer_Key__c stamps to OwnerId on insert and update
 * Test Class: self
 * Modified: Garrett Kent - 07/04/2026 - Cover the eight evolution stone clamps
 * Modified: Garrett Kent - 07/22/2026 - Cover the ball guard: unflagged edits revert, game-flagged changes pass, Master Balls never increase
 */
@isTest
private class pokemonTrainerOrgHelper_Test {

    @isTest
    static void clampsAndStampsOnInsert() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
            Currency__c = -50,
            Experience_Tokens__c = -10,
            Poke_Balls__c = -1,
            Great_Balls__c = -2,
            Ultra_Balls__c = -3,
            Master_Balls__c = -4,
            Fire_Stones__c = -1,
            Water_Stones__c = -2,
            Thunder_Stones__c = -3,
            Leaf_Stones__c = -4,
            Moon_Stones__c = -5,
            Shiny_Stones__c = -6,
            Dusk_Stones__c = -7,
            Dawn_Stones__c = -8
        );

        Test.startTest();
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Pokemon_Trainer__c insertedTrainer = [
            SELECT Currency__c, Experience_Tokens__c, Poke_Balls__c, Great_Balls__c,
                   Ultra_Balls__c, Master_Balls__c, Fire_Stones__c, Water_Stones__c,
                   Thunder_Stones__c, Leaf_Stones__c, Moon_Stones__c, Shiny_Stones__c,
                   Dusk_Stones__c, Dawn_Stones__c, Trainer_Key__c, OwnerId
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(0, insertedTrainer.Currency__c, 'Negative Currency should clamp to 0');
        System.assertEquals(0, insertedTrainer.Experience_Tokens__c, 'Negative Experience Tokens should clamp to 0');
        System.assertEquals(0, insertedTrainer.Poke_Balls__c, 'Negative Poke Balls should clamp to 0');
        System.assertEquals(0, insertedTrainer.Great_Balls__c, 'Negative Great Balls should clamp to 0');
        System.assertEquals(0, insertedTrainer.Ultra_Balls__c, 'Negative Ultra Balls should clamp to 0');
        System.assertEquals(0, insertedTrainer.Master_Balls__c, 'Negative Master Balls should clamp to 0');
        System.assertEquals(0, insertedTrainer.Fire_Stones__c, 'Negative Fire Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Water_Stones__c, 'Negative Water Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Thunder_Stones__c, 'Negative Thunder Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Leaf_Stones__c, 'Negative Leaf Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Moon_Stones__c, 'Negative Moon Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Shiny_Stones__c, 'Negative Shiny Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Dusk_Stones__c, 'Negative Dusk Stones should clamp to 0');
        System.assertEquals(0, insertedTrainer.Dawn_Stones__c, 'Negative Dawn Stones should clamp to 0');
        System.assertEquals(String.valueOf(insertedTrainer.OwnerId), insertedTrainer.Trainer_Key__c, 'Trainer_Key__c should stamp to OwnerId when blank');
    }

    @isTest
    static void clampsOnUpdate() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
            Currency__c = 100,
            Poke_Balls__c = 5
        );
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);

        trainer.Currency__c = -25;
        trainer.Poke_Balls__c = -7;

        Test.startTest();
        Database.update(trainer, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Pokemon_Trainer__c updatedTrainer = [
            SELECT Currency__c, Poke_Balls__c
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(0, updatedTrainer.Currency__c, 'Negative Currency on update should clamp to 0');
        System.assertEquals(0, updatedTrainer.Poke_Balls__c, 'Negative Poke Balls on update should clamp to 0');
    }

    @isTest
    static void preservesPositiveValuesAndExistingKey() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
            Currency__c = 250,
            Experience_Tokens__c = 30,
            Poke_Balls__c = 9,
            Trainer_Key__c = 'custom-key'
        );

        Test.startTest();
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Pokemon_Trainer__c insertedTrainer = [
            SELECT Currency__c, Experience_Tokens__c, Poke_Balls__c, Trainer_Key__c
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(250, insertedTrainer.Currency__c, 'Positive Currency should be preserved');
        System.assertEquals(30, insertedTrainer.Experience_Tokens__c, 'Positive Experience Tokens should be preserved');
        System.assertEquals(9, insertedTrainer.Poke_Balls__c, 'Positive Poke Balls should be preserved');
        System.assertEquals('custom-key', insertedTrainer.Trainer_Key__c, 'Existing Trainer_Key__c should not be overwritten');
    }

    // ---- Ball guard: only game-flagged DML may change ball counts, and Master Balls may never increase ----

    @isTest
    static void ballGuardRevertsUnflaggedUpdate() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
            Poke_Balls__c = 5,
            Great_Balls__c = 4,
            Ultra_Balls__c = 3,
            Master_Balls__c = 2
        );
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);

        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        try {
            trainer.Poke_Balls__c = 50;
            trainer.Great_Balls__c = 40;
            trainer.Ultra_Balls__c = 30;
            trainer.Master_Balls__c = 20;

            Test.startTest();
            Database.update(trainer, AccessLevel.SYSTEM_MODE);
            Test.stopTest();
        }
        finally {
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }

        Pokemon_Trainer__c updatedTrainer = [
            SELECT Poke_Balls__c, Great_Balls__c, Ultra_Balls__c, Master_Balls__c
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(5, updatedTrainer.Poke_Balls__c, 'An unflagged Poke Ball raise should revert to the old value');
        System.assertEquals(4, updatedTrainer.Great_Balls__c, 'An unflagged Great Ball raise should revert to the old value');
        System.assertEquals(3, updatedTrainer.Ultra_Balls__c, 'An unflagged Ultra Ball raise should revert to the old value');
        System.assertEquals(2, updatedTrainer.Master_Balls__c, 'An unflagged Master Ball raise should revert to the old value');
    }

    @isTest
    static void ballGuardZeroesUnflaggedInsert() {
        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        try {
            Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
                Poke_Balls__c = 5,
                Great_Balls__c = 4,
                Ultra_Balls__c = 3,
                Master_Balls__c = 2
            );

            Test.startTest();
            Database.insert(trainer, AccessLevel.SYSTEM_MODE);
            Test.stopTest();

            Pokemon_Trainer__c insertedTrainer = [
                SELECT Poke_Balls__c, Great_Balls__c, Ultra_Balls__c, Master_Balls__c
                FROM Pokemon_Trainer__c
                WHERE Id = :trainer.Id
            ];

            System.assertEquals(0, insertedTrainer.Poke_Balls__c, 'An unflagged insert should zero Poke Balls');
            System.assertEquals(0, insertedTrainer.Great_Balls__c, 'An unflagged insert should zero Great Balls');
            System.assertEquals(0, insertedTrainer.Ultra_Balls__c, 'An unflagged insert should zero Ultra Balls');
            System.assertEquals(0, insertedTrainer.Master_Balls__c, 'An unflagged insert should zero Master Balls');
        }
        finally {
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }
    }

    @isTest
    static void ballGuardAllowsFlaggedChangesButNeverMasterRaise() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(
            Poke_Balls__c = 1,
            Great_Balls__c = 1,
            Ultra_Balls__c = 1,
            Master_Balls__c = 1
        );
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);

        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        pokemonTrainerOrgHelper.allowBallChanges = true;
        try {
            trainer.Poke_Balls__c = 6;
            trainer.Great_Balls__c = 5;
            trainer.Ultra_Balls__c = 4;
            trainer.Master_Balls__c = 3;

            Test.startTest();
            Database.update(trainer, AccessLevel.SYSTEM_MODE);
            Test.stopTest();
        }
        finally {
            pokemonTrainerOrgHelper.allowBallChanges = false;
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }

        Pokemon_Trainer__c updatedTrainer = [
            SELECT Poke_Balls__c, Great_Balls__c, Ultra_Balls__c, Master_Balls__c
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(6, updatedTrainer.Poke_Balls__c, 'A game-flagged Poke Ball raise should pass');
        System.assertEquals(5, updatedTrainer.Great_Balls__c, 'A game-flagged Great Ball raise should pass');
        System.assertEquals(4, updatedTrainer.Ultra_Balls__c, 'A game-flagged Ultra Ball raise should pass');
        System.assertEquals(1, updatedTrainer.Master_Balls__c, 'A Master Ball raise should revert even when game-flagged');
    }

    @isTest
    static void ballGuardAllowsFlaggedMasterDecrement() {
        Pokemon_Trainer__c trainer = new Pokemon_Trainer__c(Master_Balls__c = 2);
        Database.insert(trainer, AccessLevel.SYSTEM_MODE);

        pokemonTrainerOrgHelper.enforceBallGuardInTests = true;
        pokemonTrainerOrgHelper.allowBallChanges = true;
        try {
            trainer.Master_Balls__c = 1;

            Test.startTest();
            Database.update(trainer, AccessLevel.SYSTEM_MODE);
            Test.stopTest();
        }
        finally {
            pokemonTrainerOrgHelper.allowBallChanges = false;
            pokemonTrainerOrgHelper.enforceBallGuardInTests = false;
        }

        Pokemon_Trainer__c updatedTrainer = [
            SELECT Master_Balls__c
            FROM Pokemon_Trainer__c
            WHERE Id = :trainer.Id
        ];

        System.assertEquals(1, updatedTrainer.Master_Balls__c, 'A game-flagged Master Ball decrement (throw) should pass');
    }
}
