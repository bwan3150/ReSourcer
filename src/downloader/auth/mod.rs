// 认证模块：管理需要认证的平台（X 和 Pixiv）
pub mod x;
pub mod pixiv;

use super::models::AuthStatus;

// 检查所有平台的认证状态
pub fn check_all_auth_status() -> AuthStatus {
    AuthStatus {
        x: x::has_cookies(),
        pixiv: pixiv::has_token(),
    }
}
