package com.registry.verg.core.cache.config;

import com.registry.verg.core.elasticsearch.dto.SearchResult;
import io.lettuce.core.api.StatefulConnection;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.apache.commons.pool2.impl.GenericObjectPoolConfig;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.connection.RedisPassword;
import org.springframework.data.redis.connection.RedisStandaloneConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceClientConfiguration;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.connection.lettuce.LettucePoolingClientConfiguration;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.RedisSerializationContext;
import org.springframework.data.redis.serializer.StringRedisSerializer;


import java.time.Duration;

@Configuration
@EnableCaching
public class RedisConfig {

    @Value("${spring.redis.host}")
    private String redisHost;

    @Value("${spring.redis.port}")
    private int redisPort;

    // Empty default so passwordless setups (e.g. the local docker-compose redis) still
    // work; a secured redis (like the shared 44 instance, which sets requirepass) supplies
    // it via SPRING_REDIS_PASSWORD -> spring.redis.password.
    @Value("${spring.redis.password:}")
    private String redisPassword;

    private final long redisTimeout = 60000;

    @Bean
    public RedisConnectionFactory redisConnectionFactory() {
        RedisStandaloneConfiguration configuration = new RedisStandaloneConfiguration();
        configuration.setHostName(redisHost);
        configuration.setPort(redisPort);
        configuration.setDatabase(0);
        // Only set a password when one is configured — otherwise Lettuce would send AUTH
        // to a passwordless server and fail. This custom factory bypasses Spring Boot's
        // auto-config, so the password MUST be applied here explicitly.
        if (redisPassword != null && !redisPassword.isEmpty()) {
            configuration.setPassword(RedisPassword.of(redisPassword));
        }
        LettuceClientConfiguration clientConfig = LettucePoolingClientConfiguration.builder()
                .commandTimeout(Duration.ofMillis(redisTimeout))
                .poolConfig((GenericObjectPoolConfig<StatefulConnection<?, ?>>) buildPoolConfig())
                .build();
        return new LettuceConnectionFactory(configuration, clientConfig);
    }
    private GenericObjectPoolConfig<?> buildPoolConfig() {
        GenericObjectPoolConfig<?> poolConfig = new GenericObjectPoolConfig<>();
        poolConfig.setMaxTotal(3000);
        poolConfig.setMaxIdle(128);
        poolConfig.setMinIdle(100);
        poolConfig.setMaxWait(Duration.ofMillis(5000));
        return poolConfig;
    }
    @Bean
    public RedisTemplate<String, SearchResult> redisTemplate(RedisConnectionFactory redisConnectionFactory) {
        RedisTemplate<String, SearchResult> redisTemplate = new RedisTemplate<>();
        redisTemplate.setConnectionFactory(redisConnectionFactory);
        redisTemplate.setKeySerializer(new StringRedisSerializer());
        redisTemplate.setValueSerializer(new StringRedisSerializer());
        redisTemplate.setHashKeySerializer(new StringRedisSerializer());
        redisTemplate.setHashValueSerializer(new StringRedisSerializer());
        return redisTemplate;
    }

    @Bean
    public CacheManager cacheManager(RedisConnectionFactory redisConnectionFactory) {
        RedisCacheConfiguration cacheConfig = RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(Duration.ofSeconds(3600))
                .disableCachingNullValues()
                .serializeKeysWith(
                        RedisSerializationContext.SerializationPair
                                .fromSerializer(new StringRedisSerializer()))
                .serializeValuesWith(
                        RedisSerializationContext.SerializationPair
                                .fromSerializer(new StringRedisSerializer()));

        return RedisCacheManager.builder(redisConnectionFactory)
                .cacheDefaults(cacheConfig)
                .build();
    }
}