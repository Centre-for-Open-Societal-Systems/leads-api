package com.registry.verg.leads.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;


public interface LeadsService {

    CustomResponse createLeads(JsonNode leadsEntity);

    CustomResponse searchLeads(SearchCriteria searchCriteria);

    CustomResponse assignLeads(JsonNode leadsEntity, String token);

    CustomResponse read(String id);

    CustomResponse delete(String id);

    CustomResponse initiateLead(JsonNode leadsEntity);

    CustomResponse qualifyLead(String leads_id, String status);

    CustomResponse processLead(String leads_id, String status);
}