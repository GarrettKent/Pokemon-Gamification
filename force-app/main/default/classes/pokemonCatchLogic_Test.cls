/* Title: pokemonCatchLogic_Test
 * Created By: Garrett Kent - 06/21/2026
 * Purpose: Tests the pure catch-math helpers in pokemonCatchLogic — catch probability, shiny/flee/critical-capture rolls, and the EXP growth curves.
 * Test Class: pokemonCatchLogic_Test
 * Modified: Garrett Kent - 07/05/2026 - Cover the configurable catch-rate multiplier overload
 */
@isTest
private class pokemonCatchLogic_Test {

    @isTest static void computeCatchProbabilityMatchesKnownValues() {
        Decimal mewtwoChance = pokemonCatchLogic.ComputeCatchProbability(3, 'pokeball', 5);
        Decimal snorlaxChance = pokemonCatchLogic.ComputeCatchProbability(25, 'greatball', 5);
        Decimal caterpieChance = pokemonCatchLogic.ComputeCatchProbability(255, 'ultraball', 5);

        System.assert(Math.abs(mewtwoChance.doubleValue() - 0.01567) < 0.0005, 'Mewtwo catch probability out of range: ' + mewtwoChance);
        System.assert(Math.abs(snorlaxChance.doubleValue() - 0.1042) < 0.0005, 'Snorlax catch probability out of range: ' + snorlaxChance);
        System.assert(Math.abs(caterpieChance.doubleValue() - 0.7378) < 0.0005, 'Caterpie catch probability out of range: ' + caterpieChance);
    }

    @isTest static void masterballAlwaysCatches() {
        Decimal masterballChance = pokemonCatchLogic.ComputeCatchProbability(3, 'masterball', 100);
        System.assertEquals(1.0, masterballChance.doubleValue(), 'Master Ball should always return a guaranteed catch, even for a high-level Pokemon');
    }

    @isTest static void catchProbabilityClampsAtOne() {
        Decimal clampedChance = pokemonCatchLogic.ComputeCatchProbability(255, 'ultraball', 5);
        Decimal hugeRateChance = pokemonCatchLogic.ComputeCatchProbability(1000, 'ultraball', 5);
        System.assert(clampedChance.doubleValue() <= 1.0, 'Catch probability must never exceed 1.0');
        System.assertEquals(1.0, hugeRateChance.doubleValue(), 'Very high capture rate times bonus must clamp to 1.0');
    }

    @isTest static void levelFactorScalesCatchProbabilityAcrossBands() {
        // Band 1 (level 1-20) is the unpenalized chance; each higher band multiplies it down by a fixed factor.
        Decimal baseChance = pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 10);

        // A null level and the top of band 1 both stay at the baseline.
        System.assertEquals(baseChance.doubleValue(), pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', null).doubleValue(), 'A null level must use the unpenalized baseline');
        System.assertEquals(baseChance.doubleValue(), pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 20).doubleValue(), 'Level 20 is still band 1 (x1.0)');

