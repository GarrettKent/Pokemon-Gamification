/* Title: pokemonCatchLogic
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Pure catch-probability, shiny, and growth-curve math for the Pokemon game. No SOQL/DML/callout.
 * Test Class: pokemonCatchLogic_Test
 * Modified: Garrett Kent - 06/21/2026 - Add RollCriticalCapture for critical-capture roll
 * Modified: Garrett Kent - 06/25/2026 - Level-banded catch difficulty (LevelCatchFactor) on ComputeCatchProbability
 * Modified: Garrett Kent - 07/04/2026 - Floor medium-slow ExpForLevel at 0 so low-level EXP is never negative
 * Modified: Garrett Kent - 07/05/2026 - Configurable catch-rate multiplier (friendly odds now, tunable in Pokemon Settings later)
 */
public with sharing class pokemonCatchLogic {

    public static Decimal ComputeCatchProbability(Integer captureRate, String ballType, Integer level){
        return ComputeCatchProbability(captureRate, ballType, level, 1.0);
    }

    public static Decimal ComputeCatchProbability(Integer captureRate, String ballType, Integer level, Decimal rateMultiplier){
        if(ballType == 'masterball') return 1.0;

        Double ballBonus = 1.0;
        if(ballType == 'greatball'){
            ballBonus = 1.5;
        }
        else if(ballType == 'ultraball'){
            ballBonus = 2.0;
        }

        Double friendliness = rateMultiplier == null || rateMultiplier <= 0 ? 1.0 : rateMultiplier.doubleValue();
        Double normalizedRate = (captureRate * ballBonus) / 765;
        Double exponent = 0.75;
        Double catchProbability = Math.pow(normalizedRate, exponent) * LevelCatchFactor(level) * friendliness;
        return catchProbability > 1 ? 1.0 : Decimal.valueOf(catchProbability);
    }

    // Higher-level wild Pokemon are harder to catch. Applied to the final probability so a band reads literally (x0.40 = 40% of the base chance). Level 1-20 is the unpenalized baseline; Master Ball short-circuits above and ignores this entirely.
    static Double LevelCatchFactor(Integer level){
        if(level == null || level <= 20) return 1.0;
        if(level <= 40) return 0.85;
        if(level <= 60) return 0.70;
        if(level <= 80) return 0.55;
        return 0.40;
    }

    public static Boolean RollShiny(Integer shinyRate){
        return Math.floor(Math.random() * shinyRate) == 0;
    }

    public static Boolean RollCriticalCapture(Integer critRate){
        return Math.floor(Math.random() * critRate) == 0;
    }

    public static Boolean RollFlee(Decimal fleeChancePercent){
        if(fleeChancePercent == null || fleeChancePercent <= 0) return false;
        if(fleeChancePercent >= 100) return true;
        return Decimal.valueOf(Math.random() * 100) < fleeChancePercent;
    }

    public static Long ExpForLevel(String growthRate, Integer level){
        Double levelValue = (Double)level;
        Double levelCubed = levelValue * levelValue * levelValue;

        if(growthRate == 'fast') return (Long)Math.floor(4 * levelCubed / 5);
        if(growthRate == 'medium') return (Long)Math.floor(levelCubed);
        if(growthRate == 'medium-slow'){
            Long mediumSlowExp = (Long)Math.floor(6.0 / 5.0 * levelCubed - 15 * levelValue * levelValue + 100 * levelValue - 140);
            return mediumSlowExp < 0 ? 0 : mediumSlowExp;
        }
        if(growthRate == 'slow') return (Long)Math.floor(5 * levelCubed / 4);
        if(growthRate == 'erratic') return ErraticExp(levelValue, levelCubed, level);
        if(growthRate == 'fluctuating') return FluctuatingExp(levelValue, levelCubed, level);
        return 0;
    }

    public static Integer LevelForExp(String growthRate, Long exp){
        Integer resolvedLevel = 1;
        for(Integer candidateLevel = 1; candidateLevel <= 100; candidateLevel++){
            if(ExpForLevel(growthRate, candidateLevel) > exp) break;
            resolvedLevel = candidateLevel;
        }
        return resolvedLevel;
    }

    static Long ErraticExp(Double levelValue, Double levelCubed, Integer level){
        if(level < 50) return (Long)Math.floor(levelCubed * (100 - levelValue) / 50);
        if(level < 68) return (Long)Math.floor(levelCubed * (150 - levelValue) / 100);
        if(level < 98) return (Long)Math.floor(levelCubed * Math.floor((1911 - 10 * levelValue) / 3) / 500);
        return (Long)Math.floor(levelCubed * (160 - levelValue) / 100);
    }

    static Long FluctuatingExp(Double levelValue, Double levelCubed, Integer level){
        if(level < 15) return (Long)Math.floor(levelCubed * (Math.floor((levelValue + 1) / 3) + 24) / 50);
        if(level < 36) return (Long)Math.floor(levelCubed * (levelValue + 14) / 50);
        return (Long)Math.floor(levelCubed * (Math.floor(levelValue / 2) + 32) / 50);
    }
}
