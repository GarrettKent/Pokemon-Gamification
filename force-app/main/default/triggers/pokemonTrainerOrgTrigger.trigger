trigger pokemonTrainerOrgTrigger on Pokemon_Trainer__c (before insert, before update) {
    pokemonTrainerOrgHelper.ClampAndStamp(Trigger.new);
}
