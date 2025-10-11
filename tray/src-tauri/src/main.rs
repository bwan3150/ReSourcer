// 阻止在 Windows 上显示控制台窗口
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::process::{Child, Command};
use std::sync::Mutex;
use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::{TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, Runtime,
};
use tauri_plugin_shell::ShellExt;

// 全局保存 re-sourcer 进程和服务 URL
struct AppState {
    child_process: Mutex<Option<Child>>,
    service_url: Mutex<String>,
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(AppState {
            child_process: Mutex::new(None),
            service_url: Mutex::new(String::new()),
        })
        .setup(|app| {
            // 创建托盘菜单
            let open_item = MenuItemBuilder::with_id("open", "打开 ReSourcer").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "退出").build(app)?;

            let menu = MenuBuilder::new(app)
                .items(&[&open_item, &quit_item])
                .build()?;

            // 创建托盘图标
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .menu_on_left_click(true) // 左键点击显示菜单
                .on_menu_event(move |app, event| match event.id().as_ref() {
                    "open" => {
                        // 打开浏览器访问服务
                        let state: tauri::State<AppState> = app.state();
                        let url = state.service_url.lock().unwrap().clone();
                        if !url.is_empty() {
                            let _ = app.shell().open(&url, None);
                        }
                    }
                    "quit" => {
                        // 退出应用
                        stop_re_sourcer(app);
                        app.exit(0);
                    }
                    _ => {}
                })
                .build(app)?;

            // 应用启动时启动 re-sourcer（使用非阻塞方式）
            let app_handle = app.handle().clone();
            std::thread::spawn(move || {
                // 延迟 1 秒启动
                std::thread::sleep(std::time::Duration::from_secs(1));
                if let Err(e) = start_re_sourcer(app_handle) {
                    eprintln!("启动 re-sourcer 失败: {}", e);
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            // 阻止窗口关闭
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                window.hide().unwrap();
                api.prevent_close();
            }
        })
        .build(tauri::generate_context!())
        .expect("构建 Tauri 应用时出错")
        .run(|app_handle, event| {
            if let tauri::RunEvent::ExitRequested { .. } = event {
                // 应用退出时停止 re-sourcer
                stop_re_sourcer(app_handle);
            }
        });
}

// 获取本机 IP 地址
fn get_local_ip() -> Option<String> {
    use std::net::UdpSocket;

    // 尝试连接到外部地址来获取本机 IP
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("8.8.8.8:80").ok()?;
    let local_addr = socket.local_addr().ok()?;
    Some(local_addr.ip().to_string())
}

// 启动 re-sourcer 二进制文件
fn start_re_sourcer<R: Runtime>(app_handle: AppHandle<R>) -> Result<(), String> {
    // 尝试多个可能的文件名
    let possible_names = vec![
        "re-sourcer-aarch64-apple-darwin",
        "re-sourcer-x86_64-unknown-linux-gnu",
        "re-sourcer-x86_64-pc-windows-msvc.exe",
        "re-sourcer",
    ];

    let mut resource_path = None;
    for name in possible_names {
        if let Ok(path) = app_handle
            .path()
            .resolve(name, tauri::path::BaseDirectory::Resource)
        {
            if path.exists() {
                println!("找到二进制文件: {:?}", path);
                resource_path = Some(path);
                break;
            }
        }
    }

    let resource_path = resource_path.ok_or_else(|| {
        "无法找到 re-sourcer 二进制文件。请确保它已正确打包到应用中。".to_string()
    })?;

    // 检查文件权限
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = std::fs::metadata(&resource_path)
            .map_err(|e| format!("无法读取文件元数据: {}", e))?;
        let permissions = metadata.permissions();

        // 如果没有执行权限，尝试添加
        if permissions.mode() & 0o111 == 0 {
            println!("添加执行权限到 re-sourcer");
            let mut new_permissions = permissions.clone();
            new_permissions.set_mode(permissions.mode() | 0o755);
            std::fs::set_permissions(&resource_path, new_permissions)
                .map_err(|e| format!("无法设置执行权限: {}", e))?;
        }
    }

    // 获取本机 IP 地址
    let ip = get_local_ip().unwrap_or_else(|| "localhost".to_string());
    let port = 1234;
    let service_url = format!("http://{}:{}", ip, port);

    println!("本机 IP: {}", ip);
    println!("服务地址: {}", service_url);

    // 保存服务 URL
    let state: tauri::State<AppState> = app_handle.state();
    *state.service_url.lock().unwrap() = service_url;

    // 获取用户主目录作为工作目录
    let home_dir = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    // 启动进程（不显示终端窗口）
    println!("启动 re-sourcer 进程...");
    println!("工作目录: {}", home_dir);

    let child = Command::new(&resource_path)
        .current_dir(&home_dir) // 设置工作目录为用户主目录
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("启动 re-sourcer 失败: {}", e))?;

    println!("re-sourcer 进程已启动，PID: {}", child.id());

    // 保存进程句柄
    *state.child_process.lock().unwrap() = Some(child);

    Ok(())
}

// 停止 re-sourcer 进程
fn stop_re_sourcer<R: Runtime>(app_handle: &AppHandle<R>) {
    let state: tauri::State<AppState> = app_handle.state();
    let mut child_process = state.child_process.lock().unwrap();

    if let Some(mut child) = child_process.take() {
        println!("停止 re-sourcer 进程");
        let _ = child.kill();
    }
}
