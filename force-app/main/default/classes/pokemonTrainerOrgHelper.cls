/* Title: pokemonTrainerOrgHelper
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Before-trigger helper for Pokemon_Trainer__c — clamps currency, XP, ball and stone counts to non-negative values and stamps Trainer_Key__c from the owner when blank
 * Test Class: pokemonTrainerOrgHelper_Test
 * Modified: Garrett Kent - 07/04/2026 - Clamp the eight evolution stone counts to non-negative (parity with balls)
 * Modified: Garrett Kent - 07/22/2026 - Guard ball fields: only game code may change them, and Master Balls can never increase at all
 */
public with sharing class pokemonTrainerOrgHelper {

    // Game code (starter grant, Poke Mart purchase, ball throw) sets this true around its trainer DML; any other save has ball edits reverted.
    public static Boolean allowBallChanges = false;

    // The guard no-ops in test context unless a test opts in, so test seeds that set ball counts directly keep working (same pattern as PokemonRewardEngine.allowTriggerRunsInTests).
    @TestVisible static Boolean enforceBallGuardInTests = false;

    public static void ClampAndStamp(List<Pokemon_Trainer__c> trainers, Map<Id,Pokemon_Trainer__c> oldTrainers){
        for(Pokemon_Trainer__c trainer : trainers){
            trainer.Currency__c = ClampToNonNegative(trainer.Currency__c);
            trainer.Experience_Tokens__c = ClampToNonNegative(trainer.Experience_Tokens__c);
            trainer.Poke_Balls__c = ClampToNonNegative(trainer.Poke_Balls__c);
            trainer.Great_Balls__c = ClampToNonNegative(trainer.Great_Balls__c);
            trainer.Ultra_Balls__c = ClampToNonNegative(trainer.Ultra_Balls__c);
            trainer.Master_Balls__c = ClampToNonNegative(trainer.Master_Balls__c);
            trainer.Fire_Stones__c = ClampToNonNegative(trainer.Fire_Stones__c);
            trainer.Water_Stones__c = ClampToNonNegative(trainer.Water_Stones__c);
            trainer.Thunder_Stones__c = ClampToNonNegative(trainer.Thunder_Stones__c);
            trainer.Leaf_Stones__c = ClampToNonNegative(trainer.Leaf_Stones__c);
            trainer.Moon_Stones__c = ClampToNonNegative(trainer.Moon_Stones__c);
            trainer.Shiny_Stones__c = ClampToNonNegative(trainer.Shiny_Stones__c);
            trainer.Dusk_Stones__c = ClampToNonNegative(trainer.Dusk_Stones__c);
            trainer.Dawn_Stones__c = ClampToNonNegative(trainer.Dawn_Stones__c);

            if(String.isBlank(trainer.Trainer_Key__c)) trainer.Trainer_Key__c = String.valueOf(trainer.OwnerId);
        }

        GuardBallFields(trainers, oldTrainers);
    }

    static void GuardBallFields(List<Pokemon_Trainer__c> trainers, Map<Id,Pokemon_Trainer__c> oldTrainers){
        if(Test.isRunningTest() && !enforceBallGuardInTests) return;

        Boolean isInsert = oldTrainers == null;
        for(Pokemon_Trainer__c trainer : trainers){
            Pokemon_Trainer__c oldTrainer = isInsert ? null : oldTrainers.get(trainer.Id);

            if(!allowBallChanges){
                if(isInsert){
                    trainer.Poke_Balls__c = 0;
                    trainer.Great_Balls__c = 0;
                    trainer.Ultra_Balls__c = 0;
                }
                else{
                    trainer.Poke_Balls__c = ClampToNonNegative(oldTrainer.Poke_Balls__c);
                    trainer.Great_Balls__c = ClampToNonNegative(oldTrainer.Great_Balls__c);
                    trainer.Ultra_Balls__c = ClampToNonNegative(oldTrainer.Ultra_Balls__c);
                }
            }

            // Master Balls are unobtainable by design: zero on insert and never allowed to increase, even by game code. Decrements (throws) pass.
            // Relax this block if the commented-out milestone grant in pokemonGameController is ever re-enabled.
            if(isInsert) trainer.Master_Balls__c = 0;
            else if(trainer.Master_Balls__c > ClampToNonNegative(oldTrainer.Master_Balls__c)) trainer.Master_Balls__c = ClampToNonNegative(oldTrainer.Master_Balls__c);
        }
    }

    static Decimal ClampToNonNegative(Decimal value){
        return value == null || value < 0 ? 0 : value;
    }
}
