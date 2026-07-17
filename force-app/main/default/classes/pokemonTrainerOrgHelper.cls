/* Title: pokemonTrainerOrgHelper
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Before-trigger helper for Pokemon_Trainer__c — clamps currency, XP, ball and stone counts to non-negative values and stamps Trainer_Key__c from the owner when blank
 * Test Class: pokemonTrainerOrgHelper_Test
 * Modified: Garrett Kent - 07/04/2026 - Clamp the eight evolution stone counts to non-negative (parity with balls)
 */
public with sharing class pokemonTrainerOrgHelper {

    public static void ClampAndStamp(List<Pokemon_Trainer__c> trainers){
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
    }

    static Decimal ClampToNonNegative(Decimal value){
        return value == null || value < 0 ? 0 : value;
    }
}
