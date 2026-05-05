# mautic-cronjobs

### First - make sure to star and subscribe to the project to get informed about updates to the script. ###

## Description ##
This script and environment file helps to manage cron jobs for Mautic. 
It’s split into two parts, so you can easily exchange the script later on. You configure the bash script via the `.env` file. Load it into your Mautic webproject outside of the public or docroot folder. Adjust the paths according to your setup. Define where logs should be saved to.

It also contains an algorithm, that helps to comply with rate limits e.g. of AWS SES. It’s a simple approach, which should work fine for most installations. However, if high volumes of mail and performance is important, then you might want to tweak it a bit.

The example in the default setup is made for 14 mails / sec. limit. It sends up to 14 mails and up to 1 sec in one loop. If there are still mails in the queue to be sent, it will wait for a second and send again up to the max amount of loops defined for one cronjob run. This way it never sends more than 14 mails per second, as it waits for a second after first send. Of course we could wait less, as sending takes some time. But this is the safe path.

## How to install ##
* place the files in your web directory, but not in the public folder (or docroot)
* edit the `.env.example` file and copy it as `.env` in the same folder as the script file `mautic.sh`
* make the mautic.sh file executable with chmod +x, check the ownership of the file as well (should be your webprojects user)
* make sure, you set the paths correctly
* test drive manually by running mautic.sh
* check the logs

## Example env file ##
* reports and webhook queuing is disabled, set to true if you want to use it
* mail queuing is enabled, set COMMAND_QUEUE to false, if you send directly without queue
* COMMAND_ORDER sets the order of execution of the commands

## Variant for SES plugins with built-in throttling ##
If your Mautic mail transport already throttles outgoing API calls itself, you do not need the outer queue loop from `mautic.sh`.

The etailors Amazon SES plugin explicitly documents:
* built-in rate limiting to honor SES sending quotas
* dynamic batch size matching the current SES max send rate
* throttling outgoing API calls using `usleep()`
* optional override via DSN `ratelimit`

For that setup, use:
* `mautic_ses_plugin.sh`
* `.env.etailors-ses.example` as your starting point for `.env`

This keeps one consumer run per cron execution and leaves per-second SES throttling to the plugin transport during actual queue consumption.

## Variant for generic long-running workers ##
If you want to run `messenger:consume` as a long-running worker without relying on etailors-specific SES throttling, use:
* `mautic_daemon.sh`
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
* this is a conservative outer throttling model, not a strict per-second transport/API rate limiter
* start with one worker and increase only if your transport and infrastructure can handle more parallelism
* if you use this variant, disable queue consumption inside the cron-driven script to avoid mixed consumer topologies
* a lockfile prevents accidental duplicate starts for the same worker configuration, but it does not turn this model into cross-worker global rate coordination
* use `.env.daemon.example` as a starting point and adjust `DAEMON_EMAILS_PER_BATCH`, `DAEMON_QUEUE_TIME_LIMIT`, `DAEMON_QUEUE_DELAY`, `DAEMON_MEMORY_LIMIT` and `DAEMON_LOCKFILE` to your environment

## Variant for long-running SES workers ##
If you want to run `messenger:consume` as a long-running worker under `systemd` or `supervisor`, use:
* `mautic_ses_daemon.sh`
* `.env.etailors-ses-daemon.example`
* `deploy/systemd/mautic-ses-worker.service` as a starting point

This variant does not set `--limit` or `--time-limit` by default. The worker is expected to run continuously, while the service manager restarts it when needed and the SES plugin controls outbound throttling inside the transport during `messenger:consume`.

Typical split for this setup:
* run the maintenance commands from `mautic.sh` or `mautic_ses_plugin.sh` via cron
* run the queue consumer continuously via `mautic_ses_daemon.sh`

