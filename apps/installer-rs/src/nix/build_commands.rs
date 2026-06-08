use crate::nix::NixBuilder;

pub fn target_ssh(builder: &NixBuilder) -> String {
    let is_deploy = crate::config::get_runtime_options().deploy_active;
    let target_user = if is_deploy { "root" } else { &builder.username };
    format!("{}@{}", target_user, builder.target_ip)
}

pub fn copy_target(target_ssh: &str, mount_point: Option<&str>) -> String {
    if let Some(mnt) = mount_point {
        format!("ssh://{}?remote-store=local?root={}", target_ssh, mnt)
    } else {
        format!("ssh://{}", target_ssh)
    }
}

pub fn flake_target_attr(builder: &NixBuilder, attr: &str) -> String {
    format!("{}#{}", builder.flake_ref, builder.target_attr(attr))
}

pub fn remote_builder_build_command(remote_workspace_dir: &str, target_attr: &str) -> String {
    format!(
        "export NIX_SSHOPTS=\"{}\" && \
         cd {} && nix build --print-out-paths --no-link git+file://$PWD#{}",
        crate::remote::ssh::SshOptions::nix_copy().nix_sshopts(),
        remote_workspace_dir,
        target_attr
    )
}

pub fn target_native_build_command(
    remote_workspace_dir: &str,
    target_attr: &str,
    mount_point: Option<&str>,
) -> String {
    let store_arg = if let Some(mnt) = mount_point {
        format!("--store {} ", mnt)
    } else {
        String::new()
    };

    format!(
        "cd {} && nix build {}--print-out-paths --no-link git+file://$PWD#{}",
        remote_workspace_dir, store_arg, target_attr
    )
}

pub fn target_realise_command(drv_path: &str, mount_point: Option<&str>, low_mem: bool) -> String {
    let gc_env = if low_mem {
        "export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1; "
    } else {
        ""
    };

    let store_arg = if let Some(mnt) = mount_point {
        format!("--store {}", mnt)
    } else {
        String::new()
    };

    format!(
        "{}nix-store --realise {} --cores 1 --max-jobs 1 {}",
        gc_env, drv_path, store_arg
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_copy_targets() {
        assert_eq!(copy_target("root@10.0.0.2", None), "ssh://root@10.0.0.2");
        assert_eq!(
            copy_target("root@10.0.0.2", Some("/mnt")),
            "ssh://root@10.0.0.2?remote-store=local?root=/mnt"
        );
    }

    #[test]
    fn remote_builder_build_uses_git_file_workspace() {
        let command = remote_builder_build_command(
            "lamt-nixconfig/host-a",
            "nixosConfigurations.host-a.config.system.build.toplevel",
        );

        assert!(command.contains("cd lamt-nixconfig/host-a"));
        assert!(
            command.contains(
                "nix build --print-out-paths --no-link git+file://$PWD#nixosConfigurations.host-a.config.system.build.toplevel"
            )
        );
    }

    #[test]
    fn target_native_build_adds_store_only_when_mounted() {
        let mounted = target_native_build_command(
            "lamt-nixconfig/host-a",
            "nixosConfigurations.host-a.config.system.build.toplevel",
            Some("/mnt"),
        );
        let unmounted = target_native_build_command(
            "lamt-nixconfig/host-a",
            "nixosConfigurations.host-a.config.system.build.toplevel",
            None,
        );

        assert!(mounted.contains("nix build --store /mnt --print-out-paths"));
        assert!(unmounted.contains("nix build --print-out-paths"));
        assert!(!unmounted.contains("--store"));
    }

    #[test]
    fn target_realise_command_adds_low_memory_env_only_when_requested() {
        let low_mem = target_realise_command("/nix/store/example.drv", Some("/mnt"), true);
        let normal = target_realise_command("/nix/store/example.drv", None, false);

        assert!(low_mem.starts_with("export GC_INITIAL_HEAP_SIZE=1M"));
        assert!(low_mem.contains("--store /mnt"));
        assert!(!normal.contains("GC_INITIAL_HEAP_SIZE"));
        assert!(!normal.contains("--store"));
    }
}
