/* Title: PokemonRewardEngine
 * Created By: Garrett Kent - 07/06/2026
 * Purpose: Object-agnostic reward engine. One entry point run(newRecords, oldMap, op) that a subscriber
 *          calls from any after-insert/update trigger; matches Pokemon_Reward_Rule__mdt rows to the
 *          record's SObjectType, applies the edge/filter/exclude/multiplier semantics, resolves owners to
 *          Trainers, applies the daily currency cap, and does one bulk UPDATE. Names no specific object.
 *          Non-rethrowing + kill-switched. Runs without sharing: rewards are owner-only, so the owner's
 *          Trainer must update even when a different user's save fires the hook (Trainer sharing is Read).
 * Test Class: PokemonRewardEngine_Test
 * Modified: Garrett Kent - 07/06/2026 - 200-record bulk test green sync-in-trigger (1 SOQL + 1 DML); no Queueable needed
 * Modified: Garrett Kent - 07/06/2026 - Review fold-in: per-rule try/catch so one malformed rule row skips itself
 *           instead of silently zeroing every rule's payout for the transaction; helpers renamed to PascalCase
 * Modified: Garrett Kent - 07/06/2026 - Governor pre-flight before the trainer SOQL and UPDATE: LimitException is
 *           uncatchable, so the engine yields silently when the subscriber's transaction has no headroom left
 * Modified: Garrett Kent - 07/20/2026 - Test insulation: trigger-invoked runs no-op in test context unless a test
 *           opts in via allowTriggerRunsInTests, so subscriber test DML never pays or spends limits
 */
