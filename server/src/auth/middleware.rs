use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpResponse,
    body::EitherBody,
    http::header,
};
use futures_util::future::LocalBoxFuture;
use std::future::{ready, Ready};

/// API Key 验证中间件
pub struct ApiKeyAuth {
    api_key: String,
}

impl ApiKeyAuth {
    pub fn new(api_key: String) -> Self {
        Self { api_key }
    }
}

impl<S, B> Transform<S, ServiceRequest> for ApiKeyAuth
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<EitherBody<B>>;
    type Error = Error;
    type InitError = ();
    type Transform = ApiKeyAuthMiddleware<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(ApiKeyAuthMiddleware {
            service,
            api_key: self.api_key.clone(),
        }))
    }
}

pub struct ApiKeyAuthMiddleware<S> {
    service: S,
    api_key: String,
}

impl<S, B> Service<ServiceRequest> for ApiKeyAuthMiddleware<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<EitherBody<B>>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let path = req.path();

        // If server is updating, reject all requests except health check
        if crate::updater::is_updating() && path != "/api/health" {
            return Box::pin(async move {
                let resp = HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Server is restarting after update"}));
                Ok(req.into_response(resp).map_into_right_body())
            });
        }

        // 白名单：不需要验证的 API 路径
        let whitelist = [
            "/api/auth/verify",
            "/api/health",
            "/api/app",
        ];

        // 检查是否在白名单中
        let is_whitelisted = whitelist.iter().any(|w| path.starts_with(w));

        if is_whitelisted {
            let fut = self.service.call(req);
            return Box::pin(async move {
                let res = fut.await?;
                Ok(res.map_into_left_body())
            });
        }

        // 从三个地方获取 API Key
        let api_key = {
            // 1. 从 Header 获取
            if let Some(key) = req.headers().get("X-API-Key") {
                key.to_str().ok().map(|s| s.to_string())
            }
            // 2. 从 Cookie 获取
            else if let Some(cookie_header) = req.headers().get(header::COOKIE) {
                if let Ok(cookie_str) = cookie_header.to_str() {
                    cookie_str
                        .split(';')
                        .find_map(|c| {
                            let parts: Vec<&str> = c.trim().splitn(2, '=').collect();
                            if parts.len() == 2 && parts[0] == "api_key" {
                                Some(parts[1].to_string())
                            } else {
                                None
                            }
                        })
                } else {
                    None
                }
            }
            // 3. 从 URL 参数获取
            else {
                req.query_string()
                    .split('&')
                    .find_map(|pair| {
                        let parts: Vec<&str> = pair.splitn(2, '=').collect();
                        if parts.len() == 2 && parts[0] == "key" {
                            Some(parts[1].to_string())
                        } else {
                            None
                        }
                    })
            }
        };

        // 验证 API Key
        let valid = api_key.as_ref().map_or(false, |k| k == &self.api_key);

        if !valid {
            // 未认证请求返回 401
            let (request, _) = req.into_parts();
            let response = HttpResponse::Unauthorized()
                .json(serde_json::json!({"error": "Unauthorized: Invalid or missing API Key"}))
                .map_into_right_body();

            return Box::pin(async move {
                Ok(ServiceResponse::new(request, response))
            });
        }

        // Key 有效，继续处理
        let fut = self.service.call(req);
        Box::pin(async move {
            let res = fut.await?;
            Ok(res.map_into_left_body())
        })
    }
}
