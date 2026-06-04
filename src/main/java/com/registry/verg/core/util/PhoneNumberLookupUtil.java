package com.registry.verg.core.util;

import com.registry.verg.core.cache.CacheService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * Utility class for looking up lead IDs by phone number using Redis.
 * Stores a mapping of phone_number → lead_id in Redis with the key prefix "phone:".
 */
@Slf4j
@Component
public class PhoneNumberLookupUtil {

    private static final String PHONE_KEY_PREFIX = "phone:";

    @Autowired
    private CacheService cacheService;

    /**
     * Stores the phone_number → lead_id mapping in Redis.
     *
     * @param phoneNumber the phone number to use as the lookup key
     * @param leadId      the lead ID to associate with this phone number
     */
    public void cachePhoneNumberMapping(String phoneNumber, String leadId) {
        if (StringUtils.isEmpty(phoneNumber) || StringUtils.isEmpty(leadId)) {
            log.warn("PhoneNumberLookupUtil::cachePhoneNumberMapping::skipping cache - phoneNumber or leadId is empty");
            return;
        }
        try {
            String redisKey = PHONE_KEY_PREFIX + phoneNumber;
            cacheService.putCache(redisKey, leadId);
            log.info("PhoneNumberLookupUtil::cachePhoneNumberMapping::cached phone_number={} -> leadId={}", phoneNumber, leadId);
        } catch (Exception e) {
            log.error("PhoneNumberLookupUtil::cachePhoneNumberMapping::error caching phone mapping: {}", e.getMessage());
        }
    }

    /**
     * Looks up a lead ID by phone number from Redis.
     *
     * @param phoneNumber the phone number to look up
     * @return the lead ID if found, or null if no mapping exists
     */
    public String findLeadIdByPhoneNumber(String phoneNumber) {
        if (StringUtils.isEmpty(phoneNumber)) {
            return null;
        }
        try {
            String redisKey = PHONE_KEY_PREFIX + phoneNumber;
            String cachedValue = cacheService.getCache(redisKey);
            if (StringUtils.isNotEmpty(cachedValue)) {
                // The value is stored as a JSON string (quoted), so strip the quotes
                String leadId = cachedValue.replace("\"", "");
                log.info("PhoneNumberLookupUtil::findLeadIdByPhoneNumber::found leadId={} for phone_number={}", leadId, phoneNumber);
                return leadId;
            }
        } catch (Exception e) {
            log.warn("PhoneNumberLookupUtil::findLeadIdByPhoneNumber::error looking up phone_number: {}", e.getMessage());
        }
        return null;
    }
}
