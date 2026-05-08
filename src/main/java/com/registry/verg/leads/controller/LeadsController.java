package com.registry.verg.leads.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;
import com.registry.verg.leads.service.LeadsService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/leads")
public class LeadsController {
    @Autowired
    private LeadsService leadsService;

    @PostMapping("/v1/create")
    public ResponseEntity<CustomResponse> create(@RequestBody JsonNode leadsDetails) {
        CustomResponse response = leadsService.createLeads(leadsDetails);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @PostMapping("/v1/search")
    public ResponseEntity<?> search(@RequestBody SearchCriteria searchCriteria) {
        CustomResponse response = leadsService.searchLeads(searchCriteria);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @GetMapping("/v1/read/{id}")
    public ResponseEntity<?> read(@PathVariable String id) {
        CustomResponse response = leadsService.read(id);
        return new ResponseEntity<>(response, HttpStatus.OK);
    }

    @PostMapping("/v1/initiate")
    public ResponseEntity<CustomResponse> initiateLead(@RequestBody JsonNode leadsDetails) {
        CustomResponse response = leadsService.initiateLead(leadsDetails);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    @PutMapping("/v1/qualify")
    public ResponseEntity<CustomResponse> qualifyLead(@RequestBody JsonNode qualifyRequest) {
        String leadsId = qualifyRequest.get("leads_id").asText();
        String status = qualifyRequest.get("status").asText();
        CustomResponse response = leadsService.qualifyLead(leadsId, status);
        return new ResponseEntity<>(response, response.getResponseCode());
    }


    @PutMapping("/v1/process")
    public ResponseEntity<CustomResponse> processLead(@RequestBody JsonNode processRequest) {
        String leadsId = processRequest.get("leads_id").asText();
        String status = processRequest.get("status").asText();
        CustomResponse response = leadsService.processLead(leadsId, status);
        return new ResponseEntity<>(response, response.getResponseCode());
    }

    
}