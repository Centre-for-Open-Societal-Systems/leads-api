package com.registry.verg.vergsample.service.impl;

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
import com.registry.verg.vergsample.entity.SampleEntity;
import com.registry.verg.vergsample.repository.SampleRepository;
import com.registry.verg.vergsample.service.SampleService;
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
public class SampleServiceImpl implements SampleService {
    @Autowired
    private PayloadValidation payloadValidation;

    @Autowired
    private SampleRepository sampleRepository;

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

    private Logger logger = LoggerFactory.getLogger(SampleServiceImpl.class);

    @Value("${spring.redis.cacheTtl}")
    private long searchResultRedisTtl;

    @Override
    public CustomResponse createSample(JsonNode sampleEntity) {
        log.info("InterestServiceImpl::createInterest:entered the method: " + sampleEntity);
        CustomResponse response = new CustomResponse();
        payloadValidation.validatePayload(Constants.SAMPLE_VALIDATION_FILE_JSON, sampleEntity);


        log.debug("InterestServiceImpl::createInterest:validated the payload");
        try {
            log.info("InterestServiceImpl::createInterest:creating interest");
            SampleEntity sampleEntity1 = new SampleEntity();
            // Generate Primary Key
            UUID interestIdUuid = Uuids.timeBased();
            String primaryID = String.valueOf(interestIdUuid);
            sampleEntity1.setSampleId(primaryID);
            // Create Parameters like createdDate / updateDate / Data and Status
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            sampleEntity1.setCreatedOn(currentTime);
            sampleEntity1.setUpdatedOn(currentTime);
            sampleEntity1.setStatus(Constants.ACTIVE);
            sampleEntity1.setData(sampleEntity);

            sampleRepository.save(sampleEntity1);

            log.info("SampleServiceImpl::createSample::persisted sample in postgres");
            ObjectNode jsonNode = objectMapper.createObjectNode();
            jsonNode.put("SampleID",
                    sampleEntity.get(Constants.SAMPLE_ID_RQST).asText());
            jsonNode.setAll((ObjectNode) sampleEntity);
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.addDocument(Constants.INTEREST_INDEX_NAME, Constants.INDEX_TYPE,
                    String.valueOf(primaryID), map, vergProperties.getElasticSampleJsonPath());
            cacheService.putCache(primaryID, jsonNode);
            response.setMessage(Constants.SUCCESSFULLY_CREATED);
            map.put(Constants.SAMPLE_ID_RQST, primaryID);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("SampleServiceImpl::createSample::persited sample in Verg");
            return response;

        } catch (Exception e) {

            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Override
    public CustomResponse searchSample(SearchCriteria searchCriteria) {
        log.info("SampleServiceImpl::searchDemand");
        CustomResponse response = new CustomResponse();
        SearchResult searchResult = redisTemplate.opsForValue()
                .get(generateRedisJwtTokenKey(searchCriteria));
        if (searchResult != null) {
            log.info("SampleServiceImpl::searchSample: sample search result fetched from redis");
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
            searchResult =
                    esUtilService.searchDocuments(Constants.INTEREST_INDEX_NAME, searchCriteria);
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
    public CustomResponse assignSample(JsonNode sampleEntity, String token) {
        return null;
    }

    @Override
    public CustomResponse read(String id) {
        log.info("InterestServiceImpl::read:inside the method");
        CustomResponse response = new CustomResponse();
        if (StringUtils.isEmpty(id)) {
            //logger.error("InterestServiceImpl::read:Id not found");
            response.setResponseCode(HttpStatus.INTERNAL_SERVER_ERROR);
            response.setMessage(Constants.ID_NOT_FOUND);
            return response;
        }
        try {
            String cachedJson = cacheService.getCache(id);
            if (StringUtils.isNotEmpty(cachedJson)) {
                log.info("InterestServiceImpl::read:Record coming from redis cache");
                response.setMessage(Constants.SUCCESSFULLY_READING);
                response
                        .getResult()
                        .put(Constants.RESULT, objectMapper.readValue(cachedJson, new TypeReference<Object>() {
                        }));
            } else {
                Optional<SampleEntity> entityOptional = sampleRepository.findById(id);
                if (entityOptional.isPresent()) {
                    SampleEntity sampleEntity = entityOptional.get();
                    cacheService.putCache(id, sampleEntity.getData());
                    log.info("InterestServiceImpl::read:Record coming from postgres db");
                    response.setMessage(Constants.SUCCESSFULLY_READING);
                    response
                            .getResult()
                            .put(Constants.RESULT,
                                    objectMapper.convertValue(
                                            sampleEntity.getData(), new TypeReference<Object>() {
                                            }));
                } else {
                    //logger.error("Invalid Id: {}", id);
                    response.setResponseCode(HttpStatus.NOT_FOUND);
                    response.setMessage(Constants.INVALID_ID);
                }
            }
        } catch (Exception e) {
            //logger.error("Error while mapping JSON for id {}: {}", id, e.getMessage(), e);
            throw new CustomException(Constants.ERROR, "error while processing",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
        return response;
    }

    @Override
    public CustomResponse delete(String id) {
        return null;
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
                //logger.error("Error occurred while converting json object to json string", e);
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
