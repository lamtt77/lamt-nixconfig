pub fn ps_literal(value: &str) -> String {
	format!("'{}'", value.replace('\'', "''"))
}

pub fn powershell(script: &str) -> String {
	let wrapped = format!(
		"$ErrorActionPreference = 'Stop'; [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding; & {{ {} }}",
		script
	);
	let bytes = wrapped.encode_utf16().flat_map(u16::to_le_bytes).collect::<Vec<_>>();
	format!(
		"powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand {}",
		base64_encode(&bytes)
	)
}

pub fn list_distributions() -> String {
	powershell("wsl.exe --list --quiet")
}

pub fn list_running_distributions() -> String {
	powershell("wsl.exe --list --running --quiet")
}

pub fn check_powershell() -> String {
	powershell("'nxd-powershell-ok'")
}

pub fn check_wsl_command() -> String {
	powershell("$null = Get-Command wsl.exe -ErrorAction Stop; 'nxd-wsl-command-ok'")
}

pub fn check_wsl_version() -> String {
	powershell("wsl.exe --version | Out-String")
}

pub fn check_wsl_access() -> String {
	powershell("wsl.exe --status | Out-String; wsl.exe --list --quiet | Out-String")
}

pub fn check_install_root(install_root: &str) -> String {
	powershell(&format!(
		"$path = {}; \
		 $parent = Split-Path -Parent $path; \
		 if (-not $parent) {{ $parent = $path }} \
		 New-Item -ItemType Directory -Force -Path $parent | Out-Null; \
		 $testFile = Join-Path $parent '.nxd-write-test'; \
		 try {{ \
		     [System.IO.File]::WriteAllText($testFile, 'test'); \
		     Remove-Item $testFile -Force; \
		 }} catch {{ \
		     throw \"No write access to WSL installation root: $parent\" \
		 }}",
		ps_literal(install_root)
	))
}

pub fn install_windows_authorized_key(public_key: &str) -> String {
	powershell(&format!(
		"$key = {}; \
		 $identity = [Security.Principal.WindowsIdentity]::GetCurrent(); \
		 $principal = [Security.Principal.WindowsPrincipal]::new($identity); \
		 $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); \
		 if ($isAdmin) {{ \
		     $sshDir = Join-Path $env:ProgramData 'ssh'; \
		     $path = Join-Path $sshDir 'administrators_authorized_keys'; \
		 }} else {{ \
		     $sshDir = Join-Path $HOME '.ssh'; \
		     $path = Join-Path $sshDir 'authorized_keys'; \
		 }}; \
		 New-Item -ItemType Directory -Force -Path $sshDir | Out-Null; \
		 $lines = if (Test-Path -LiteralPath $path) {{ @([IO.File]::ReadAllLines($path)) }} else {{ @() }}; \
		 if ($lines -notcontains $key) {{ $lines += $key }}; \
		 [IO.File]::WriteAllLines($path, $lines, [Text.UTF8Encoding]::new($false)); \
		 if ($isAdmin) {{ \
		     & icacls.exe $path /reset | Out-Null; \
		     if ($LASTEXITCODE -ne 0) {{ throw 'Failed to reset administrators_authorized_keys ACL' }}; \
		     & icacls.exe $path /inheritance:r | Out-Null; \
		     if ($LASTEXITCODE -ne 0) {{ throw 'Failed to disable administrators_authorized_keys inheritance' }}; \
		     & icacls.exe $path /grant:r '*S-1-5-32-544:F' 'SYSTEM:F' | Out-Null; \
		     if ($LASTEXITCODE -ne 0) {{ throw 'Failed to set administrators_authorized_keys ACL' }}; \
		 }}; \
		 Write-Output \"Installed public key at $path\"",
		ps_literal(public_key)
	))
}

pub fn verify_archive(archive_name: &str, expected_sha256: &str) -> String {
	powershell(&format!(
		"$archive = Join-Path $HOME {}; \
		 $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant(); \
		 if ($actual -ne {}) {{ throw \"WSL bootstrap artifact checksum mismatch\" }}",
		ps_literal(archive_name),
		ps_literal(expected_sha256)
	))
}

pub fn prepare_archive(archive_name: &str, expected_sha256: &str) -> String {
	powershell(&format!(
		"$archive = Join-Path $HOME {}; \
		 if (Test-Path -LiteralPath $archive) {{ \
		     $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant(); \
		     if ($actual -eq {}) {{ 'MATCH' }} else {{ Remove-Item -LiteralPath $archive -Force; 'UPLOAD' }} \
		 }} else {{ 'UPLOAD' }}",
		ps_literal(archive_name),
		ps_literal(expected_sha256)
	))
}

