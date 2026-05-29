# mautic-cronjobs

### First - make sure to star and subscribe to the project to get informed about updates to the script. ###

## Description ##
This repository provides shell scripts and environment templates for Mautic cron jobs and long-running messenger workers.

The scripts are designed to live outside the public web root and are configured through a modular environment layout:
* `.env.common` for shared base values
* one process-specific `.env*` file per cron or worker process

This split is important because cron, SES queue workers, generic queue workers and hit/tracking workers need separate lockfiles, log directories and independent lifecycle settings.

The default cron flow still contains a conservative outer loop that helps to stay below transport limits when queued emails are consumed in batches. If your mail transport already throttles internally, use the SES-specific cron and daemon variants instead.

## What changed in version 3 ##
Version 3 adds a more robust base script and separates the available operating modes more clearly:
* hardened `mautic.sh` with stricter env validation, safer path handling and more robust log rotation
* modular `.env.common` plus process-specific `.env` overlays
* optional generic long-running worker via `mautic_daemon.sh`
* optional etailors-specific cron and daemon variants via `mautic_ses_plugin.sh` and `mautic_ses_daemon.sh`
* optional hit/tracking worker via `mautic_hit_daemon.sh`
* example `systemd` unit files for generic, SES and hit worker setups

## Recommended directory layout ##
Recommended installation path:
* scripts: `/opt/mautic-cronjobs`
* logs: `/opt/mautic-cronjobs/logs`
* error logs: `/opt/mautic-cronjobs/errorlogs`

`/opt/mautic-cronjobs` is a good default if you want one dedicated system-level location for scripts, env files, lock files and logs, and it matches the example `systemd` unit files in this repository.

It is also perfectly valid to install the scripts parallel to the Mautic app, as long as they stay outside the public web root or docroot. Typical examples:
* `/var/www/mautic-cronjobs`
* `/var/www/mautic/../mautic-cronjobs`
* `/srv/www/mautic-cronjobs`

The important part is not the exact absolute path, but the layout:
* keep the scripts outside `public/` or the docroot
* keep `.env.common`, the process-specific `.env*` files, lock files and logs in the same dedicated script directory
* make sure the web or worker user can read the scripts and write logs and lock files

## How to install ##
* place the files in your web directory, but not in the public folder or docroot
* copy `.env.common.example` to `.env.common`
* copy the process-specific example file you need and rename it to `.env`, `.env.daemon`, `.env.ses-daemon` or `.env.hit-daemon`
* make the script files executable and owned by the same user that runs Mautic
* make sure the paths are correct
* test drive the relevant script manually
* check the logs

### Example install with wget ###
Create a dedicated directory first:
```bash
mkdir -p /opt/mautic-cronjobs
cd /opt/mautic-cronjobs
```

Download the shared base and cron files from the `beta` branch:
```bash
wget -O mautic.sh https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/mautic.sh
wget -O .env.common.example https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/.env.common.example
wget -O .env.example https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/.env.example
```

Optional files for generic daemon mode:
```bash
wget -O mautic_daemon.sh https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/mautic_daemon.sh
wget -O .env.daemon.example https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/.env.daemon.example
wget -O mautic-worker.service https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/deploy/systemd/mautic-worker.service
```

Optional files for etailors SES mode:
```bash
wget -O mautic_ses_plugin.sh https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/mautic_ses_plugin.sh
wget -O mautic_ses_daemon.sh https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/mautic_ses_daemon.sh
wget -O .env.ses-daemon.example https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/.env.ses-daemon.example
wget -O mautic-ses-worker.service https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/deploy/systemd/mautic-ses-worker.service
```

Optional files for hit/tracking workers:
```bash
wget -O mautic_hit_daemon.sh https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/mautic_hit_daemon.sh
wget -O .env.hit-daemon.example https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/.env.hit-daemon.example
wget -O mautic-hit-worker.service https://raw.githubusercontent.com/twentyZen/mautic-cronjobs/beta/deploy/systemd/mautic-hit-worker.service
```

Then make the downloaded scripts executable:
```bash
chmod +x mautic.sh mautic_daemon.sh mautic_ses_plugin.sh mautic_ses_daemon.sh mautic_hit_daemon.sh
```

## Modular .env layout ##
All script variants load configuration in this order:
1. `.env.common`
2. one process-specific overlay

The second file may override values from `.env.common`. This is intentional.

Use these files:
* `.env.common` for values shared by all processes, for example `PHP_INTERPRETER` and `PATH_TO_CONSOLE`
* `.env` for cron-driven maintenance via `mautic.sh` or `mautic_ses_plugin.sh`
* `.env.daemon` for `mautic_daemon.sh`
* `.env.ses-daemon` for `mautic_ses_daemon.sh`
* `.env.hit-daemon` for `mautic_hit_daemon.sh`