public without sharing class PokemonRewardEngine {

    // Per-user raw payout accumulator; the engine sums these, then rounds/caps/writes.
    private class RewardDelta {
        Decimal currencyAmount;
        Decimal xpAmount;
        RewardDelta(Decimal currencyAmount, Decimal xpAmount){
            this.currencyAmount = currencyAmount;
            this.xpAmount = xpAmount;
        }
    }

    @TestVisible static Boolean isAwarding = false;

    @TestVisible static List<Pokemon_Reward_Rule__mdt> ruleOverride;
    @TestVisible static Boolean automationEnabledOverride;
    @TestVisible static Decimal dailyCapOverride;
    @TestVisible static Boolean allowTriggerRunsInTests = false;

    public static void run(List<SObject> newRecords, Map<Id, SObject> oldMap, TriggerOperation op){
        try{
            if(newRecords == null || newRecords.isEmpty()) return;
            if(op != TriggerOperation.AFTER_INSERT && op != TriggerOperation.AFTER_UPDATE) return;
            // Subscriber tests fire the hooked triggers on every test DML; those runs stay no-ops
            // unless a test opts in, so test setup never pays and never spends the test's limits.
            if(Test.isRunningTest() && Trigger.isExecuting && !allowTriggerRunsInTests) return;
            if(!AutomationEnabled()) return;
            if(isAwarding) return;
            isAwarding = true;
            try{
                Award(newRecords, oldMap, op == TriggerOperation.AFTER_INSERT);
            }
            finally{
                isAwarding = false;
            }
        }
        catch(Exception e){
            System.debug('ERROR in PokemonRewardEngine.run: ' + e.getLineNumber() + ' - ' + e.getMessage());
        }
    }

    static void Award(List<SObject> newRecords, Map<Id, SObject> oldMap, Boolean isInsertOp){
        String sObjectName = newRecords[0].getSObjectType().getDescribe().getName();
        List<Pokemon_Reward_Rule__mdt> matchingRules = new List<Pokemon_Reward_Rule__mdt>();
        for(Pokemon_Reward_Rule__mdt rule : GetRules()){
            Boolean objectMatches = rule.SObject_API_Name__c != null && rule.SObject_API_Name__c.trim().equalsIgnoreCase(sObjectName);
            if(rule.Active__c == true && objectMatches && RunOnIncludesOp(rule.Run_On__c, isInsertOp)){
                matchingRules.add(rule);
            }
        }
        if(matchingRules.isEmpty()) return;

        Map<Id, RewardDelta> deltasByUser = new Map<Id, RewardDelta>();
        for(Pokemon_Reward_Rule__mdt rule : matchingRules){
            // Each rule is isolated: a malformed row (bad field API name, non-numeric multiplier field)
            // skips itself without starving the other rules' payouts.
            try{
                AccumulateRule(rule, newRecords, oldMap, isInsertOp, deltasByUser);
            }
            catch(Exception ruleError){
                System.debug('ERROR in PokemonRewardEngine.Award: rule ' + rule.DeveloperName + ' skipped - ' + ruleError.getMessage());
            }
        }
        if(deltasByUser.isEmpty()) return;

        Set<String> trainerKeys = new Set<String>();
        for(Id userId : deltasByUser.keySet()){
            trainerKeys.add(String.valueOf(userId));
        }

        // Governor pre-flight: LimitException is uncatchable, so if the subscriber's transaction has no
        // SOQL headroom left, yield the reward silently rather than kill their save reaching for it.
        if(Limits.getQueries() >= Limits.getLimitQueries() || Limits.getQueryRows() + trainerKeys.size() > Limits.getLimitQueryRows()) return;

        Date today = Date.today();
        List<Pokemon_Trainer__c> trainersToUpdate = new List<Pokemon_Trainer__c>();
        for(Pokemon_Trainer__c trainer : [SELECT Id, Currency__c, Currency_Today__c, Earn_Date__c, Experience_Tokens__c, Trainer_Key__c
                                          FROM Pokemon_Trainer__c WHERE Trainer_Key__c IN :trainerKeys]){
            RewardDelta rawDelta = deltasByUser.get(UserIdFromKey(trainer.Trainer_Key__c));
            if(rawDelta == null) continue;

            // Round the summed per-user amounts once, before the cap comparison — never per-delta.
            Decimal currencyRounded = rawDelta.currencyAmount.setScale(0, System.RoundingMode.HALF_UP);
            Decimal xpRounded = rawDelta.xpAmount.setScale(0, System.RoundingMode.HALF_UP);

            if(trainer.Earn_Date__c != today) trainer.Currency_Today__c = 0;
            Decimal currencyToday = trainer.Currency_Today__c == null ? 0 : trainer.Currency_Today__c;
            Decimal headroom = DailyCap() - currencyToday;
            Decimal grant = currencyRounded < headroom ? currencyRounded : headroom;
            if(grant < 0) grant = 0;

            trainer.Currency__c = ClampToNonNegative((trainer.Currency__c == null ? 0 : trainer.Currency__c) + grant);
            trainer.Currency_Today__c = ClampToNonNegative(currencyToday + grant);
            trainer.Earn_Date__c = today;
            trainer.Experience_Tokens__c = ClampToNonNegative((trainer.Experience_Tokens__c == null ? 0 : trainer.Experience_Tokens__c) + xpRounded);
            trainersToUpdate.add(trainer);
        }
        if(trainersToUpdate.isEmpty()) return;
        if(Limits.getDmlStatements() >= Limits.getLimitDmlStatements() || Limits.getDmlRows() + trainersToUpdate.size() > Limits.getLimitDmlRows()) return;
        UPDATE trainersToUpdate;
    }

    static void AccumulateRule(Pokemon_Reward_Rule__mdt rule, List<SObject> newRecords, Map<Id, SObject> oldMap, Boolean isInsertOp, Map<Id, RewardDelta> deltasByUser){
        Set<String> doneValues = SplitTrimmedLower(rule.Done_Values__c);
        Set<String> filterValues = SplitTrimmedLower(rule.Filter_Values__c);
        Set<String> excludeValues = SplitTrimmedLower(rule.Exclude_Values__c);

        for(SObject record : newRecords){
            if(String.isBlank(rule.Edge_Field__c)){
                // Blank-edge rules pay only on insert, regardless of Run_On__c — never on every save.
                if(!isInsertOp) continue;
            }
            else{
                String newEdgeValue = Normalized(record.get(rule.Edge_Field__c));
                if(newEdgeValue == null || !doneValues.contains(newEdgeValue)) continue;
                if(!isInsertOp){
                    String oldEdgeValue = Normalized(oldMap.get(record.Id).get(rule.Edge_Field__c));
                    if(oldEdgeValue != null && doneValues.contains(oldEdgeValue)) continue;
                }
            }

            if(String.isNotBlank(rule.Filter_Field__c)){
                String filterValue = Normalized(record.get(rule.Filter_Field__c));
                if(filterValue == null || !filterValues.contains(filterValue)) continue;
            }

            if(String.isNotBlank(rule.Exclude_Field__c)){
                String excludeValue = Normalized(record.get(rule.Exclude_Field__c));
                if(excludeValue == null || excludeValues.contains(excludeValue)) continue;
            }

            String ownerIdValue = String.valueOf(record.get('OwnerId'));
            if(String.isBlank(ownerIdValue) || !ownerIdValue.startsWith('005')) continue;

            Decimal multiplier = MultiplierFor(rule, record);
            Decimal currencyDelta = (rule.Currency__c == null ? 0 : rule.Currency__c) * multiplier;
            Decimal xpDelta = (rule.XP__c == null ? 0 : rule.XP__c) * multiplier;
            MergeDelta(deltasByUser, (Id)ownerIdValue, currencyDelta, xpDelta);
        }
    }

    static Decimal MultiplierFor(Pokemon_Reward_Rule__mdt rule, SObject record){
        if(String.isBlank(rule.Multiplier_Field__c)) return 1;
        Object rawMultiplier = record.get(rule.Multiplier_Field__c);
        Decimal multiplier = 0;
        if(rawMultiplier instanceof Decimal){
            multiplier = (Decimal)rawMultiplier;
        }
        else if(rawMultiplier != null){
            multiplier = Decimal.valueOf(String.valueOf(rawMultiplier));
        }
        if(multiplier < 0) multiplier = 0;
        if(rule.Multiplier_Cap__c != null && multiplier > rule.Multiplier_Cap__c) multiplier = rule.Multiplier_Cap__c;
        return multiplier;
    }

    static void MergeDelta(Map<Id, RewardDelta> deltasByUser, Id ownerId, Decimal currencyDelta, Decimal xpDelta){
        RewardDelta existing = deltasByUser.get(ownerId);
        if(existing == null){
            deltasByUser.put(ownerId, new RewardDelta(currencyDelta, xpDelta));
        }
        else{
            existing.currencyAmount += currencyDelta;
            existing.xpAmount += xpDelta;
        }
    }

    static Boolean RunOnIncludesOp(String runOn, Boolean isInsertOp){
        if(String.isBlank(runOn)) return false;
        if(runOn == 'Insert & Update') return true;
        return isInsertOp ? runOn == 'Insert' : runOn == 'Update';
    }

    static Boolean AutomationEnabled(){
        if(automationEnabledOverride != null) return automationEnabledOverride;
        Pokemon_Settings__mdt settings = Pokemon_Settings__mdt.getInstance('Default');
        return settings != null && settings.Automation_Enabled__c == true;
    }

    static Decimal DailyCap(){
        if(dailyCapOverride != null) return dailyCapOverride;
        Pokemon_Settings__mdt settings = Pokemon_Settings__mdt.getInstance('Default');
        return settings == null || settings.Daily_Total_Currency_Cap__c == null ? 0 : settings.Daily_Total_Currency_Cap__c;
    }

    static Set<String> SplitTrimmedLower(String configList){
        Set<String> parsedValues = new Set<String>();
        if(String.isBlank(configList)) return parsedValues;
        for(String entry : configList.split(',')){
            String normalizedEntry = entry.trim().toLowerCase();
            if(normalizedEntry != '') parsedValues.add(normalizedEntry);
        }
        return parsedValues;
    }

    static Decimal ClampToNonNegative(Decimal amount){
        return amount == null || amount < 0 ? 0 : amount;
    }

    static String Normalized(Object fieldValue){
        if(fieldValue == null) return null;
        String stringValue = String.valueOf(fieldValue).trim().toLowerCase();
        return stringValue == '' ? null : stringValue;
    }

    static Id UserIdFromKey(String trainerKey){
        return (Id)trainerKey;
    }

    @TestVisible static List<Pokemon_Reward_Rule__mdt> GetRules(){
        if(ruleOverride != null) return ruleOverride;
        return Pokemon_Reward_Rule__mdt.getAll().values();
    }
}
