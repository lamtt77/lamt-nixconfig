use std::io::IsTerminal;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum ColorMode {
	#[default]
	Auto,
	Always,
	Never,
}

pub fn should_color(mode: ColorMode) -> bool {
	match mode {
		ColorMode::Always => true,
		ColorMode::Never => false,
		ColorMode::Auto => {
			if std::env::var("NO_COLOR").is_ok() {
				false
			} else {
				std::io::stdout().is_terminal()
			}
		}
	}
}

pub fn colorize(text: &str, color_code: &str, mode: ColorMode) -> String {
	if should_color(mode) { format!("\x1b[{}m{}\x1b[0m", color_code, text) } else { text.to_string() }
}

pub const GREEN: &str = "32";
pub const YELLOW: &str = "33";
pub const RED: &str = "31";
pub const CYAN: &str = "36";
pub const MAGENTA: &str = "35";
pub const GRAY: &str = "90";
pub const BOLD: &str = "1";

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_should_color_never() {
		assert!(!should_color(ColorMode::Never));
	}

	#[test]
	fn test_should_color_always() {
		assert!(should_color(ColorMode::Always));
	}

	#[test]
	fn test_colorize_never() {
		let text = "hello";
		assert_eq!(colorize(text, GREEN, ColorMode::Never), "hello");
	}

	#[test]
	fn test_colorize_always() {
		let text = "hello";
		assert_eq!(colorize(text, GREEN, ColorMode::Always), "\x1b[32mhello\x1b[0m");
	}
}
