package com.registry.verg.vergsample.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;
import com.registry.verg.vergsample.service.SampleService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/sample")
public class SampleController {
    @Autowired
    private SampleService sampleService;

    @PostMapping("/v1/create")
    public ResponseEntity<CustomResponse> create(@RequestBody JsonNode sampleDetails) {
        CustomResponse response = sampleService.createSample(sampleDetails);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @PostMapping("/v1/search")
    public ResponseEntity<?> search(@RequestBody SearchCriteria searchCriteria) {
        CustomResponse response = sampleService.searchSample(searchCriteria);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @GetMapping("/v1/read/{id}")
    public ResponseEntity<?> read(@PathVariable String id) {
        CustomResponse response = sampleService.read(id);
        return new ResponseEntity<>(response, HttpStatus.OK);
    }
}