Why split the configuration:
* each process needs its own lockfile
* each process needs its own log directory
* shared lockfiles would block parallel execution through `flock`
* separate logs make diagnosis easier when cron, SES worker and hit worker run independently

Migration from the old single `.env` layout:
* move shared values like `PHP_INTERPRETER` and `PATH_TO_CONSOLE` into `.env.common`
* keep cron-specific values like `LOCKFILE`, `LOG_DIR`, `ERROR_LOG_DIR`, `COMMAND_*` and queue loop settings in `.env`
* move generic daemon settings into `.env.daemon`
* move SES daemon settings into `.env.ses-daemon`
* move hit worker settings into `.env.hit-daemon`

## Example env file ##
* reports and webhook queuing is disabled, set to true if you want to use it
* mail queuing is enabled, set `COMMAND_QUEUE` to false if you send directly without queue
* `COMMAND_ORDER` sets the order of execution of the commands

## Variant for SES plugins with built-in throttling ##
If your Mautic mail transport already throttles outgoing API calls itself, you do not need the outer queue loop from `mautic.sh`.

The etailors Amazon SES plugin explicitly documents:
* built-in rate limiting to honor SES sending quotas
* dynamic batch size matching the current SES max send rate
* throttling outgoing API calls using `usleep()`
* optional override via DSN `ratelimit`

For that setup, use:
* `mautic_ses_plugin.sh`
* `.env.common.example`
* `.env.example` as your starting point for `.env`

This keeps one consumer run per cron execution and leaves per-second SES throttling to the plugin transport during actual queue consumption.

## Variant for generic long-running workers ##
If you want to run `messenger:consume` as a long-running worker without relying on etailors-specific SES throttling, use:
* `mautic_daemon.sh`
* `.env.common.example`
* `.env.daemon.example`
* `deploy/systemd/mautic-worker.service`

This variant is useful for generic Mautic queue workers under `systemd` or `supervisor`. It keeps the existing rate-limited consume pattern from `mautic.sh`, but runs it continuously as a managed worker process.

This is a coarse outer throttling model: it limits how much work one consume cycle may do and then pauses before the next cycle. It does not apply rate limiting directly inside the mail transport itself.

Typical split for this setup:
* run the maintenance commands from `mautic.sh` via cron
* run the queue consumer continuously via `mautic_daemon.sh`

Important notes for this setup:
* `messenger:consume` is still responsible for consuming queued email messages
* the daemon consumes only a limited batch per cycle, then sleeps before starting the next cycle
* this is a conservative outer throttling model, not a strict per-second transport or API rate limiter
* start with one worker and increase only if your transport and infrastructure can handle more parallelism
* if you use this variant, disable queue consumption inside the cron-driven script to avoid mixed consumer topologies
* a dedicated lockfile prevents accidental duplicate starts for the same worker configuration, but it does not turn this model into cross-worker global rate coordination
* use `.env.common.example` plus `.env.daemon.example` and adjust `DAEMON_EMAILS_PER_BATCH`, `DAEMON_QUEUE_TIME_LIMIT`, `DAEMON_QUEUE_DELAY`, `DAEMON_MEMORY_LIMIT`, `DAEMON_LOCKFILE` and `DAEMON_LOG_DIR` to your environment

## Variant for long-running SES workers ##
If you want to run `messenger:consume` as a long-running worker under `systemd` or `supervisor`, use:
* `mautic_ses_daemon.sh`
* `.env.common.example`
* `.env.ses-daemon.example`
* `deploy/systemd/mautic-ses-worker.service`

This variant always uses the explicit transport name `email`. The worker is expected to run continuously, while the service manager restarts it when needed and the SES plugin controls outbound throttling inside the transport during `messenger:consume`.

Typical split for this setup:
* run the maintenance commands from `mautic.sh` or `mautic_ses_plugin.sh` via cron
* run the queue consumer continuously via `mautic_ses_daemon.sh`

### Example systemd setup ###
1. Copy `.env.common.example` to `.env.common`.
2. Copy `.env.ses-daemon.example` to `.env.ses-daemon`.
3. Adjust at least `PHP_INTERPRETER`, `PATH_TO_CONSOLE`, `SES_DAEMON_LOCKFILE`, `SES_DAEMON_LOG_DIR` and `SES_DAEMON_MEMORY_LIMIT`.
4. Optional: set `SES_DAEMON_TIME_LIMIT=3600` if you want regular clean restarts.
5. Make sure `mautic_ses_daemon.sh` is executable and owned by the same user that runs Mautic.
6. Copy `deploy/systemd/mautic-ses-worker.service` to `/etc/systemd/system/mautic-ses-worker.service`.
7. Adjust `User`, `Group`, `WorkingDirectory` and `ExecStart` in the unit file to match your server.
8. Reload systemd and enable the worker:
   `systemctl daemon-reload`
   `systemctl enable --now mautic-ses-worker`
