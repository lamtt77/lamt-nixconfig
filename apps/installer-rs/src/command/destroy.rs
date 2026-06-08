use crate::context::load_context_from_spec;
use crate::fleet::resolution::resolve_provider;
use crate::process::Logger;

pub fn execute_destroy(target: &str) -> Result<(), Box<dyn std::error::Error>> {
    let ctx = load_context_from_spec(target)?;
    let logger = Logger::terminal();
    if let Some(provider) = resolve_provider(&ctx, logger) {
        println!("Requesting destruction of instance {}...", target);
        provider.destroy()?;
        println!("Destruction complete.");
        Ok(())
    } else {
        Err(format!("Error: Target {} is not managed by a VM provider.", target).into())
    }
}
