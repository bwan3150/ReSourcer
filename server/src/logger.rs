// 彩色日志中间件
use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error,
};
use colored::*;
use futures_util::future::LocalBoxFuture;
use std::future::{ready, Ready};
use std::time::Instant;

/// 彩色日志中间件
pub struct ColorLogger;

impl ColorLogger {
    pub fn new() -> Self {
        Self
    }
}

impl<S, B> Transform<S, ServiceRequest> for ColorLogger
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = ColorLoggerMiddleware<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(ColorLoggerMiddleware { service }))
    }
}

pub struct ColorLoggerMiddleware<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for ColorLoggerMiddleware<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let start = Instant::now();
        let method = req.method().to_string();
        let path = req.path().to_string();
        let version = format!("{:?}", req.version());

        let fut = self.service.call(req);

        Box::pin(async move {
            let res = fut.await?;
            let elapsed = start.elapsed();
            let status = res.status().as_u16();

            // 格式化时间戳（灰色）
            let timestamp = chrono::Local::now()
                .format("%Y-%m-%dT%H:%M:%S%.6f%:z")
                .to_string()
                .dimmed();

            // 格式化 HTTP 方法（不同颜色）
            let method_colored = match method.as_str() {
                "GET" => method.green(),
                "POST" => method.blue(),
                "PUT" => method.yellow(),
                "PATCH" => method.magenta(),
                "DELETE" => method.red(),
                "OPTIONS" => method.cyan(),
                "HEAD" => method.white(),
                _ => method.normal(),
            };

            // 格式化状态码（不同颜色）
            let status_colored = match status {
                200..=299 => status.to_string().green(),
                300..=399 => status.to_string().cyan(),
                400..=499 => status.to_string().yellow(),
                500..=599 => status.to_string().red(),
                _ => status.to_string().normal(),
            };

            // 格式化耗时
            let elapsed_ms = elapsed.as_secs_f64() * 1000.0;
            let elapsed_str = if elapsed_ms < 10.0 {
                format!("{:.2}ms", elapsed_ms).dimmed()
            } else if elapsed_ms < 100.0 {
                format!("{:.1}ms", elapsed_ms).normal()
            } else if elapsed_ms < 1000.0 {
                format!("{:.0}ms", elapsed_ms).yellow()
            } else {
                format!("{:.1}s", elapsed_ms / 1000.0).red()
            };

            println!(
                "[{}] {} {} {} - {} ({})",
                timestamp,
                method_colored,
                path,
                version.dimmed(),
                elapsed_str,
                status_colored
            );

            Ok(res)
        })
    }
}