        // Both edges of every higher band apply that band's multiplier to the base chance.
        assertBandFactor(baseChance, 21, 0.85);
        assertBandFactor(baseChance, 40, 0.85);
        assertBandFactor(baseChance, 41, 0.70);
        assertBandFactor(baseChance, 60, 0.70);
        assertBandFactor(baseChance, 61, 0.55);
        assertBandFactor(baseChance, 80, 0.55);
        assertBandFactor(baseChance, 81, 0.40);
        assertBandFactor(baseChance, 100, 0.40);
    }

    static void assertBandFactor(Decimal baseChance, Integer level, Decimal expectedFactor) {
        Decimal bandChance = pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', level);
        Double expected = baseChance.doubleValue() * expectedFactor.doubleValue();
        System.assert(Math.abs(bandChance.doubleValue() - expected) < 0.0005, 'Level ' + level + ' should scale catch probability by ' + expectedFactor + ' (expected ' + expected + ', got ' + bandChance + ')');
    }

    @isTest static void unknownBallUsesBaseBonus() {
        Decimal unknownBallChance = pokemonCatchLogic.ComputeCatchProbability(3, 'fancyball', 5);
        Decimal pokeballChance = pokemonCatchLogic.ComputeCatchProbability(3, 'pokeball', 5);
        System.assertEquals(pokeballChance.doubleValue(), unknownBallChance.doubleValue(), 'Unknown ball should fall back to base bonus of 1.0');
    }

    @isTest static void catchRateMultiplierScalesTheOdds() {
        // The friendly multiplier scales the final probability: Caterpie + pokeball at 1.5x is ~0.4387 * 1.5 = ~0.658.
        Decimal baseChance = pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 5);
        Decimal friendlyChance = pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 5, 1.5);
        System.assert(Math.abs(friendlyChance.doubleValue() - baseChance.doubleValue() * 1.5) < 0.0005, 'A 1.5x multiplier should scale the base probability: ' + friendlyChance);

        // Null and non-positive multipliers fall back to the base formula; big multipliers still clamp at 1.0.
        System.assertEquals(baseChance.doubleValue(), pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 5, null).doubleValue(), 'A null multiplier must use the base formula');
        System.assertEquals(baseChance.doubleValue(), pokemonCatchLogic.ComputeCatchProbability(255, 'pokeball', 5, 0).doubleValue(), 'A zero multiplier must fall back to the base formula');
        System.assertEquals(1.0, pokemonCatchLogic.ComputeCatchProbability(255, 'ultraball', 5, 3).doubleValue(), 'A big multiplier must clamp the probability at 1.0');
    }

    @isTest static void rollShinyWithRateOneAlwaysTrue() {
        System.assertEquals(true, pokemonCatchLogic.RollShiny(1), 'A shiny rate of 1 must always roll shiny');
    }

    @isTest static void testRollCriticalCapture() {
        System.assertEquals(true, pokemonCatchLogic.RollCriticalCapture(1), 'A critical capture rate of 1 must always crit');
    }

    @isTest static void rollShinyReturnsBoolean() {
        // S5.8 moved the shiny roll to fire only inside the catch branch; the math itself is unchanged.
        Object shinyResult = pokemonCatchLogic.RollShiny(512);
        System.assert(shinyResult instanceof Boolean, 'RollShiny should always return a Boolean');
    }

    @isTest static void rollFleeBoundariesAreDeterministic() {
        System.assertEquals(false, pokemonCatchLogic.RollFlee(0), 'A 0% flee chance must never flee');
        System.assertEquals(false, pokemonCatchLogic.RollFlee(null), 'A null flee chance must never flee');
        System.assertEquals(true, pokemonCatchLogic.RollFlee(100), 'A 100% flee chance must always flee');
    }

    @isTest static void rollFleeReturnsBoolean() {
        Object fleeResult = pokemonCatchLogic.RollFlee(12.5);
        System.assert(fleeResult instanceof Boolean, 'RollFlee should always return a Boolean');
    }

    @isTest static void expForLevelMatchesCanonicalTotalsAtLevel100() {
        System.assertEquals(800000L, pokemonCatchLogic.ExpForLevel('fast', 100), 'Fast curve total at level 100');
        System.assertEquals(1000000L, pokemonCatchLogic.ExpForLevel('medium', 100), 'Medium curve total at level 100');
        System.assertEquals(1059860L, pokemonCatchLogic.ExpForLevel('medium-slow', 100), 'Medium-slow curve total at level 100');
        System.assertEquals(1250000L, pokemonCatchLogic.ExpForLevel('slow', 100), 'Slow curve total at level 100');
        System.assertEquals(600000L, pokemonCatchLogic.ExpForLevel('erratic', 100), 'Erratic curve total at level 100');
        System.assertEquals(1640000L, pokemonCatchLogic.ExpForLevel('fluctuating', 100), 'Fluctuating curve total at level 100');
    }

    @isTest static void levelForExpRoundTripsAtLevel50() {
        List<String> growthRates = new List<String>{'fast', 'medium', 'medium-slow', 'slow', 'erratic', 'fluctuating'};
        for (String growthRate : growthRates) {
            Long expAtFifty = pokemonCatchLogic.ExpForLevel(growthRate, 50);
            Integer resolvedLevel = pokemonCatchLogic.LevelForExp(growthRate, expAtFifty);
            System.assertEquals(50, resolvedLevel, 'Round trip should resolve to level 50 for growth rate ' + growthRate);
        }
    }

    @isTest static void levelForExpFloorsAndCaps() {
        System.assertEquals(1, pokemonCatchLogic.LevelForExp('medium', 0), 'Zero experience should floor at level 1');
        System.assertEquals(100, pokemonCatchLogic.LevelForExp('medium', 999999999L), 'Experience beyond level 100 should cap at level 100');
    }

    @isTest static void expForLevelUnknownGrowthRateReturnsZero() {
        System.assertEquals(0L, pokemonCatchLogic.ExpForLevel('not-a-real-curve', 50), 'An unrecognized growth rate should fall through to 0');
    }

    @isTest static void expForLevelMediumSlowNeverNegative() {
        // The medium-slow polynomial dips below 0 at low levels (n=1 raw is -54); it must floor at 0 so stored EXP is never negative.
        System.assertEquals(0L, pokemonCatchLogic.ExpForLevel('medium-slow', 1), 'Medium-slow EXP at level 1 must floor at 0, never negative');
        System.assert(pokemonCatchLogic.ExpForLevel('medium-slow', 1) >= 0, 'Medium-slow EXP must never be negative');

        // A normal higher level still returns its expected positive canonical value.
        System.assertEquals(1059860L, pokemonCatchLogic.ExpForLevel('medium-slow', 100), 'Medium-slow EXP at level 100 must be unchanged');
    }
}