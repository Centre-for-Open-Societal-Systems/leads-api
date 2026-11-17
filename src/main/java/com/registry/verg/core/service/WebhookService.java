package com.registry.verg.core.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.util.Map;

/**
 * Fire-and-forget webhook calls, shared by all catalogues.
 *
 * Kept in its own bean so that {@code @Async} goes through the Spring proxy and the call
 * really runs on the task executor (an {@code @Async} method called from inside the same
 * class runs synchronously).
 */
@Service
@Slf4j
public class WebhookService {

    @Autowired
    private OutboundRequestHandlerServiceImpl outboundRequestHandler;

    /**
     * POSTs {@code payload} as JSON to {@code url} with the given headers, off the request thread.
     * Failures are logged and never reach the caller.
     */
    @Async
    public void sendToWebhookAsync(String url, Map<String, Object> payload, Map<String, String> headers) {
        try {
            log.info("WebhookService::sendToWebhookAsync::sending data to webhook: {}", url);
            Object result = outboundRequestHandler.fetchResultUsingPost(url, payload, headers);
            log.info("WebhookService::sendToWebhookAsync::webhook response received: {}", result);
        } catch (Exception e) {
            log.error("WebhookService::sendToWebhookAsync::failed to send webhook: {}", e.getMessage(), e);
        }
    }
}
