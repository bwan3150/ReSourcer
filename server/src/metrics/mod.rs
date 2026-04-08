pub mod models;
mod storage;
mod handlers;
pub mod collector;

use actix_web::web;

pub fn routes(cfg: &mut web::ServiceConfig) {
    cfg.service(web::resource("/current").route(web::get().to(handlers::current)))
       .service(web::resource("/history").route(web::get().to(handlers::history)))
       .service(web::resource("/disk").route(web::get().to(handlers::disk_details)));
}
