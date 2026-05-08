package com.registry.verg.crop.service.impl;

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
import com.registry.verg.crop.entity.CropEntity;
import com.registry.verg.crop.repository.CropRepository;
import com.registry.verg.crop.service.CropService;
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
public class CropServiceImpl implements CropService {
    @Autowired
    private PayloadValidation payloadValidation;

    @Autowired
    private PrimaryKeyUtil primaryKeyUtil;

    @Autowired
    private CropRepository cropRepository;

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

    private Logger logger = LoggerFactory.getLogger(CropServiceImpl.class);

    @Value("${spring.redis.cacheTtl}")
    private long searchResultRedisTtl;

    @Override
    public CustomResponse createCrop(JsonNode cropEntity) {
        log.info("CropServiceImpl::createCrop:entered the method: " + cropEntity);
        CustomResponse response = new CustomResponse();
        payloadValidation.validatePayload(Constants.CROP_VALIDATION_FILE_JSON, cropEntity);

        log.debug("CropServiceImpl::createCrop:validated the payload");
        try {
            log.info("CropServiceImpl::createCrop:creating crop");
            CropEntity cropEntity1 = new CropEntity();
            // Generate Primary Key
            String primaryID = primaryKeyUtil.generateKey(Constants.CROP_VALIDATION_FILE_JSON);
            cropEntity1.setCropId(primaryID);
            // Create Parameters like createdDate / updateDate / Data and Status
            Timestamp currentTime = new Timestamp(System.currentTimeMillis());
            cropEntity1.setCreatedOn(currentTime);
            cropEntity1.setUpdatedOn(currentTime);
            cropEntity1.setStatus(Constants.ACTIVE);
            cropEntity1.setData(cropEntity);

            cropRepository.save(cropEntity1);

            log.info("CropServiceImpl::createCrop::persisted crop in postgres");
            ObjectNode jsonNode = objectMapper.createObjectNode();
            jsonNode.setAll((ObjectNode) cropEntity);
            Map<String, Object> map = objectMapper.convertValue(jsonNode, Map.class);
            esUtilService.addDocument(Constants.CROP_INDEX_NAME, Constants.INDEX_TYPE,
                    String.valueOf(primaryID), map, vergProperties.getElasticCropJsonPath());
            cacheService.putCache(primaryID, jsonNode);
            response.setMessage(Constants.SUCCESSFULLY_CREATED);
            map.put(Constants.CROP_ID_RQST, primaryID);
            response.setResult(map);
            response.setResponseCode(HttpStatus.OK);
            log.info("CropServiceImpl::createCrop::persisted crop in Verg");
            return response;

        } catch (Exception e) {
            throw new CustomException("error while processing", e.getMessage(),
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Override
    public CustomResponse searchCrop(SearchCriteria searchCriteria) {
        log.info("CropServiceImpl::searchCrop");
        CustomResponse response = new CustomResponse();
        SearchResult searchResult = redisTemplate.opsForValue()
                .get(generateRedisJwtTokenKey(searchCriteria));
        if (searchResult != null) {
            log.info("CropServiceImpl::searchCrop: crop search result fetched from redis");
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
                    esUtilService.searchDocuments(Constants.CROP_INDEX_NAME, searchCriteria);
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
    public CustomResponse assignCrop(JsonNode cropEntity, String token) {
        return null;
    }

    @Override
    public CustomResponse read(String id) {
        log.info("CropServiceImpl::read:inside the method");
        CustomResponse response = new CustomResponse();
        if (StringUtils.isEmpty(id)) {
            response.setResponseCode(HttpStatus.INTERNAL_SERVER_ERROR);
            response.setMessage(Constants.ID_NOT_FOUND);
            return response;
        }
        try {
            String cachedJson = cacheService.getCache(id);
            if (StringUtils.isNotEmpty(cachedJson)) {
                log.info("CropServiceImpl::read:Record coming from redis cache");
                response.setMessage(Constants.SUCCESSFULLY_READING);
                response
                        .getResult()
                        .put(Constants.RESULT, objectMapper.readValue(cachedJson, new TypeReference<Object>() {
                        }));
            } else {
                Optional<CropEntity> entityOptional = cropRepository.findById(id);
                if (entityOptional.isPresent()) {
                    CropEntity cropEntity = entityOptional.get();
                    cacheService.putCache(id, cropEntity.getData());
                    log.info("CropServiceImpl::read:Record coming from postgres db");
                    response.setMessage(Constants.SUCCESSFULLY_READING);
                    response
                            .getResult()
                            .put(Constants.RESULT,
                                    objectMapper.convertValue(
                                            cropEntity.getData(), new TypeReference<Object>() {
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
                // logger.error("Error occurred while converting json object to json string", e);
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