package com.registry.verg.crop.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;
import com.registry.verg.crop.service.CropService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/crop")
public class CropController {
    @Autowired
    private CropService cropService;

    @PostMapping("/v1/create")
    public ResponseEntity<CustomResponse> create(@RequestBody JsonNode cropDetails) {
        CustomResponse response = cropService.createCrop(cropDetails);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @PostMapping("/v1/search")
    public ResponseEntity<?> search(@RequestBody SearchCriteria searchCriteria) {
        CustomResponse response = cropService.searchCrop(searchCriteria);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @GetMapping("/v1/read/{id}")
    public ResponseEntity<?> read(@PathVariable String id) {
        CustomResponse response = cropService.read(id);
        return new ResponseEntity<>(response, HttpStatus.OK);
    }
}