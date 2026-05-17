package com.registry.verg.leads.service.impl;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.datastax.oss.driver.api.core.uuid.Uuids;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.registry.verg.core.cache.CacheService;
import com.registry.verg.core.dto.CustomResponse;
import com.registry.verg.core.dto.RespParam;
import com.registry.verg.core.elasticsearch.dto.SearchCriteria;
import com.registry.verg.core.elasticsearch.dto.SearchResult;
import com.registry.verg.core.elasticsearch.service.ESUtilService;
import com.registry.verg.core.exception.CustomException;
import com.registry.verg.core.util.Constants;
import com.registry.verg.core.util.PayloadValidation;
import com.registry.verg.core.util.VergProperties;
import com.registry.verg.core.util.PrimaryKeyUtil;
import com.registry.verg.leads.entity.LeadsEntity;
import com.registry.verg.leads.repository.LeadsRepository;
import com.registry.verg.leads.service.LeadsService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.sql.Timestamp;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
@Slf4j
public class LeadsServiceImpl implements LeadsService {
    @Autowired
    private PayloadValidation payloadValidation;

    @Autowired
    private PrimaryKeyUtil primaryKeyUtil;

    @Autowired
    private LeadsRepository leadsRepository;

    @Autowired
    private ESUtilService esUtilService;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private CacheService cacheService;

    @Autowired
    private RedisTemplate<String, SearchResult> redisTemplate;

    @Autowired
    private VergProperties vergProperties;

    private Logger logger = LoggerFactory.getLogger(LeadsServiceImpl.class);

    @Value("${spring.redis.cacheTtl}")
    private long searchResultRedisTtl;

