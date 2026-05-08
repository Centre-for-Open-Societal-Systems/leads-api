package com.registry.verg.crop.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;


public interface CropService {

    CustomResponse createCrop(JsonNode cropEntity);

    CustomResponse searchCrop(SearchCriteria searchCriteria);

    CustomResponse assignCrop(JsonNode cropEntity, String token);

    CustomResponse read(String id);

    CustomResponse delete(String id);
}