pub fn archive_size(archive_name: &str) -> String {
	powershell(&format!(
		"$archive = Join-Path $HOME {}; \
		 if (Test-Path -LiteralPath $archive) {{ (Get-Item -LiteralPath $archive).Length }} else {{ 0 }}",
		ps_literal(archive_name)
	))
}

pub fn promote_archive(partial_name: &str, archive_name: &str, expected_sha256: &str) -> String {
	powershell(&format!(
		"$partial = Join-Path $HOME {}; \
		 $archive = Join-Path $HOME {}; \
		 $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $partial).Hash.ToLowerInvariant(); \
		 if ($actual -ne {}) {{ Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue; throw 'WSL bootstrap artifact checksum mismatch' }}; \
		 Move-Item -LiteralPath $partial -Destination $archive -Force",
		ps_literal(partial_name),
		ps_literal(archive_name),
		ps_literal(expected_sha256)
	))
}

pub fn cleanup_archive_cache(distribution: &str, keep_name: &str) -> String {
	let prefix = format!("nxd-{}-", sanitize_name(distribution));
	powershell(&format!(
		"$keep = {}; \
		 Get-ChildItem -LiteralPath $HOME -Filter {} -File | \
		   Where-Object {{ $_.Name -ne $keep }} | \
		   Sort-Object LastWriteTime -Descending | \
		   Select-Object -Skip 2 | \
		   Remove-Item -Force -ErrorAction SilentlyContinue",
		ps_literal(keep_name),
		ps_literal(&format!("{}*.tar.gz", prefix))
	))
}

pub fn remove_archive(archive_name: &str) -> String {
	powershell(&format!(
		"$archive = Join-Path $HOME {}; Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue",
		ps_literal(archive_name)
	))
}

pub fn import_distribution(distribution: &str, install_root: &str, archive_name: &str) -> String {
	powershell(&format!(
		"New-Item -ItemType Directory -Force -Path {} | Out-Null; \
		 $archive = Join-Path $HOME {}; \
		 wsl.exe --import {} {} $archive --version 2",
		ps_literal(install_root),
		ps_literal(archive_name),
		ps_literal(distribution),
		ps_literal(install_root)
	))
}

pub fn unregister_distribution(distribution: &str) -> String {
	powershell(&format!("wsl.exe --unregister {}", ps_literal(distribution)))
}

pub fn start_distribution(distribution: &str) -> String {
	powershell(&format!("wsl.exe -d {} --exec /bin/sh -c true", ps_literal(distribution)))
}

pub fn start_keepalive(distribution: &str, timeout_secs: u32) -> String {
	powershell(&format!(
		"wsl.exe -d {} --exec /run/current-system/sw/bin/sleep {}",
		ps_literal(distribution),
		ps_literal(&timeout_secs.to_string())
	))
}

pub fn guest_ip(distribution: &str) -> String {
	powershell(&format!(
		"$addresses = (wsl.exe -d {} -- hostname -I).Trim().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries); \
		 $selected = $addresses | Where-Object {{ $_ -match '^[0-9a-fA-F:.]+$' -and $_ -notmatch '^127\\.' -and $_ -ne '::1' }} | Select-Object -First 1; \
		 if (-not $selected) {{ throw 'WSL guest returned no usable address' }}; $selected",
		ps_literal(distribution)
	))
}

pub fn sanitize_name(value: &str) -> String {
	value
		.chars()
		.map(|character| if character.is_ascii_alphanumeric() { character } else { '-' })
		.collect()
}

