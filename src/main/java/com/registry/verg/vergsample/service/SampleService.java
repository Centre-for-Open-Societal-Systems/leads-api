package com.registry.verg.vergsample.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;


public interface SampleService {

    CustomResponse createSample(JsonNode sampleEntity);

    CustomResponse searchSample(SearchCriteria searchCriteria);

    CustomResponse assignSample(JsonNode sampleEntity, String token);

    CustomResponse read(String id);

    CustomResponse delete(String id);
}