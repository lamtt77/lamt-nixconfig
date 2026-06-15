use crate::context::load_context_from_spec;
use crate::fleet::resolution::resolve_provider;
use crate::process::Logger;

pub fn execute_destroy(target: &str, plan_only: bool) -> Result<(), Box<dyn std::error::Error>> {
	let ctx = load_context_from_spec(target)?;
	let logger = Logger::terminal();
	if let Some(provider) = resolve_provider(&ctx, logger) {
		let state = provider.inspect()?;
		println!("Host: {}", ctx.hostname);
		println!("  Provider: {:?}", provider.kind());
		println!("  Resource: {}", provider.resource_identity());
		println!("  State:    {:?}", state);
		println!(
			"  Action:   {}",
			if state == crate::providers::ProviderState::Missing {
				"no-op (resource is missing)"
			} else {
				"destroy provider resource"
			}
		);
		if plan_only || state == crate::providers::ProviderState::Missing {
			return Ok(());
		}
		let warning = format!("This permanently destroys {}.", provider.resource_identity());
		if !crate::workflow::confirm::confirm_action(
			"Proceed with provider destruction?",
			Some(&warning),
			crate::config::get_runtime_options().force,
		)? {
			return Err("Destruction cancelled.".into());
		}
		println!("Requesting destruction of instance {}...", target);
		provider.destroy()?;
		println!("Destruction complete.");
		Ok(())
	} else {
		Err(format!("Error: Target {} is not managed by a VM provider.", target).into())
	}
}
