/* Title: PokemonSpeciesService_Test
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Tests PokemonSpeciesService against the deployed pokemonSpeciesSeed Static Resource
 * Test Class: PokemonSpeciesService_Test
 */
@isTest
private class PokemonSpeciesService_Test {

    @isTest static void testGetLegendarySpecies(){
        Test.startTest();
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(new Map<String,Object>{ 'pokedexNumber' => 150 });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Dex 150 should resolve successfully');
        Map<String,Object> species = (Map<String,Object>)results.get('species');
        System.assertEquals('Mewtwo', species.get('name'), 'Dex 150 should be Mewtwo');
        System.assertEquals(3, (Integer)species.get('captureRate'), 'Mewtwo capture rate should be 3');
        System.assertEquals('slow', species.get('growthRate'), 'Mewtwo growth rate should be slow');
        System.assertEquals(true, species.get('isLegendary'), 'Mewtwo should be legendary');
    }

    @isTest static void testGetDualTypeSpecies(){
        Test.startTest();
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(new Map<String,Object>{ 'pokedexNumber' => 1 });
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Dex 1 should resolve successfully');
        Map<String,Object> species = (Map<String,Object>)results.get('species');
        System.assertEquals('Bulbasaur', species.get('name'), 'Dex 1 should be Bulbasaur');
        System.assertEquals('poison', species.get('type2'), 'Bulbasaur second type should be poison');
    }

    @isTest static void testIntegerOverload(){
        Test.startTest();
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(150);
        Test.stopTest();

        System.assertEquals('success', results.get('status'), 'Integer overload should resolve successfully');
        Map<String,Object> species = (Map<String,Object>)results.get('species');
        System.assertEquals('Mewtwo', species.get('name'), 'Integer overload should return Mewtwo for 150');
    }

    @isTest static void testMissingSpecies(){
        Test.startTest();
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(new Map<String,Object>{ 'pokedexNumber' => 99999 });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Unknown dex should return an error');
        System.assert(String.valueOf(results.get('message')).contains('99999'), 'Error message should reference the missing dex');
    }

    @isTest static void testNullParam(){
        Test.startTest();
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(new Map<String,Object>{ 'pokedexNumber' => null });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'Null pokedex number should return an error');
    }

    @isTest static void testNonIntegerParamHandledGracefully(){
        Test.startTest();
        // A non-integer pokedexNumber forces a cast TypeException inside the try, exercising the catch path.
        Map<String,Object> results = PokemonSpeciesService.GetSpecies(new Map<String,Object>{ 'pokedexNumber' => 'not-a-number' });
        Test.stopTest();

        System.assertEquals('error', results.get('status'), 'A bad pokedexNumber should be caught and returned as an error');
        System.assert(String.valueOf(results.get('message')).contains('PokemonSpeciesService'), 'Caught error message should identify the service');
    }
}
