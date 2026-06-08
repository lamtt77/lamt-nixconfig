use dialoguer::Confirm;

/// Prompt user for confirmation on an action. Returns true if confirmed.
/// Auto-confirms and prints a warning/message if `force` is true.
pub fn confirm_action(
    prompt: &str,
    warning: Option<&str>,
    force: bool,
) -> Result<bool, Box<dyn std::error::Error>> {
    if force {
        if let Some(warn) = warning {
            println!("{}", warn);
        }
        return Ok(true);
    }

    let confirmed = Confirm::new()
        .with_prompt(prompt)
        .default(false)
        .interact()
        .unwrap_or(false);

    Ok(confirmed)
}
