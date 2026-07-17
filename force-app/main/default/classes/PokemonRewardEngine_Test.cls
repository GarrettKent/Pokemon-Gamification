/* Title: PokemonRewardEngine_Test
 * Created By: Garrett Kent - 07/06/2026
 * Purpose: Tests every reward-engine behavior from the Phase-2 design — edge/filter/exclude/multiplier
 *          semantics, blank-edge insert-only guardrail, trimmed case-insensitive matching, per-user
 *          summing + round-before-cap, daily cap machinery, XP target, plumbing guards, and the
 *          200-record bulk run. Case is the stand-in source object; Opportunity.Amount stands in for
 *          the numeric multiplier field.
 * Test Class: self
 * Modified: Garrett Kent - 07/06/2026 - Coverage-review fold-in: pin blank-edge insert-vs-update halves, exclude-list
 *           trim/case matching, per-record exclude asserts, non-after positive control, multiplier-cap below daily cap,
 *           fractional multiplier rounding, uneven bulk split + governor headroom, swallow-and-release-guard test
 * Modified: Garrett Kent - 07/06/2026 - Adversarial-review fold-in: badRuleDoesNotStarveGoodRules (per-rule isolation)
 */
@isTest
private class PokemonRewardEngine_Test {

    @TestSetup static void setupTestData(){
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Long uniqueStamp = DateTime.now().getTime();
        User ownerUser = buildUser(standardProfile.Id, 'PokemonRewardOwner', 'rwown', uniqueStamp);
        User secondUser = buildUser(standardProfile.Id, 'PokemonRewardSecond', 'rwsec', uniqueStamp + 1);
        User noTrainerUser = buildUser(standardProfile.Id, 'PokemonRewardNoTrainer', 'rwnot', uniqueStamp + 2);
        System.runAs(new User(Id = UserInfo.getUserId())){
            INSERT new List<User>{ ownerUser, secondUser, noTrainerUser };
        }

        INSERT new List<Pokemon_Trainer__c>{
            new Pokemon_Trainer__c(Name = 'Reward Owner', Trainer_Key__c = String.valueOf(ownerUser.Id), Currency__c = 0, Currency_Today__c = 0, Experience_Tokens__c = 0),
            new Pokemon_Trainer__c(Name = 'Reward Second', Trainer_Key__c = String.valueOf(secondUser.Id), Currency__c = 0, Currency_Today__c = 0, Experience_Tokens__c = 0)
        };
    }

    static User buildUser(Id profileId, String lastName, String alias, Long uniqueStamp){
        return new User(
            FirstName = 'Pokemon',
            LastName = lastName,
            Alias = alias,
            Username = lastName.toLowerCase() + '.' + uniqueStamp + '@pokemon.example.com',
            Email = lastName.toLowerCase() + '@pokemon.example.com',
            ProfileId = profileId,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York'
        );
    }

