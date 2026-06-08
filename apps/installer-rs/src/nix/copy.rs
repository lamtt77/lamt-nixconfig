use crate::nix::NixBuilder;
use crate::process::{shell_escape, Logger};

fn debug_print_nix_copy_args(args: &[&str], logger: Logger) {
    let rendered = std::iter::once("nix".to_string())
        .chain(args.iter().map(|arg| shell_escape(arg)))
        .collect::<Vec<_>>()
        .join(" ");
    debug!(logger, "Nix copy command: {}", rendered);
}

fn debug_print_nix_copy_command(command: &str, logger: Logger) {
    debug!(logger, "Nix copy command: {}", command);
}

pub fn nix_copy_args<'a>(
    builder: &NixBuilder,
    copy_target: &'a str,
    source: &'a str,
) -> Vec<&'a str> {
    let mut args = vec!["copy"];
    if builder.substitute_on_destination {
        args.push("--substitute-on-destination");
    }
    args.push("--to");
    args.push(copy_target);
    args.push(source);
    args
}

pub fn nix_copy_args_with_log<'a>(
    builder: &NixBuilder,
    copy_target: &'a str,
    source: &'a str,
    logger: Logger,
) -> Vec<&'a str> {
    let args = nix_copy_args(builder, copy_target, source);
    debug_print_nix_copy_args(&args, logger);
    args
}

pub fn nix_copy_command(builder: &NixBuilder, copy_target: &str, source: &str) -> String {
    let substitute_flag = if builder.substitute_on_destination {
        " --substitute-on-destination"
    } else {
        ""
    };

    format!(
        "export NIX_SSHOPTS=\"{}\" && \
         nix copy{} --to \"{}\" {}",
        crate::remote::ssh::SshOptions::nix_copy().nix_sshopts(),
        substitute_flag,
        copy_target,
        source
    )
}

pub fn nix_copy_command_with_log(
    builder: &NixBuilder,
    copy_target: &str,
    source: &str,
    logger: Logger,
) -> String {
    let command = nix_copy_command(builder, copy_target, source);
    debug_print_nix_copy_command(&command, logger);
    command
}
