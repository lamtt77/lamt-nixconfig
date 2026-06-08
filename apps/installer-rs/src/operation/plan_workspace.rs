use crate::context::RuntimeContext;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceMode {
    SingleHost,
    CommonBasePerHost,
}

pub fn is_local_target(hostname: &str, target_ip: &str, local_hostname: &str) -> bool {
    target_ip == "127.0.0.1" || target_ip == "localhost" || hostname == local_hostname
}

pub fn is_local_context(ctx: &RuntimeContext, local_hostname: &str) -> bool {
    is_local_target(&ctx.hostname, &ctx.target_ip, local_hostname)
}

pub fn workspace_mode_for_hosts(
    host_count: usize,
    only_host_is_local: bool,
    single_host_fast_path_allowed: bool,
) -> WorkspaceMode {
    if host_count == 1 && only_host_is_local && single_host_fast_path_allowed {
        WorkspaceMode::SingleHost
    } else {
        WorkspaceMode::CommonBasePerHost
    }
}

pub fn workspace_mode_for_targets<T>(
    targets: &[T],
    single_host_fast_path_allowed: bool,
    is_local: impl Fn(&T) -> bool,
) -> WorkspaceMode {
    workspace_mode_for_hosts(
        targets.len(),
        targets.first().map(is_local).unwrap_or(false),
        single_host_fast_path_allowed,
    )
}
