use crate::batch;
use crate::cli::SwitchAction;
use crate::context::{load_batch_contexts, load_context_from_spec, RuntimeContext};
use crate::fleet::local::{current_local_hostname, is_local_target};
use crate::fleet::resolution::resolve_provider;
use crate::plan::{OperationKind, RunState, WorkspaceMode};
use crate::process::Logger;
use crate::workspace;
use std::sync::Arc;

fn print_batch_switch_plan(
    planned_hosts: &[RuntimeContext],
    action: &str,
    hm: bool,
    logger: Logger,
) {
    println!("================ Planning for Batch/Fleet Switch ================");
    for ctx in planned_hosts {
        let provider = resolve_provider(ctx, logger.clone());
        let has_provider = provider.is_some();
        let provider_exists = provider.map(|p| p.exists()).unwrap_or(false);

        let plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
            ctx,
            operation: crate::plan::OperationKind::Switch,
            redeploy: false,
            overwrite: false,
            convert_to: None,
            switch_action: Some(action),
            home_manager: hm,
            provider_exists,
            has_provider,
        });
        plan.render(ctx, None);
    }
    println!("=================================================================");
}

pub async fn execute_switch(
    target: Option<&String>,
    hosts: Option<&String>,
    action: &SwitchAction,
    hm: bool,
    force: bool,
    parallel: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    crate::command::hosts::validate_target_and_hosts(target, hosts)?;

    let action_str = match action {
        SwitchAction::Switch => "switch",
        SwitchAction::Bootentry => "bootentry",
        SwitchAction::Test => "test",
        SwitchAction::Build => "build",
    };

    if let Some(hosts_str) = hosts {
        let host_list = crate::command::hosts::resolve_hosts_arg(hosts_str)?;

        let planned_hosts = load_batch_contexts(&host_list, true)?;

        // 1. Dry run / planning output for Batch Switch
        let logger = Logger::terminal();
        print_batch_switch_plan(&planned_hosts, action_str, hm, logger.clone());

        let mut plans = Vec::new();
        for ctx in &planned_hosts {
            let provider = resolve_provider(ctx, logger.clone());
            let has_provider = provider.is_some();
            let provider_exists = provider.map(|p| p.exists()).unwrap_or(false);

            let plan = crate::plan::plan_host(crate::plan::PlanHostOptions {
                ctx,
                operation: crate::plan::OperationKind::Switch,
                redeploy: false,
                overwrite: false,
                convert_to: None,
                switch_action: Some(action_str),
                home_manager: hm,
                provider_exists,
                has_provider,
            });
            plans.push(plan);
        }

        if !crate::plan::confirm_batch(&plans, force)? {
            println!("Batch switch aborted by user.");
            return Ok(());
        }

        println!("Launching batch switch...");
        let run_plan = crate::plan::build_run_plan(
            OperationKind::Switch,
            planned_hosts,
            true,
            is_local_target,
        );
        let mut planned_hosts = run_plan.targets;
        if matches!(run_plan.workspace_mode, WorkspaceMode::SingleHost) {
            let logger = Logger::terminal();
            let ctx = planned_hosts.remove(0);
            let mut switch_workspace = workspace::prepare_workspace_for_context(
                &ctx,
                WorkspaceMode::SingleHost,
                logger.clone(),
            )?;

            let run_state = RunState::default();
            let exec_ctx = crate::runner::HostExecutionContext {
                logger: logger.clone(),
                redeploy: false,
                overwrite: false,
                convert_to: None,
                switch_action: Some(action_str),
                home_manager: hm,
                run_state: &run_state,
            };

            crate::runner::execute_host_operation(
                &ctx,
                OperationKind::Switch,
                &exec_ctx,
                &mut switch_workspace,
            )?;
            return Ok(());
        }

        let common_workspace = Arc::new(workspace::CommonSourceWorkspace::prepare(
            Logger::terminal(),
        )?);
        let run_state = RunState::default();
        batch::BatchRunner::switch_batch(
            planned_hosts,
            action_str.to_string(),
            hm,
            common_workspace,
            run_state,
            parallel,
        )
        .await?;
    } else {
        let target_host = target.cloned().unwrap_or_else(current_local_hostname);
        if target_host.is_empty() {
            return Err(
                "Error: Could not determine current hostname for default switch target.".into(),
            );
        }

        let t_context_start = std::time::Instant::now();
        let ctx = load_context_from_spec(&target_host)?;
        let t_context_elapsed = t_context_start.elapsed();
        let logger = Logger::terminal();
        let switch_workspace_mode = if is_local_target(&ctx) {
            WorkspaceMode::SingleHost
        } else {
            WorkspaceMode::CommonBasePerHost
        };
        let t_workspace_start = std::time::Instant::now();
        let mut switch_workspace =
            workspace::prepare_workspace_for_context(&ctx, switch_workspace_mode, logger.clone())?;
        let t_workspace_elapsed = t_workspace_start.elapsed();

        let run_state = RunState::default();
        let exec_ctx = crate::runner::HostExecutionContext {
            logger: logger.clone(),
            redeploy: false,
            overwrite: false,
            convert_to: None,
            switch_action: Some(action_str),
            home_manager: hm,
            run_state: &run_state,
        };

        let t_exec_start = std::time::Instant::now();
        let res = crate::runner::execute_host_operation(
            &ctx,
            OperationKind::Switch,
            &exec_ctx,
            &mut switch_workspace,
        );
        let t_exec_elapsed = t_exec_start.elapsed();

        debug!(
            logger,
            "
            Timing breakdown:
              Context loading:         {t_context_elapsed:?}
              Workspace preparation:   {t_workspace_elapsed:?}
              Execution:               {t_exec_elapsed:?}
            "
        );

        res?;
    }
    Ok(())
}
