/* Title: PokemonSpeciesService
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Reads the Pokemon species catalog from the pokemonSpeciesSeed Static Resource and returns a single species by Pokedex number
 * Test Class: PokemonSpeciesService_Test
 * Modified: Garrett Kent - 07/05/2026 - Expose GetCatalog so minimum wild levels can be derived across the whole seed
 */
public with sharing class PokemonSpeciesService {

    static Map<String,Object> speciesCatalog;

    public static Map<String,Object> GetCatalog(){
        return LoadCatalog();
    }

    public static Map<String,Object> GetSpecies(Map<String,Object> params){
        Map<String,Object> results = new Map<String,Object>();
        results.put('status', 'success');
        try{
            if(!params.containsKey('pokedexNumber') || params.get('pokedexNumber') == null){
                results.put('status', 'error');
                results.put('message', 'ERROR in PokemonSpeciesService.GetSpecies: Pokedex Number Required');
                return results;
            }
            Integer pokedexNumber = (Integer)params.get('pokedexNumber');

            Map<String,Object> catalog = LoadCatalog();
            String pokedexKey = String.valueOf(pokedexNumber);
            if(!catalog.containsKey(pokedexKey)){
                results.put('status', 'error');
                results.put('message', 'Species not found for dex ' + pokedexNumber);
                return results;
            }
            results.put('species', catalog.get(pokedexKey));
        }
        catch(Exception error){
            results.put('status', 'error');
            results.put('message', 'ERROR in PokemonSpeciesService.GetSpecies: ' + error.getLineNumber() + ' - ' + error.getMessage());
        }
        return results;
    }

    public static Map<String,Object> GetSpecies(Integer pokedexNumber){
        return GetSpecies(new Map<String,Object>{ 'pokedexNumber' => pokedexNumber });
    }

    static Map<String,Object> LoadCatalog(){
        if(speciesCatalog == null){
            StaticResource seedResource = [SELECT Body FROM StaticResource WHERE Name = 'pokemonSpeciesSeed' LIMIT 1];
            speciesCatalog = (Map<String,Object>)JSON.deserializeUntyped(seedResource.Body.toString());
        }
        return speciesCatalog;
    }
}