### Example systemd setup ###
1. Copy `.env.etailors-ses-daemon.example` to `.env` and adjust at least `PHP_INTERPRETER`, `PATH_TO_CONSOLE` and `DAEMON_LOG_DIR`.
2. Make sure `mautic_ses_daemon.sh` is executable and owned by the same user that runs Mautic.
3. Copy `deploy/systemd/mautic-ses-worker.service` to `/etc/systemd/system/mautic-ses-worker.service`.
4. Adjust `User`, `Group`, `WorkingDirectory` and `ExecStart` in the unit file to match your server.
5. Reload systemd and enable the worker:
   `systemctl daemon-reload`
   `systemctl enable --now mautic-ses-worker`
6. Check the worker status and recent logs:
   `systemctl status mautic-ses-worker`
   `journalctl -u mautic-ses-worker -n 100 --no-pager`

Important notes for this setup:
* do not run the queue consumer from cron in parallel to the daemon worker
* keep only the maintenance commands on cron, for example segments, campaigns, imports, broadcasts and reports
* the daemon script writes its own log files and also emits output to `systemd`/`journald`
* if your worker should restart after deployments, use `systemctl restart mautic-ses-worker`
* if you need multiple workers, define them explicitly as separate systemd units or templated instances instead of launching additional unmanaged copies manually
* start with a single worker and increase only if you actually need more throughput
* newer versions of the etailors SES plugin coordinate send rate across workers, but your effective throughput should still be verified against real SES behavior and logs

### Example cron split for daemon mode ###
When `mautic-ses-worker.service` is active, cron should only trigger the maintenance script and not a second queue consumer.

Example crontab:
```cron
*/5 * * * * cd /opt/mautic-cronjobs && /opt/mautic-cronjobs/mautic_ses_plugin.sh >/dev/null 2>&1
```

For this setup, configure `.env` so that the queue consumer is disabled inside the cron-driven script:
```dotenv
COMMAND_QUEUE="messenger:consume email --limit=$QUEUE_MESSAGE_LIMIT --time-limit=$QUEUE_TIME_LIMIT|false"
```

This keeps:
* cron responsible for segments, campaigns, imports, broadcasts, reports and other scheduled maintenance tasks
* `systemd` responsible for continuous queue consumption

If you prefer to keep a single `.env` file for the daemon variant, set `COMMAND_QUEUE` to `false` there and let `DAEMON_QUEUE_COMMAND` in `.env` control the long-running worker separately.

### Notes about the etailors SES plugin ###
The etailors Amazon SES plugin acts as a mail transport and applies rate limiting during actual sending, not while messages are being written into the queue.

That means:
* `messenger:consume` is still required when you use queued email sending
* the plugin throttles outbound SES API calls from inside the consumer process
* long-running workers are a valid setup for this plugin
* recent plugin versions add shared rate coordination across workers, but conservative rollout is still recommended: start with one worker, then scale out only if needed
* compared to the generic non-etailors worker, this is a technically cleaner limit model because throttling happens at the actual transport/API call layer

## Useful settings ##
For now please follow this thread: https://forum.mautic.org/t/a-small-guide-to-send-mails-using-doctrine-for-queue-in-mautic-5/33118/22
If you send directly without queue (not recommended) be careful with the batch size. SMTP can only handle up to 10 per call, API differs between Mail Service Providers, e.g. 50 for Mailjet API v3.

## Locking mechanism ##
The script prevents concurrent executions by acquiring an exclusive lock on the file defined by `LOCKFILE`. It uses the `flock` command from the `util-linux` package (preinstalled on most Linux systems). If multiple cron jobs attempt to start simultaneously, the lock ensures only the first one continues. On minimal containers you may need to install `util-linux` manually so that `flock` is available.

## Support ##
There is no regular support. Please open a discussion for ideas / questions in https://forum.mautic.org/c/general-discussion/6 and mention user dirk_s. Please only open real issues as git issues for this project.

Have fun - hope it helps. 

Your Mautic Friends by twentyZEN GmbH
https://twentyzen.com/
