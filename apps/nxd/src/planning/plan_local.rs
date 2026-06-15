use crate::context::RuntimeContext;

pub fn is_local_target(hostname: &str, target_ip: &str, local_hostname: &str) -> bool {
	target_ip == "127.0.0.1" || target_ip == "localhost" || hostname == local_hostname
}

pub fn is_local_context(ctx: &RuntimeContext, local_hostname: &str) -> bool {
	is_local_target(&ctx.hostname, &ctx.target_ip, local_hostname)
}
