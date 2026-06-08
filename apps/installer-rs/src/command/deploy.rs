use crate::batch;
use crate::context::{
    load_batch_contexts, load_context_from_spec, resolve_install_context, RuntimeContext,
};
use crate::fleet::local::is_local_target;
use crate::fleet::resolution::{resolve_provider, resolve_target_ip_for_deploy};
use crate::pipeline::DeploymentMode;
use crate::plan::{OperationKind, RunState, WorkspaceMode};
use crate::process::Logger;
use crate::progress::log::print_elapsed_summary;
use crate::workspace;
use std::sync::Arc;

fn print_batch_deploy_plan(
    planned_hosts: &[RuntimeContext],
    redeploy: bool,
    overwrite: bool,
    convert_to: Option<&String>,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("================ Planning for Batch/Fleet Deployment ================");
    for ctx in planned_hosts {
        let provider = resolve_provider(ctx, logger.clone());
        let has_provider = provider.is_some();
        let provider_exists = provider.map(|p| p.exists()).unwrap_or(false);

        let plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
            ctx,
            operation: crate::plan::OperationKind::Deploy,
            redeploy,
            overwrite,
            convert_to,
            switch_action: None,
            home_manager: false,
            provider_exists,
            has_provider,
        });
        plan.render(ctx, convert_to);
    }
    println!("====================================================================");
    Ok(())
}

fn confirm_batch_deploy(
    planned_hosts: &[RuntimeContext],
    redeploy: bool,
    overwrite: bool,
    convert_to: Option<&String>,
    force: bool,
    logger: Logger,
) -> bool {
    let mut plans = Vec::new();
    for ctx in planned_hosts {
        let provider = resolve_provider(ctx, logger.clone());
        let has_provider = provider.is_some();
        let provider_exists = provider.map(|p| p.exists()).unwrap_or(false);

        let plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
            ctx,
            operation: crate::plan::OperationKind::Deploy,
            redeploy,
            overwrite,
            convert_to,
            switch_action: None,
            home_manager: false,
            provider_exists,
            has_provider,
        });
        plans.push(plan);
    }

    crate::plan::confirm_batch(&plans, force).unwrap_or(false)
}

pub struct DeployCmdOptions<'a> {
    pub target: Option<&'a String>,
    pub hosts: Option<&'a String>,
    pub plan: bool,
    pub redeploy: bool,
    pub overwrite: bool,
    pub convert_to: Option<&'a String>,
    pub force: bool,
    pub parallel: usize,
}