fn base64_encode(bytes: &[u8]) -> String {
	const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	let mut encoded = String::with_capacity(bytes.len().div_ceil(3) * 4);
	for chunk in bytes.chunks(3) {
		let first = chunk[0];
		let second = chunk.get(1).copied().unwrap_or(0);
		let third = chunk.get(2).copied().unwrap_or(0);
		encoded.push(TABLE[(first >> 2) as usize] as char);
		encoded.push(TABLE[(((first & 0x03) << 4) | (second >> 4)) as usize] as char);
		if chunk.len() > 1 {
			encoded.push(TABLE[(((second & 0x0f) << 2) | (third >> 6)) as usize] as char);
		} else {
			encoded.push('=');
		}
		if chunk.len() > 2 {
			encoded.push(TABLE[(third & 0x3f) as usize] as char);
		} else {
			encoded.push('=');
		}
	}
	encoded
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn escapes_powershell_literals() {
		assert_eq!(ps_literal("NixOS O'Brien"), "'NixOS O''Brien'");
	}

	#[test]
	fn import_command_quotes_all_metadata() {
		let command = import_distribution("NixOS Test", r"C:\WSL\NixOS Test", "nxd test.tar.gz");
		assert!(command.contains("-NoProfile -NonInteractive -EncodedCommand"));
		assert!(!command.contains("NixOS Test"));
	}

	#[test]
	fn checksum_command_does_not_interpolate_metadata() {
		let command = verify_archive("nxd test.tar.gz", "abc123");
		assert!(command.contains("-EncodedCommand"));
		assert!(!command.contains("nxd test.tar.gz"));
	}

	#[test]
	fn prepare_archive_reuses_only_matching_content() {
		let command = prepare_archive("nxd test.tar.gz", "abc123");
		let encoded = command.split_whitespace().last().unwrap();
		let bytes = decode_base64(encoded);
		let utf16 =
			bytes.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect::<Vec<_>>();
		let script = String::from_utf16(&utf16).unwrap();

		assert!(script.contains("'MATCH'"));
		assert!(script.contains("Remove-Item"));
		assert!(script.contains("'UPLOAD'"));
		assert!(script.contains("'abc123'"));
	}

	#[test]
	fn archive_progress_and_promotion_commands_are_encoded() {
		let size = archive_size("archive.partial");
		let promote = promote_archive("archive.partial", "archive.tar.gz", "abc123");
		let cleanup = cleanup_archive_cache("NixOS Test", "archive.tar.gz");

		assert!(size.contains("-EncodedCommand"));
		assert!(promote.contains("-EncodedCommand"));
		assert!(cleanup.contains("-EncodedCommand"));
		assert!(!promote.contains("archive.partial"));
		assert!(!cleanup.contains("NixOS Test"));
	}

	#[test]
	fn install_root_command_escapes_path() {
		let command = check_install_root(r"C:\WSL\NixOS O'Brien");
		assert!(command.contains("-EncodedCommand"));
		assert!(!command.contains("O'Brien"));
	}

	#[test]
	fn authorized_key_command_hides_key_from_command_line() {
		let command = install_windows_authorized_key("ssh-ed25519 AAAATest user@example");
		assert!(command.contains("-EncodedCommand"));
		assert!(!command.contains("AAAATest"));
	}

	#[test]
	fn keepalive_command_runs_wsl_in_the_foreground() {
		let start = start_keepalive("NixOS Test", 21_600);
		let encoded = start.split_whitespace().last().unwrap();
		let bytes = decode_base64(encoded);
		let utf16 =
			bytes.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect::<Vec<_>>();
		let script = String::from_utf16(&utf16).unwrap();

		assert!(start.contains("-EncodedCommand"));
		assert!(!start.contains("NixOS Test"));
		assert!(!script.contains("Start-Process"));
		assert!(script.contains("wsl.exe -d 'NixOS Test' --exec"));
		assert!(script.contains("/run/current-system/sw/bin/sleep '21600'"));
	}

	#[test]
	fn base64_encoding_matches_known_values() {
		assert_eq!(base64_encode(b""), "");
		assert_eq!(base64_encode(b"f"), "Zg==");
		assert_eq!(base64_encode(b"fo"), "Zm8=");
		assert_eq!(base64_encode(b"foo"), "Zm9v");
	}

	#[test]
	fn encoded_command_preserves_powershell_literals() {
		let command = import_distribution("NixOS O'Brien", r"C:\WSL\NixOS", "image.tar.gz");
		let encoded = command.split_whitespace().last().unwrap();
		let bytes = decode_base64(encoded);
		let utf16 =
			bytes.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect::<Vec<_>>();
		let script = String::from_utf16(&utf16).unwrap();
		assert!(script.contains("'NixOS O''Brien'"));
		assert!(script.contains(r"'C:\WSL\NixOS'"));
		assert!(script.contains("'image.tar.gz'"));
	}

	fn decode_base64(value: &str) -> Vec<u8> {
		let sextets = value
			.bytes()
			.filter(|byte| *byte != b'=')
			.map(|byte| match byte {
				b'A'..=b'Z' => byte - b'A',
				b'a'..=b'z' => byte - b'a' + 26,
				b'0'..=b'9' => byte - b'0' + 52,
				b'+' => 62,
				b'/' => 63,
				_ => panic!("invalid base64"),
			})
			.collect::<Vec<_>>();
		let mut bytes = Vec::new();
		for chunk in sextets.chunks(4) {
			bytes.push((chunk[0] << 2) | (chunk[1] >> 4));
			if chunk.len() > 2 {
				bytes.push((chunk[1] << 4) | (chunk[2] >> 2));
			}
			if chunk.len() > 3 {
				bytes.push((chunk[2] << 6) | chunk[3]);
			}
		}
		bytes
	}
}