9. Check the worker status and recent logs:
   `systemctl status mautic-ses-worker`
   `journalctl -u mautic-ses-worker -n 100 --no-pager`

Important notes for this setup:
* do not run the queue consumer from cron in parallel to the daemon worker
* keep only the maintenance commands on cron, for example segments, campaigns, imports, broadcasts and reports
* the daemon script writes its own log files and also emits output to `systemd` and `journald`
* if your worker should restart after deployments, use `systemctl restart mautic-ses-worker`
* if you need multiple workers, define them explicitly as separate systemd units or templated instances instead of launching additional unmanaged copies manually
* start with a single worker and increase only if you actually need more throughput
* newer versions of the etailors SES plugin coordinate send rate across workers, but your effective throughput should still be verified against real SES behavior and logs

## Variant for hit/tracking workers ##
If Mautic processes page hits or email opens or clicks asynchronously via messenger transport `hit`, use:
* `mautic_hit_daemon.sh`
* `.env.common.example`
* `.env.hit-daemon.example`
* `deploy/systemd/mautic-hit-worker.service`

This worker always calls `messenger:consume hit` with the transport name explicitly set. Do not omit the transport name, because Mautic may otherwise enter interactive mode or select the wrong transport.

Use this worker whenever `messenger_dsn_hit` points to a Doctrine-backed transport. If no hit worker is running, tracking jobs can pile up in `messenger_messages`.

Important notes for this setup:
* the hit worker uses the same `messenger_messages` table as other Doctrine transports by default
* transport separation happens via `queue_name`, not via a separate `table_name`
* one worker is usually enough because stats processing is latency-tolerant
* start with `HIT_DAEMON_MEMORY_LIMIT="256M"`
* keep `HIT_DAEMON_TIME_LIMIT=3600` unless you have a clear reason to change it
* `systemctl enable --now mautic-hit-worker` is the intended service-manager flow
* for verification, run `messenger:consume hit --limit=1 -vv` and confirm that Mautic reports `Consuming messages from transport "hit"`

Not part of this repository change:
* switching `messenger_dsn_hit` in `config/local.php` from `sync://` to `doctrine://default`
* `cache:clear` and PHP-FPM restart after that Mautic config change
* checking `bin/console debug:messenger` if your actual transport alias differs from `hit`

### Example cron split for daemon mode ###
When `mautic-ses-worker.service` is active, cron should only trigger the maintenance script and not a second queue consumer.

Example crontab:
```cron
*/5 * * * * cd /opt/mautic-cronjobs && /opt/mautic-cronjobs/mautic_ses_plugin.sh >/dev/null 2>&1
```

For this setup, configure `.env` so that the queue consumer is disabled inside the cron-driven script:
```dotenv
COMMAND_QUEUE="messenger:consume email --limit=$EMAILS_PER_BATCH --time-limit=$QUEUE_TIME_LIMIT|false"
```

This keeps:
* cron responsible for segments, campaigns, imports, broadcasts, reports and other scheduled maintenance tasks
* `systemd` responsible for continuous queue consumption

### Notes about the etailors SES plugin ###
The etailors Amazon SES plugin acts as a mail transport and applies rate limiting during actual sending, not while messages are being written into the queue.

That means:
* `messenger:consume` is still required when you use queued email sending
* the plugin throttles outbound SES API calls from inside the consumer process
* long-running workers are a valid setup for this plugin
* recent plugin versions add shared rate coordination across workers, but conservative rollout is still recommended: start with one worker, then scale out only if needed
* compared to the generic non-etailors worker, this is a technically cleaner limit model because throttling happens at the actual transport or API call layer

## Useful settings ##
For now please follow this thread: https://forum.mautic.org/t/a-small-guide-to-send-mails-using-doctrine-for-queue-in-mautic-5/33118/22
If you send directly without queue, which is not recommended, be careful with the batch size. SMTP can only handle up to 10 per call, API differs between mail service providers, for example 50 for Mailjet API v3.

## Locking mechanism ##
The scripts prevent concurrent executions by acquiring an exclusive lock on the relevant lockfile with `flock` from the `util-linux` package.

Important:
* cron, generic daemon, SES daemon and hit daemon must not share the same lockfile
* separate lockfiles are required if you want those processes to run in parallel
* on minimal containers you may need to install `util-linux` manually so that `flock` is available

## Support ##
There is no regular support. Please open a discussion for ideas or questions in https://forum.mautic.org/c/general-discussion/6 and mention user dirk_s. Please only open real issues as git issues for this project.

Have fun - hope it helps.

Your Mautic Friends by twentyZEN GmbH
https://twentyzen.com/