    static User userByLastName(String lastName){
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    static Pokemon_Trainer__c trainerFor(Id userId){
        return [SELECT Id, Currency__c, Currency_Today__c, Earn_Date__c, Experience_Tokens__c, Trainer_Key__c
                FROM Pokemon_Trainer__c WHERE Trainer_Key__c = :String.valueOf(userId) LIMIT 1];
    }

    static Pokemon_Reward_Rule__mdt caseRule(){
        return new Pokemon_Reward_Rule__mdt(
            DeveloperName = 'Case_Closed_Test',
            Active__c = true,
            SObject_API_Name__c = 'Case',
            Run_On__c = 'Insert & Update',
            Edge_Field__c = 'Status',
            Done_Values__c = 'Closed',
            Exclude_Field__c = 'Type',
            Exclude_Values__c = 'Junk, Comms Case',
            Currency__c = 12,
            XP__c = 60
        );
    }

    static Pokemon_Reward_Rule__mdt opportunityRule(Decimal multiplierCap){
        return new Pokemon_Reward_Rule__mdt(
            DeveloperName = 'Opportunity_Multiplier_Test',
            Active__c = true,
            SObject_API_Name__c = 'Opportunity',
            Run_On__c = 'Insert',
            Currency__c = 10,
            XP__c = 42,
            Multiplier_Field__c = 'Amount',
            Multiplier_Cap__c = multiplierCap
        );
    }

    static Case makeCase(Id ownerId, String status, String caseType, String origin){
        return new Case(OwnerId = ownerId, Status = status, Type = caseType, Origin = origin, Subject = 'Reward Engine Test');
    }

    static Opportunity makeOpportunity(Id ownerId, Decimal amount){
        return new Opportunity(OwnerId = ownerId, Name = 'Reward Engine Test', StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = amount);
    }

    static Map<Id, SObject> oldStatusMap(List<Case> updatedCases, String oldStatus){
        Map<Id, SObject> oldMap = new Map<Id, SObject>();
        for(Case caseRecord : updatedCases){
            oldMap.put(caseRecord.Id, new Case(Id = caseRecord.Id, Status = oldStatus, Type = caseRecord.Type, Origin = caseRecord.Origin, OwnerId = caseRecord.OwnerId));
        }
        return oldMap;
    }

    static void arm(List<Pokemon_Reward_Rule__mdt> rules){
        PokemonRewardEngine.ruleOverride = rules;
        PokemonRewardEngine.automationEnabledOverride = true;
        PokemonRewardEngine.dailyCapOverride = 120;
    }

    @isTest static void awardsOnUpdateEdgeIntoDone(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        INSERT workCase;
        workCase.Status = 'Closed';

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, oldStatusMap(new List<Case>{ workCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'Update into Closed should pay the base currency');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'Update into Closed should pay the base XP');
        System.assertEquals(12, ownerTrainer.Currency_Today__c.intValue(), 'Currency_Today__c should track the day\'s grants');
        System.assertEquals(Date.today(), ownerTrainer.Earn_Date__c, 'Earn_Date__c should stamp today on an award');
    }

    @isTest static void awardsOnInsertCreatedIntoDone(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A record created already done should pay (null oldMap insert path)');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'A record created already done should pay XP');
    }

    @isTest static void noPayOnResaveAlreadyDone(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, oldStatusMap(new List<Case>{ workCase }, 'Closed'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A re-save of an already-done record must pay nothing');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'A re-save of an already-done record must pay no XP');
    }

    @isTest static void excludeFieldBlocksAward(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case junkCase = makeCase(ownerUser.Id, 'New', 'Junk', 'Web');
        Case nullTypeCase = makeCase(ownerUser.Id, 'New', null, 'Web');
        List<Case> excludedCases = new List<Case>{ junkCase, nullTypeCase };
        INSERT excludedCases;
        junkCase.Status = 'Closed';
        nullTypeCase.Status = 'Closed';

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ junkCase }, oldStatusMap(new List<Case>{ junkCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A Type value in the exclude list must block the award');

        PokemonRewardEngine.run(new List<SObject>{ nullTypeCase }, oldStatusMap(new List<Case>{ nullTypeCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A null value must also be excluded when an exclude is configured');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'Excluded records must pay no XP');
    }

    @isTest static void ownerNotAUserNoTrainerSkipped(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        User noTrainerUser = userByLastName('PokemonRewardNoTrainer');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });

        Group caseQueue;
        System.runAs(new User(Id = UserInfo.getUserId())){
            caseQueue = new Group(Name = 'Pokemon Reward Test Queue', DeveloperName = 'Pokemon_Reward_Test_Queue', Type = 'Queue');
            INSERT caseQueue;
            INSERT new QueueSobject(QueueId = caseQueue.Id, SobjectType = 'Case');
        }

        Case queueCase = makeCase(caseQueue.Id, 'Closed', 'Mechanical', 'Web');
        Case noTrainerCase = makeCase(noTrainerUser.Id, 'Closed', 'Mechanical', 'Web');
        List<Case> skippedCases = new List<Case>{ queueCase, noTrainerCase };
        INSERT skippedCases;

        Test.startTest();
        PokemonRewardEngine.run(skippedCases, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A queue-owned record and a User with no Trainer must both no-op without exception');
        System.assertEquals(2, [SELECT COUNT() FROM Pokemon_Trainer__c], 'The engine must never create Trainer records');
    }

    @isTest static void roundsSummedBeforeCap(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt fractionalRule = caseRule();
        fractionalRule.Currency__c = 2.4;
        fractionalRule.XP__c = 2.4;
        arm(new List<Pokemon_Reward_Rule__mdt>{ fractionalRule });
        Case firstCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        Case secondCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        List<Case> fractionalCases = new List<Case>{ firstCase, secondCase };
        INSERT fractionalCases;
        firstCase.Status = 'Closed';
        secondCase.Status = 'Closed';

        Test.startTest();
        PokemonRewardEngine.run(fractionalCases, oldStatusMap(fractionalCases, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(5, ownerTrainer.Currency__c.intValue(), '2.4 + 2.4 must sum to 4.8 then round once to 5 — never round per-delta to 4');
        System.assertEquals(5, ownerTrainer.Experience_Tokens__c.intValue(), 'XP must also sum before the single rounding');
    }

    @isTest static void dailyCapClampsGrant(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        ownerTrainer.Currency_Today__c = 118;
        ownerTrainer.Earn_Date__c = Date.today();
        UPDATE ownerTrainer;

        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(2, ownerTrainer.Currency__c.intValue(), 'With 118 of 120 already earned today, a 12 currency award must grant only the 2 of headroom');
        System.assertEquals(120, ownerTrainer.Currency_Today__c.intValue(), 'Currency_Today__c must stop exactly at the daily cap');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'XP is uncapped and must pay in full');
    }

    @isTest static void dailyResetOnDateRollover(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        ownerTrainer.Currency_Today__c = 120;
        ownerTrainer.Earn_Date__c = Date.today().addDays(-1);
        UPDATE ownerTrainer;

        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A stale Earn_Date__c must reset Currency_Today__c before capping, so the full award grants');
        System.assertEquals(12, ownerTrainer.Currency_Today__c.intValue(), 'Currency_Today__c must restart from 0 on the date rollover');
        System.assertEquals(Date.today(), ownerTrainer.Earn_Date__c, 'Earn_Date__c must stamp today after the rollover');
    }

    @isTest static void crossTransactionAccumulation(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        PokemonRewardEngine.dailyCapOverride = 20;
        Case firstCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case secondCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT new List<Case>{ firstCase, secondCase };

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ firstCase }, null, TriggerOperation.AFTER_INSERT);
        PokemonRewardEngine.run(new List<SObject>{ secondCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(20, ownerTrainer.Currency__c.intValue(), 'The second transaction must be capped by the running Currency_Today__c from the first (12 + 8, not 12 + 12)');
        System.assertEquals(20, ownerTrainer.Currency_Today__c.intValue(), 'Currency_Today__c must accumulate across transactions in the same day');
        System.assertEquals(120, ownerTrainer.Experience_Tokens__c.intValue(), 'XP is uncapped and must pay in full across both transactions');
    }

    @isTest static void crossRuleSummingMerge(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt bonusRule = caseRule();
        bonusRule.DeveloperName = 'Case_Closed_Bonus_Test';
        bonusRule.Currency__c = 5;
        bonusRule.XP__c = 25;
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule(), bonusRule });
        Case workCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        INSERT workCase;
        workCase.Status = 'Closed';

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, oldStatusMap(new List<Case>{ workCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(17, ownerTrainer.Currency__c.intValue(), 'Two matching rules on one object must sum into a single Trainer update (12 + 5)');
        System.assertEquals(85, ownerTrainer.Experience_Tokens__c.intValue(), 'XP must merge across rules (60 + 25)');
    }

    @isTest static void xpWritesToExperienceTokens(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'XP must land in Experience_Tokens__c, the spendable bank');
    }

    @isTest static void clampNeverNegative(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt negativeRule = caseRule();
        negativeRule.Currency__c = -5;
        negativeRule.XP__c = -5;
        arm(new List<Pokemon_Reward_Rule__mdt>{ negativeRule });
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        ownerTrainer.Currency_Today__c = 130;
        ownerTrainer.Earn_Date__c = Date.today();
        UPDATE ownerTrainer;

        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'Negative headroom and negative rule amounts must never drive Currency__c below 0');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'Experience_Tokens__c must never go below 0');
    }

    @isTest static void emptyOrNullRecordsEarlyReturn(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });

        Test.startTest();
        PokemonRewardEngine.run(null, null, TriggerOperation.AFTER_INSERT);
        PokemonRewardEngine.run(new List<SObject>(), null, TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'Null and empty record lists must early-return without exception or award');
    }

    @isTest static void killSwitchOffNoAward(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        PokemonRewardEngine.automationEnabledOverride = false;
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'The kill switch must block every award');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'The kill switch must block XP too');
    }

    @isTest static void recursionGuardBlocksReentry(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case firstCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case secondCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT new List<Case>{ firstCase, secondCase };

        Test.startTest();
        PokemonRewardEngine.isAwarding = true;
        PokemonRewardEngine.run(new List<SObject>{ firstCase }, null, TriggerOperation.AFTER_INSERT);
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A re-entrant run must be blocked by the recursion guard');

        PokemonRewardEngine.isAwarding = false;
        PokemonRewardEngine.run(new List<SObject>{ secondCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'Once the guard clears, a fresh run must pay normally');
    }

    @isTest static void filterFieldIncludesOnlyMatching(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt webOnlyRule = caseRule();
        webOnlyRule.Filter_Field__c = 'Origin';
        webOnlyRule.Filter_Values__c = 'Web';
        arm(new List<Pokemon_Reward_Rule__mdt>{ webOnlyRule });
        Case webCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case phoneCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Phone');
        List<Case> mixedCases = new List<Case>{ webCase, phoneCase };
        INSERT mixedCases;

        Test.startTest();
        PokemonRewardEngine.run(mixedCases, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'Only the record matching the include filter must pay — one award, not two');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'Only the filtered-in record must pay XP');
    }

    @isTest static void filterNullValueFailsFilter(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt webOnlyRule = caseRule();
        webOnlyRule.Filter_Field__c = 'Origin';
        webOnlyRule.Filter_Values__c = 'Web';
        arm(new List<Pokemon_Reward_Rule__mdt>{ webOnlyRule });
        Case noOriginCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', null);
        INSERT noOriginCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ noOriginCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A null filter-field value must fail the include filter and skip the record');
    }

    @isTest static void multiplierScalesPayout(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ opportunityRule(null) });
        Opportunity hoursStandIn = makeOpportunity(ownerUser.Id, 7.5);
        INSERT hoursStandIn;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ hoursStandIn }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(75, ownerTrainer.Currency__c.intValue(), 'A 7.5 multiplier on a base of 10 must pay 75 currency');
        System.assertEquals(315, ownerTrainer.Experience_Tokens__c.intValue(), 'A 7.5 multiplier on a base of 42 must pay 315 XP');
    }

    @isTest static void multiplierCapClamps(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt cappedRule = opportunityRule(12);
        cappedRule.Currency__c = 5;
        arm(new List<Pokemon_Reward_Rule__mdt>{ cappedRule });
        Opportunity hoursStandIn = makeOpportunity(ownerUser.Id, 15);
        INSERT hoursStandIn;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ hoursStandIn }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(60, ownerTrainer.Currency__c.intValue(), 'A 15 field value with a cap of 12 must pay base x12 (60), not x15 (75) — asserted below the daily cap so the multiplier cap itself is proven');
        System.assertEquals(504, ownerTrainer.Experience_Tokens__c.intValue(), 'XP must clamp to the same capped multiplier (42 x 12)');
    }

    @isTest static void multiplierFractionalProductRounds(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ opportunityRule(null) });
        Opportunity fractionalHours = makeOpportunity(ownerUser.Id, 0.92);
        INSERT fractionalHours;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ fractionalHours }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(9, ownerTrainer.Currency__c.intValue(), 'A fractional product must round half-up once: 10 x 0.92 = 9.2 rounds to 9');
        System.assertEquals(39, ownerTrainer.Experience_Tokens__c.intValue(), 'XP rounds its own product independently: 42 x 0.92 = 38.64 rounds to 39');
    }

    @isTest static void multiplierNullOrNegativeIsZero(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ opportunityRule(12) });
        Opportunity nullAmount = makeOpportunity(ownerUser.Id, null);
        Opportunity negativeAmount = makeOpportunity(ownerUser.Id, -3);
        List<Opportunity> zeroOpportunities = new List<Opportunity>{ nullAmount, negativeAmount };
        INSERT zeroOpportunities;

        Test.startTest();
        PokemonRewardEngine.run(zeroOpportunities, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'Null and negative multiplier values must both pay 0 without exception');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'Null and negative multiplier values must pay no XP');
    }

    @isTest static void blankMultiplierIsTimesOne(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt flatRule = opportunityRule(null);
        flatRule.Multiplier_Field__c = null;
        arm(new List<Pokemon_Reward_Rule__mdt>{ flatRule });
        Opportunity flatOpportunity = makeOpportunity(ownerUser.Id, 999);
        INSERT flatOpportunity;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ flatOpportunity }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(10, ownerTrainer.Currency__c.intValue(), 'A blank multiplier field must mean x1 — the flat base, ignoring any numeric fields on the record');
        System.assertEquals(42, ownerTrainer.Experience_Tokens__c.intValue(), 'A blank multiplier field must pay flat base XP');
    }

    @isTest static void blankEdgePaysOnInsertOnly(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt blankEdgeRule = caseRule();
        blankEdgeRule.Edge_Field__c = null;
        blankEdgeRule.Done_Values__c = null;
        arm(new List<Pokemon_Reward_Rule__mdt>{ blankEdgeRule });
        Case workCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A blank-edge rule must pay on the insert operation');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'A blank-edge rule must pay XP on insert');

        PokemonRewardEngine.run(new List<SObject>{ workCase }, oldStatusMap(new List<Case>{ workCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A blank-edge rule must add NOTHING on update, even with Run_On = Insert & Update');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'The update pass of a blank-edge rule must add no XP');
    }

    @isTest static void valueMatchingIsTrimmedCaseInsensitive(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt sloppyRule = caseRule();
        sloppyRule.Done_Values__c = ' closed ';
        sloppyRule.Filter_Field__c = 'Origin';
        sloppyRule.Filter_Values__c = 'web , EMAIL';
        sloppyRule.Exclude_Values__c = ' JUNK , comms case';
        arm(new List<Pokemon_Reward_Rule__mdt>{ sloppyRule });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case junkCase = makeCase(ownerUser.Id, 'Closed', 'Junk', 'Web');
        List<Case> sloppyCases = new List<Case>{ workCase, junkCase };
        INSERT sloppyCases;

        Test.startTest();
        PokemonRewardEngine.run(sloppyCases, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'Admin-typed config like \' closed \' and \'web\' must match trimmed and case-insensitively, and \' JUNK \' must still exclude a \'Junk\' record — one award, not two or zero');
    }

    @isTest static void multipleRowsPerObjectAccumulate(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt webBoardRule = caseRule();
        webBoardRule.DeveloperName = 'Web_Board_Test';
        webBoardRule.Filter_Field__c = 'Origin';
        webBoardRule.Filter_Values__c = 'Web';
        webBoardRule.Currency__c = 5;
        webBoardRule.XP__c = 25;
        Pokemon_Reward_Rule__mdt phoneBoardRule = caseRule();
        phoneBoardRule.DeveloperName = 'Phone_Board_Test';
        phoneBoardRule.Filter_Field__c = 'Origin';
        phoneBoardRule.Filter_Values__c = 'Phone';
        phoneBoardRule.Currency__c = 15;
        phoneBoardRule.XP__c = 75;
        arm(new List<Pokemon_Reward_Rule__mdt>{ webBoardRule, phoneBoardRule });
        Case webCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case phoneCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Phone');
        List<Case> boardCases = new List<Case>{ webCase, phoneCase };
        INSERT boardCases;

        Test.startTest();
        PokemonRewardEngine.run(boardCases, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(20, ownerTrainer.Currency__c.intValue(), 'Each record must pay only its own board-style rule (5 + 15), accumulated in one run');
        System.assertEquals(100, ownerTrainer.Experience_Tokens__c.intValue(), 'XP must accumulate per-rule per-record (25 + 75)');
    }

    @isTest static void bulkTwoHundredRecordsOneUpdate(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        User secondUser = userByLastName('PokemonRewardSecond');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        List<Case> bulkCases = new List<Case>();
        for(Integer caseIndex = 0; caseIndex < 200; caseIndex++){
            Id bulkOwnerId = caseIndex < 120 ? ownerUser.Id : secondUser.Id;
            bulkCases.add(makeCase(bulkOwnerId, 'New', 'Mechanical', 'Web'));
        }
        INSERT bulkCases;
        for(Case bulkCase : bulkCases){
            bulkCase.Status = 'Closed';
        }
        Map<Id, SObject> bulkOldMap = oldStatusMap(bulkCases, 'New');

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer soqlBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();
        Integer cpuBefore = Limits.getCpuTime();
        PokemonRewardEngine.run(bulkCases, bulkOldMap, TriggerOperation.AFTER_UPDATE);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Integer queryRowsUsed = Limits.getQueryRows() - queryRowsBefore;
        Integer cpuUsed = Limits.getCpuTime() - cpuBefore;
        Test.stopTest();

        System.assertEquals(1, dmlUsed, 'A 200-record run must issue exactly one bulk Trainer UPDATE');
        System.assertEquals(1, soqlUsed, 'A 200-record run must issue exactly one Trainer SOQL query');
        System.assert(queryRowsUsed < 100, 'A 200-record run must query only the affected Trainers, not scan rows: ' + queryRowsUsed);
        System.assert(cpuUsed < 5000, 'A 200-record run must leave comfortable CPU headroom for the sync-in-trigger decision: ' + cpuUsed + 'ms');

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        Pokemon_Trainer__c secondTrainer = trainerFor(secondUser.Id);
        System.assertEquals(120, ownerTrainer.Currency__c.intValue(), '120 closes x 12 sums to 1440 raw and must clamp to the 120 daily cap');
        System.assertEquals(7200, ownerTrainer.Experience_Tokens__c.intValue(), 'XP is uncapped and per-owner: 120 closes x 60');
        System.assertEquals(120, secondTrainer.Currency__c.intValue(), 'The second owner must clamp to the cap independently');
        System.assertEquals(4800, secondTrainer.Experience_Tokens__c.intValue(), 'The uneven split proves per-owner attribution: 80 closes x 60');
    }

    @isTest static void nonAfterOpsNoOp(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;
        List<SObject> passingRecords = new List<SObject>{ workCase };
        Map<Id, SObject> passingOldMap = oldStatusMap(new List<Case>{ workCase }, 'New');

        Test.startTest();
        PokemonRewardEngine.run(passingRecords, null, TriggerOperation.BEFORE_INSERT);
        PokemonRewardEngine.run(passingRecords, passingOldMap, TriggerOperation.BEFORE_UPDATE);
        PokemonRewardEngine.run(passingRecords, null, TriggerOperation.AFTER_UNDELETE);
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'Before and undelete operations must pay zero — the after-only guard makes bottom-of-trigger placement single-fire');
        System.assertEquals(0, ownerTrainer.Experience_Tokens__c.intValue(), 'Non-after operations must pay no XP');

        PokemonRewardEngine.run(passingRecords, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'The same record and rule must pay under an after op — proving the zeros above came from the op guard, not a dead rule');
    }

    @isTest static void inactiveWrongObjectWrongOpRulesSkipped(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt inactiveRule = caseRule();
        inactiveRule.Active__c = false;
        Pokemon_Reward_Rule__mdt wrongObjectRule = caseRule();
        wrongObjectRule.SObject_API_Name__c = 'Opportunity';
        Pokemon_Reward_Rule__mdt updateOnlyRule = caseRule();
        updateOnlyRule.Run_On__c = 'Update';
        arm(new List<Pokemon_Reward_Rule__mdt>{ inactiveRule, wrongObjectRule, updateOnlyRule });
        Case insertedCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT insertedCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ insertedCase }, null, TriggerOperation.AFTER_INSERT);

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'Inactive, wrong-object, and Update-only rules must all skip an insert');

        Pokemon_Reward_Rule__mdt insertOnlyRule = caseRule();
        insertOnlyRule.Run_On__c = 'Insert';
        PokemonRewardEngine.ruleOverride = new List<Pokemon_Reward_Rule__mdt>{ insertOnlyRule };
        Case updatedCase = makeCase(ownerUser.Id, 'New', 'Mechanical', 'Web');
        INSERT updatedCase;
        updatedCase.Status = 'Closed';
        PokemonRewardEngine.run(new List<SObject>{ updatedCase }, oldStatusMap(new List<Case>{ updatedCase }, 'New'), TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'An Insert-only rule must skip an update operation');
    }

    @isTest static void awardPaysOwnerWhenAnotherUserSaves(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        User secondUser = userByLastName('PokemonRewardSecond');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        System.runAs(secondUser){
            PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        }
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'Rewards are owner-only: the record owner must be paid even when a different user performs the save');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'The owner must receive the XP regardless of who saved the record');
    }

    @isTest static void engineSwallowsErrorsAndReleasesGuard(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt brokenRule = caseRule();
        brokenRule.Multiplier_Field__c = 'No_Such_Field__c';
        arm(new List<Pokemon_Reward_Rule__mdt>{ brokenRule });
        Case brokenCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        Case cleanCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT new List<Case>{ brokenCase, cleanCase };

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ brokenCase }, null, TriggerOperation.AFTER_INSERT);
        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A rule pointing at a nonexistent field must be swallowed without award or exception');

        PokemonRewardEngine.ruleOverride = new List<Pokemon_Reward_Rule__mdt>{ caseRule() };
        PokemonRewardEngine.run(new List<SObject>{ cleanCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'The recursion guard must release in finally after a swallowed error, so the next run pays normally');
    }

    @isTest static void badRuleDoesNotStarveGoodRules(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt brokenRule = caseRule();
        brokenRule.DeveloperName = 'Broken_Field_Rule_Test';
        brokenRule.Multiplier_Field__c = 'No_Such_Field__c';
        arm(new List<Pokemon_Reward_Rule__mdt>{ brokenRule, caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A malformed rule must skip itself only — the good sibling rule in the same run must still pay');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'The good sibling rule\'s XP must survive a malformed rule in the same run');
    }

    @isTest static void nullOldMapOnUpdateIsSwallowedSilently(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_UPDATE);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'A null oldMap on the update path must be swallowed silently — a miswired hook must never throw into the subscriber\'s save');
    }

    @isTest static void yieldsSilentlyWhenNoGovernorHeadroom(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        arm(new List<Pokemon_Reward_Rule__mdt>{ caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        while(Limits.getQueries() < Limits.getLimitQueries()){
            List<User> burnedQuery = [SELECT Id FROM User LIMIT 1];
        }
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(0, ownerTrainer.Currency__c.intValue(), 'With zero SOQL headroom the engine must yield the award silently instead of throwing an uncatchable LimitException into the save');
    }

    @isTest static void nullBaseAmountsTreatedAsZero(){
        User ownerUser = userByLastName('PokemonRewardOwner');
        Pokemon_Reward_Rule__mdt nullAmountsRule = caseRule();
        nullAmountsRule.DeveloperName = 'Null_Amounts_Test';
        nullAmountsRule.Currency__c = null;
        nullAmountsRule.XP__c = null;
        arm(new List<Pokemon_Reward_Rule__mdt>{ nullAmountsRule, caseRule() });
        Case workCase = makeCase(ownerUser.Id, 'Closed', 'Mechanical', 'Web');
        INSERT workCase;

        Test.startTest();
        PokemonRewardEngine.run(new List<SObject>{ workCase }, null, TriggerOperation.AFTER_INSERT);
        Test.stopTest();

        Pokemon_Trainer__c ownerTrainer = trainerFor(ownerUser.Id);
        System.assertEquals(12, ownerTrainer.Currency__c.intValue(), 'A rule with null amounts must contribute 0 without NPE-ing the whole run — the normal rule still pays');
        System.assertEquals(60, ownerTrainer.Experience_Tokens__c.intValue(), 'The normal rule\'s XP must survive a null-amount sibling rule');
    }
}
