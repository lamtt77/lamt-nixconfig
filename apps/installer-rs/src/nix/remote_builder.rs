use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

static BUILDER_LOCKS: OnceLock<Mutex<HashMap<String, Arc<Mutex<()>>>>> = OnceLock::new();
static BUILDER_BASE_SYNCS: OnceLock<Mutex<HashMap<String, Arc<Mutex<bool>>>>> = OnceLock::new();

pub fn get_builder_lock(connection: &str) -> Arc<Mutex<()>> {
    let map_mutex = BUILDER_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut map = map_mutex.lock().unwrap();
    map.entry(connection.to_string())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

pub fn get_builder_base_sync(connection: &str, base_dir: &str) -> Arc<Mutex<bool>> {
    let map_mutex = BUILDER_BASE_SYNCS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut map = map_mutex.lock().unwrap();
    let key = format!("{}:{}", connection, base_dir);
    map.entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(false)))
        .clone()
}

pub fn check_builder_compatible(builder_ssh: &str, target_system: &str) -> bool {
    let Some(stdout) = crate::remote::ssh::probe_stdout(builder_ssh, "uname -m", 2) else {
        return false;
    };

    let builder_system = match stdout.trim() {
        "x86_64" => "x86_64-linux",
        "aarch64" | "arm64" => "aarch64-linux",
        _ => "",
    };

    builder_system == target_system
}
