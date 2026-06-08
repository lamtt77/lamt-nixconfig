use crate::process::Logger;
use std::io::{BufRead, BufReader, Write};
use std::thread;

use crate::progress::target::LogTarget;

pub fn format_output_line(line: &str) -> String {
    let color_mode = crate::progress::color::ColorMode::Auto;
    if let Some(stripped) = line.strip_prefix("Error:") {
        let label =
            crate::progress::color::colorize("Error:", crate::progress::color::RED, color_mode);
        format!("{}{}", label, stripped)
    } else if let Some(stripped) = line.strip_prefix("error:") {
        let label =
            crate::progress::color::colorize("error:", crate::progress::color::RED, color_mode);
        format!("{}{}", label, stripped)
    } else if let Some(stripped) = line.strip_prefix("Warning:") {
        let label = crate::progress::color::colorize(
            "Warning:",
            crate::progress::color::YELLOW,
            color_mode,
        );
        format!("{}{}", label, stripped)
    } else if let Some(stripped) = line.strip_prefix("warning:") {
        let label = crate::progress::color::colorize(
            "warning:",
            crate::progress::color::YELLOW,
            color_mode,
        );
        format!("{}{}", label, stripped)
    } else {
        line.to_string()
    }
}

pub fn stream_output_lines<R>(reader: R, logger: Logger, stderr: bool) -> thread::JoinHandle<String>
where
    R: std::io::Read + Send + 'static,
{
    thread::spawn(move || {
        let mut captured = String::new();
        let reader = BufReader::new(reader);
        for line in reader.lines().map_while(Result::ok) {
            write_output_line(&line, logger.clone(), stderr);
            captured.push_str(&line);
            captured.push('\n');
        }
        captured
    })
}

pub fn write_output_line(line: &str, logger: Logger, stderr: bool) {
    if let Ok(mut target) = logger.lock() {
        match &mut *target {
            LogTarget::Terminal => {
                if stderr {
                    eprintln!("{}", format_output_line(line));
                } else {
                    println!("{}", format_output_line(line));
                }
            }
            LogTarget::Batch { file, .. } | LogTarget::File(file) => {
                let _ = writeln!(file, "{}", line);
            }
            LogTarget::Silent => {}
        }
    }
}