    @Override
    public CustomResponse createLeads(JsonNode leadsEntity) {
        log.info("LeadsServiceImpl::createLeads:entered the method: " + leadsEntity);
        CustomResponse response = new CustomResponse();
        payloadValidation.validatePayload(Constants.LEADS_VALIDATION_FILE_JSON, leadsEntity);

        log.debug("LeadsServiceImpl::createLeads:validated the payload");
        try {
            log.info("LeadsServiceImpl::createLeads:creating leads");
            LeadsEntity leadsEntity1 = new LeadsEntity();
            // Generate Primary Key
            String primaryID = primaryKeyUtil.generateKey(Constants.LEADS_VALIDATION_FILE_JSON);
            leadsEntity1.setLeadsId(primaryID);
            // Create Parameters like createdDate / updateDate / Data and Status
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            leadsEntity1.setCreatedOn(currentTime);
            leadsEntity1.setUpdatedOn(currentTime);
            leadsEntity1.setStatus(Constants.ACTIVE);
            leadsEntity1.setData(leadsEntity);

            leadsRepository.save(leadsEntity1);

            log.info("LeadsServiceImpl::createLeads::persisted leads in postgres");
            ObjectNode jsonNode = objectMapper.createObjectNode();
            // jsonNode.put("LeadsID",
            // leadsEntity.get(Constants.LEADS_ID_RQST).asText());
            jsonNode.put("status", Constants.ACTIVE);
            jsonNode.setAll((ObjectNode) leadsEntity);
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.addDocument(Constants.LEADS_INDEX_NAME, Constants.INDEX_TYPE,
                    String.valueOf(primaryID), map, vergProperties.getElasticLeadsJsonPath());
            cacheService.putCache(primaryID, jsonNode);
            response.setMessage(Constants.SUCCESSFULLY_CREATED);
            map.put(Constants.LEADS_ID_RQST, primaryID);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("LeadsServiceImpl::createLeads::persisted leads in Verg");
            return response;

        } catch (Exception e) {
            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Override
    public CustomResponse searchLeads(SearchCriteria searchCriteria) {
        log.info("LeadsServiceImpl::searchLeads");
        CustomResponse response = new CustomResponse();
        SearchResult searchResult = redisTemplate.opsForValue()
                .get(generateRedisJwtTokenKey(searchCriteria));
        if (searchResult != null) {
            log.info("LeadsServiceImpl::searchLeads: leads search result fetched from redis");
            response.getResult().put(Constants.RESULT, searchResult);
            createSuccessResponse(response);
            return response;
        }
        String searchString = searchCriteria.getSearchString();
        if (searchString != null && searchString.length() < 2) {
            createErrorResponse(response, "Minimum 3 characters are required to search",
                    HttpStatus.BAD_REQUEST,
                    Constants.FAILED_CONST);
            return response;
        }
        try {
            searchResult = esUtilService.searchDocuments(Constants.LEADS_INDEX_NAME, searchCriteria);
            response.getResult().put(Constants.RESULT, searchResult);
            createSuccessResponse(response);
            return response;
        } catch (Exception e) {
            createErrorResponse(response, e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR,
                    Constants.FAILED_CONST);
            redisTemplate.opsForValue()
                    .set(generateRedisJwtTokenKey(searchCriteria), searchResult, searchResultRedisTtl,
                            TimeUnit.SECONDS);
            return response;
        }
    }

    @Override
    public CustomResponse assignLeads(JsonNode leadsEntity, String token) {
        return null;
    }

    @Override
    public CustomResponse read(String id) {
        log.info("LeadsServiceImpl::read:inside the method");
        CustomResponse response = new CustomResponse();
        if (StringUtils.isEmpty(id)) {
            response.setResponseCode(HttpStatus.INTERNAL_SERVER_ERROR);
            response.setMessage(Constants.ID_NOT_FOUND);
            return response;
        }
        try {
            String cachedJson = cacheService.getCache(id);
            if (StringUtils.isNotEmpty(cachedJson)) {
                log.info("LeadsServiceImpl::read:Record coming from redis cache");
                response.setMessage(Constants.SUCCESSFULLY_READING);
                response
                        .getResult()
                        .put(Constants.RESULT, objectMapper.readValue(cachedJson, new TypeReference<Object>() {
                        }));
            } else {
                Optional<LeadsEntity> entityOptional = leadsRepository.findById(id);
                if (entityOptional.isPresent()) {
                    LeadsEntity leadsEntity = entityOptional.get();
                    cacheService.putCache(id, leadsEntity.getData());
                    log.info("LeadsServiceImpl::read:Record coming from postgres db");
                    response.setMessage(Constants.SUCCESSFULLY_READING);
                    response
                            .getResult()
                            .put(Constants.RESULT,
                                    objectMapper.convertValue(
                                            leadsEntity.getData(), new TypeReference<Object>() {
                                            }));
                } else {
                    response.setResponseCode(HttpStatus.NOT_FOUND);
                    response.setMessage(Constants.INVALID_ID);
                }
            }
        } catch (Exception e) {
            throw new CustomException(Constants.ERROR, "error while processing",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
        return response;
    }

    @Override
    public CustomResponse delete(String id) {
        return null;
    }

    @Override
    public CustomResponse initiateLead(JsonNode leadsEntity) {
        log.info("LeadsServiceImpl::initiateLead:entered the method: " + leadsEntity);
        CustomResponse response = new CustomResponse();
        payloadValidation.validatePayload(Constants.LEADS_VALIDATION_FILE_JSON, leadsEntity);

        log.debug("LeadsServiceImpl::initiateLead:validated the payload");
        try {
            log.info("LeadsServiceImpl::initiateLead:initiating leads");
            LeadsEntity leadsEntity1 = new LeadsEntity();
            // Generate Primary Key
            String primaryID = primaryKeyUtil.generateKey(Constants.LEADS_VALIDATION_FILE_JSON);
            leadsEntity1.setLeadsId(primaryID);
            // Create Parameters like createdDate / updateDate / Data and Status
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            leadsEntity1.setCreatedOn(currentTime);
            leadsEntity1.setUpdatedOn(currentTime);
            leadsEntity1.setStatus(Constants.INITIATED);
            leadsEntity1.setData(leadsEntity);

            leadsRepository.save(leadsEntity1);

            log.info("LeadsServiceImpl::initiateLead::persisted leads in postgres");
            ObjectNode jsonNode = objectMapper.createObjectNode();
            // jsonNode.put("LeadsID",
            // leadsEntity.get(Constants.LEADS_ID_RQST).asText());
            jsonNode.put("status", Constants.INITIATED);
            jsonNode.setAll((ObjectNode) leadsEntity);
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.addDocument(Constants.LEADS_INDEX_NAME, Constants.INDEX_TYPE,
                    String.valueOf(primaryID), map, vergProperties.getElasticLeadsJsonPath());
            cacheService.putCache(primaryID, jsonNode);
            response.setMessage(Constants.SUCCESSFULLY_CREATED);
            map.put(Constants.LEADS_ID_RQST, primaryID);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("LeadsServiceImpl::initiateLead::persisted leads in Verg");
            return response;

        } catch (Exception e) {
            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Override
    public CustomResponse qualifyLead(String leads_id, String status) {
        log.info("LeadsServiceImpl::qualifyLead:entered the method: leads_id={}, status={}", leads_id, status);
        CustomResponse response = new CustomResponse();

        // 1. Validate status param is either QUALIFIED or DISQUALIFIED
        if (!Constants.QUALIFIED.equals(status) && !Constants.DISQUALIFIED.equals(status)) {
            throw new CustomException("Invalid status",
                    "Status must be either QUALIFIED or DISQUALIFIED",
                    HttpStatus.BAD_REQUEST);
        }

        // 2. Find lead by ID from Postgres
        Optional<LeadsEntity> entityOptional = leadsRepository.findById(leads_id);
        if (entityOptional.isEmpty()) {
            throw new CustomException("Lead not found",
                    "No lead found with id: " + leads_id,
                    HttpStatus.NOT_FOUND);
        }

        LeadsEntity leadsEntity = entityOptional.get();

        // 3. Check current status == INITIATED
        if (!Constants.INITIATED.equals(leadsEntity.getStatus())) {
            throw new CustomException("Invalid status transition",
                    "Lead status must be INITIATED to qualify/disqualify. Current status: " + leadsEntity.getStatus(),
                    HttpStatus.BAD_REQUEST);
        }

        try {
            // 4. Update status and updatedOn timestamp
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            leadsEntity.setStatus(status);
            leadsEntity.setUpdatedOn(currentTime);

            // 5. Save to Postgres
            leadsRepository.save(leadsEntity);
            log.info("LeadsServiceImpl::qualifyLead::updated lead status in postgres");

            // 6. Update Elasticsearch document
            ObjectNode jsonNode = objectMapper.createObjectNode();
            // jsonNode.put("LeadsID", leads_id);
            jsonNode.put("status", status);
            if (leadsEntity.getData() != null) {
                jsonNode.setAll((ObjectNode) leadsEntity.getData());
            }
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.updateDocument(Constants.LEADS_INDEX_NAME, Constants.INDEX_TYPE,
                    leads_id, map, vergProperties.getElasticLeadsJsonPath());

            // 7. Update Redis cache
            cacheService.putCache(leads_id, jsonNode);

            // 8. Return success response
            response.setMessage(Constants.SUCCESSFULLY_UPDATED);
            map.put(Constants.LEADS_ID_RQST, leads_id);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("LeadsServiceImpl::qualifyLead::lead status updated to {} in Verg", status);
            return response;

        } catch (CustomException e) {
            throw e;
        } catch (Exception e) {
            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Override
    public CustomResponse processLead(String leads_id, String status) {
        log.info("LeadsServiceImpl::processLead:entered the method: leads_id={}, status={}", leads_id, status);
        CustomResponse response = new CustomResponse();

        // 1. Validate status param is either PROCESSED or REJECTED
        if (!Constants.PROCESSED.equals(status) && !Constants.REJECTED.equals(status)) {
            throw new CustomException("Invalid status",
                    "Status must be either PROCESSED or REJECTED",
                    HttpStatus.BAD_REQUEST);
        }

        // 2. Find lead by ID from Postgres
        Optional<LeadsEntity> entityOptional = leadsRepository.findById(leads_id);
        if (entityOptional.isEmpty()) {
            throw new CustomException("Lead not found",
                    "No lead found with id: " + leads_id,
                    HttpStatus.NOT_FOUND);
        }

        LeadsEntity leadsEntity = entityOptional.get();

        // 3. Check current status == QUALIFIED
        if (!Constants.QUALIFIED.equals(leadsEntity.getStatus())) {
            throw new CustomException("Invalid status transition",
                    "Lead status must be QUALIFIED to process. Current status: " + leadsEntity.getStatus(),
                    HttpStatus.BAD_REQUEST);
        }

        try {
            // 4. Update status and updatedOn timestamp
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            leadsEntity.setStatus(status);
            leadsEntity.setUpdatedOn(currentTime);

            // 5. Save to Postgres
            leadsRepository.save(leadsEntity);
            log.info("LeadsServiceImpl::processLead::updated lead status in postgres");

            // 6. Update Elasticsearch document
            ObjectNode jsonNode = objectMapper.createObjectNode();
            // jsonNode.put("LeadsID", leads_id);
            jsonNode.put("status", status);
            if (leadsEntity.getData() != null) {
                jsonNode.setAll((ObjectNode) leadsEntity.getData());
            }
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.updateDocument(Constants.LEADS_INDEX_NAME, Constants.INDEX_TYPE,
                    leads_id, map, vergProperties.getElasticLeadsJsonPath());

            // 7. Update Redis cache
            cacheService.putCache(leads_id, jsonNode);

            // 8. Return success response
            response.setMessage(Constants.SUCCESSFULLY_UPDATED);
            map.put(Constants.LEADS_ID_RQST, leads_id);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("LeadsServiceImpl::processLead::lead status updated to {} in Verg", status);
            return response;

        } catch (CustomException e) {
            throw e;
        } catch (Exception e) {
            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    public void createSuccessResponse(CustomResponse response) {
        response.setParams(new RespParam());
        response.getParams().setStatus(Constants.SUCCESS);
        response.setResponseCode(HttpStatus.OK);
    }

    public String generateRedisJwtTokenKey(Object requestPayload) {
        if (requestPayload != null) {
            try {
                String reqJsonString = objectMapper.writeValueAsString(requestPayload);
                return JWT.create()
                        .withClaim(Constants.REQUEST_PAYLOAD, reqJsonString)
                        .sign(Algorithm.HMAC256(Constants.JWT_SECRET_KEY));
            } catch (JsonProcessingException e) {
                // logger.error("Error occurred while converting json object to json string",
                // e);
            }
        }
        return "";
    }

    public void createErrorResponse(
            CustomResponse response, String errorMessage, HttpStatus httpStatus, String status) {
        response.setParams(new RespParam());
        response.getParams().setStatus(status);
        response.setResponseCode(httpStatus);
    }
}