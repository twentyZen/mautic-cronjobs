# mautic-cronjobs

### First - make sure to star and subscribe to the project to get informed about updates to the script. ###

## Description ##
This script and environment file helps to manage cron jobs for Mautic. 
It’s split into two parts, so you can easily exchange the script later on. You configure the bash script via the env file. Load it into your Mautic webproject outside of the public or docroot folder. Adjust the paths according to your setup. Define where logs should be saved to.

It also contains an algorithm, that helps to comply with rate limits e.g. of AWS SES. It’s a simple approach, which should work fine for most installations. However, if high volumes of mail and performance is important, then you might want to tweak it a bit.

The example in the default setup is made for 14 mails / sec. limit. It sends up to 14 mails and up to 1 sec in one loop. If there are still mails in the queue to be sent, it will wait for a second and send again up to the max amount of loops defined for one cronjob run. This way it never sends more than 14 mails per second, as it waits for a second after first send. Of course we could wait less, as sending takes some time. But this is the safe path.

## How to install ##
* place the files in your web directory, but not in the public folder (or docroot)
* edit the env.example file and place it as .env in the same folder as the script file mautic.sh
* make the mautic.sh file executable with chmod +x, check the ownership of the file as well (should be your webprojects user)
* make sure, you set the paths correctly
* test drive manually by running mautic.sh
* check the logs

## Example env file ##
* reports and webhook queuing is disabled, set to true if you want to use it
* mail queuing is enabled, set COMMAND_QUEUE to false, if you send directly without queue
* COMMAND_ORDER sets the order of execution of the commands

## Useful settings ##
For now please follow this thread: https://forum.mautic.org/t/a-small-guide-to-send-mails-using-doctrine-for-queue-in-mautic-5/33118/22
If you send directly without queue (not recommended) be careful with the batch size. SMTP can only handle up to 10 per call, API differs between Mail Service Providers, e.g. 50 for Mailjet API v3.  

## Support ##
There is no regular support. Please open a discussion for ideas / questions in https://forum.mautic.org/c/general-discussion/6 and mention user dirk_s. Please only open real issues as git issues for this project.

Have fun - hope it helps. 

Your Mautic Friends by twentyZEN GmbH
https://twentyzen.com/