pub async fn execute_deploy(opts: DeployCmdOptions<'_>) -> Result<(), Box<dyn std::error::Error>> {
    let DeployCmdOptions {
        target,
        hosts,
        plan,
        redeploy,
        overwrite,
        convert_to,
        force,
        parallel,
    } = opts;

    crate::command::hosts::validate_target_and_hosts(target, hosts)?;

    // Check if we are running in batch mode
    if let Some(hosts_str) = hosts {
        let host_list = crate::command::hosts::resolve_hosts_arg(hosts_str)?;

        let planned_hosts = load_batch_contexts(&host_list, false)?;

        // 1. Dry run / planning output
        let logger = Logger::terminal();
        print_batch_deploy_plan(
            &planned_hosts,
            redeploy,
            overwrite,
            convert_to,
            logger.clone(),
        )?;

        if plan {
            return Ok(());
        }

        if !confirm_batch_deploy(
            &planned_hosts,
            redeploy,
            overwrite,
            convert_to,
            force,
            logger.clone(),
        ) {
            if redeploy {
                println!("Batch redeployment aborted by user.");
            } else {
                println!("Batch deployment aborted by user.");
            }
            return Ok(());
        }

        // Stage ISOs after confirmation and before parallel execution begins.
        for ctx in &planned_hosts {
            crate::operation::plan_iso::ensure_proxmox_iso(ctx, logger.clone())?;
        }

        println!("Launching batch deployment...");
        let run_plan = crate::plan::build_run_plan(
            OperationKind::Deploy,
            planned_hosts,
            convert_to.is_none(),
            is_local_target,
        );
        let mut planned_hosts = run_plan.targets;
        if matches!(run_plan.workspace_mode, WorkspaceMode::SingleHost) {
            let logger = Logger::terminal();
            let ctx = planned_hosts.remove(0);
            let install_workspace_mode = WorkspaceMode::SingleHost;
            let mut install_workspace = workspace::prepare_workspace_for_context(
                &ctx,
                install_workspace_mode,
                logger.clone(),
            )?;

            let run_state = RunState::default();
            let exec_ctx = crate::runner::HostExecutionContext {
                logger: logger.clone(),
                redeploy,
                overwrite,
                convert_to,
                switch_action: None,
                home_manager: false,
                run_state: &run_state,
            };

            crate::runner::execute_host_operation(
                &ctx,
                OperationKind::Deploy,
                &exec_ctx,
                &mut install_workspace,
            )?;
            return Ok(());
        }

        let common_workspace = Arc::new(workspace::CommonSourceWorkspace::prepare(
            Logger::terminal(),
        )?);
        let run_state = RunState::default();
        batch::BatchRunner::deploy_batch(
            planned_hosts,
            redeploy,
            overwrite,
            convert_to.cloned(),
            common_workspace,
            run_state,
            parallel,
        )
        .await?;
    } else if let Some(host) = target {
        println!("Loading configuration for target {}...", host);
        let mut ctx = load_context_from_spec(host)?;
        let deployment_start = std::time::Instant::now();
        let logger = Logger::terminal();
        let mode = DeploymentMode::from_context(&ctx, convert_to.is_some());

        // 1. Dry run / planning output
        if plan {
            ctx.target_ip = resolve_target_ip_for_deploy(&ctx, logger.clone());
            let provider = resolve_provider(&ctx, logger.clone());
            let has_provider = provider.is_some();
            let provider_exists = provider.map(|p| p.exists()).unwrap_or(false);

            let host_plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
                ctx: &ctx,
                operation: crate::plan::OperationKind::Deploy,
                redeploy,
                overwrite,
                convert_to,
                switch_action: None,
                home_manager: false,
                provider_exists,
                has_provider,
            });

            println!(
                "================ Planning for {} ================",
                ctx.hostname
            );
            host_plan.render(&ctx, convert_to);
            return Ok(());
        }

        // 2. Resolve target IP and perform provider checking and confirmation.
        ctx.target_ip = resolve_target_ip_for_deploy(&ctx, logger.clone());
        let provider = resolve_provider(&ctx, logger.clone());
        let has_provider = provider.is_some();
        let provider_exists = provider.as_ref().map(|p| p.exists()).unwrap_or(false);

        let host_plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
            ctx: &ctx,
            operation: crate::plan::OperationKind::Deploy,
            redeploy,
            overwrite,
            convert_to,
            switch_action: None,
            home_manager: false,
            provider_exists,
            has_provider,
        });

        if let Some(ref reason) = host_plan.skip_reason {
            println!("{}", reason);
            return Ok(());
        }

        if !crate::plan::confirm_batch(&[host_plan], force)? {
            if redeploy {
                println!("Redeployment aborted by user.");
            } else {
                println!("Deployment aborted by user.");
            }
            return Ok(());
        }

        crate::operation::plan_iso::ensure_proxmox_iso(&ctx, logger.clone())?;

        let install_ctx = resolve_install_context(&ctx, &mode, convert_to)?;

        let install_workspace_mode = if is_local_target(&install_ctx) {
            WorkspaceMode::SingleHost
        } else {
            WorkspaceMode::CommonBasePerHost
        };
        let mut install_workspace = workspace::prepare_workspace_for_context(
            &install_ctx,
            install_workspace_mode,
            logger.clone(),
        )?;

        let run_state = RunState::default();
        let exec_ctx = crate::runner::HostExecutionContext {
            logger: logger.clone(),
            redeploy,
            overwrite,
            convert_to,
            switch_action: None,
            home_manager: false,
            run_state: &run_state,
        };

        crate::runner::execute_host_operation(
            &ctx,
            OperationKind::Deploy,
            &exec_ctx,
            &mut install_workspace,
        )?;

        print_elapsed_summary("Deployment successfully", deployment_start.elapsed());
    } else {
        return Err(
            "Error: Specify either --target <hostname> or --hosts <comma-separated-list>.".into(),
        );
    }
    Ok(())
}
