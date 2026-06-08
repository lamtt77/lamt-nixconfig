use crate::context::RuntimeContext;
use std::sync::OnceLock;

pub fn current_local_hostname() -> String {
    static CACHE: OnceLock<String> = OnceLock::new();
    CACHE
        .get_or_init(|| {
            std::process::Command::new("hostname")
                .arg("-s")
                .output()
                .ok()
                .filter(|out| out.status.success())
                .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
                .filter(|name| !name.is_empty())
                .unwrap_or_else(|| "localhost".to_string())
        })
        .clone()
}

pub fn is_local_target(ctx: &RuntimeContext) -> bool {
    crate::plan::is_local_context(ctx, &current_local_hostname())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_current_local_hostname() {
        let host = current_local_hostname();
        assert!(!host.is_empty());
    }
}
