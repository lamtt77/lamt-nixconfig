use crate::progress::color::{self, ColorMode};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StatusLevel {
    Info,
    Success,
    Warning,
    Error,
    Failure,
    Debug,
}

impl StatusLevel {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "Info" | "INFO" => Some(StatusLevel::Info),
            "Success" | "SUCCESS" => Some(StatusLevel::Success),
            "Warning" | "Warn" | "WARNING" | "WARN" => Some(StatusLevel::Warning),
            "Error" | "ERROR" => Some(StatusLevel::Error),
            "Failure" | "Fail" | "FAILURE" | "FAIL" => Some(StatusLevel::Failure),
            "Debug" | "DEBUG" => Some(StatusLevel::Debug),
            _ => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            StatusLevel::Info => "INFO",
            StatusLevel::Success => "SUCCESS",
            StatusLevel::Warning => "WARNING",
            StatusLevel::Error => "ERROR",
            StatusLevel::Failure => "FAILURE",
            StatusLevel::Debug => "DEBUG",
        }
    }
}

pub struct ProgressEvent<'a> {
    pub level: StatusLevel,
    pub host: Option<&'a str>,
    pub message: String,
}

pub fn normalize_multiline_message(message: &str) -> String {
    let mut lines: Vec<&str> = message.lines().collect();
    if lines.len() <= 1 {
        return message.to_string();
    }

    while lines.first().is_some_and(|line| line.trim().is_empty()) {
        lines.remove(0);
    }
    while lines.last().is_some_and(|line| line.trim().is_empty()) {
        lines.pop();
    }

    let common_indent = lines
        .iter()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            line.chars()
                .take_while(|ch| *ch == ' ' || *ch == '\t')
                .count()
        })
        .min()
        .unwrap_or(0);

    lines
        .iter()
        .map(|line| {
            if line.trim().is_empty() {
                ""
            } else {
                line.char_indices()
                    .nth(common_indent)
                    .map(|(idx, _)| &line[idx..])
                    .unwrap_or("")
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

impl<'a> ProgressEvent<'a> {
    pub fn new(level: StatusLevel, host: Option<&'a str>, message: impl Into<String>) -> Self {
        Self {
            level,
            host,
            message: message.into(),
        }
    }

    pub fn render(&self, color_mode: ColorMode) -> String {
        let prefix = if let Some(host) = self.host {
            format!("[{}] ", host)
        } else {
            "".to_string()
        };

        match self.level {
            StatusLevel::Info => {
                format!("{}{}", prefix, self.message)
            }
            StatusLevel::Success => {
                let success_label = color::colorize("SUCCESS", color::GREEN, color_mode);
                format!("{}{} {}", prefix, success_label, self.message)
            }
            StatusLevel::Warning => {
                let warning_label = color::colorize("WARNING", color::YELLOW, color_mode);
                format!("{}{} {}", prefix, warning_label, self.message)
            }
            StatusLevel::Error => {
                let error_label = color::colorize("ERROR", color::RED, color_mode);
                format!("{}{} {}", prefix, error_label, self.message)
            }
            StatusLevel::Failure => {
                let failure_label = color::colorize("FAILURE", color::RED, color_mode);
                format!("{}{} {}", prefix, failure_label, self.message)
            }
            StatusLevel::Debug => {
                let debug_label = color::colorize("[DEBUG]", color::GRAY, color_mode);
                format!("{} {}", debug_label, self.message)
            }
        }
    }

    pub fn log(&self, color_mode: ColorMode) {
        let msg = self.render(color_mode);
        match self.level {
            StatusLevel::Error | StatusLevel::Failure | StatusLevel::Debug => {
                eprintln!("{}", msg);
            }
            _ => {
                println!("{}", msg);
            }
        }
    }
}

pub fn print_elapsed_summary(prefix: &str, duration: std::time::Duration) {
    let mins = duration.as_secs() / 60;
    let secs = duration.as_secs() % 60;
    let event = ProgressEvent::new(
        StatusLevel::Success,
        None,
        format!("{} completed in {}m {}s!", prefix, mins, secs),
    );
    event.log(ColorMode::Auto);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_progress_event_rendering() {
        let event = ProgressEvent::new(StatusLevel::Success, Some("host1"), "done");
        let rendered = event.render(ColorMode::Never);
        assert_eq!(rendered, "[host1] SUCCESS done");
    }

    #[test]
    fn test_debug_rendering() {
        let event = ProgressEvent::new(StatusLevel::Debug, None, "testing");
        let rendered = event.render(ColorMode::Never);
        assert_eq!(rendered, "[DEBUG] testing");
    }

    #[test]
    fn normalizes_multiline_message_indentation() {
        let normalized = normalize_multiline_message(
            "
            Timing breakdown:
              Context loading: 1s
              Execution: 2s
            ",
        );
        assert_eq!(
            normalized,
            "Timing breakdown:\n  Context loading: 1s\n  Execution: 2s"
        );
    }

    #[test]
    fn preserves_single_line_indentation() {
        assert_eq!(
            normalize_multiline_message("  already aligned"),
            "  already aligned"
        );
    }
}
