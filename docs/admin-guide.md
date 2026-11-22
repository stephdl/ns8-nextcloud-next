# Admin guide

This guide is for the NS8 administrator who runs the module. The person who uses Nextcloud
has its own [user guide](user-guide.md). How the module works inside is in
[architecture](architecture.md).

The examples use the instance `nextcloud-next1`.

## Install

```sh
add-module ghcr.io/stephdl/nextcloud-next:latest 1
```

The output of the command returns the instance name:

```text
{'module_id': 'nextcloud-next1', 'image_name': 'nextcloud-next', 'image_url': 'ghcr.io/stephdl/nextcloud-next:latest'}
```

The module does not start until it is configured.

## Status page

The Status page of the module shows the host name with a link to Nextcloud, the node, the
backup, the system logs, the failed services, the images and the volumes. **Restart
application** restarts every container of the module. Nextcloud is unavailable for a few
seconds.

## Configure

Fill in the Settings page, or run `configure-module`:

```sh
api-cli run module/nextcloud-next1/configure-module --data - <<EOF
{
    "host": "cloud.example.org",
    "lets_encrypt": true,
    "domain": "ad.example.org",
    "password": "Admin-pass-2026",
    "internal_smarthost": false
}
EOF
```

The first run installs Nextcloud and takes a few minutes.

### Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `host` | yes | Host name of Nextcloud. Traefik routes it to the module, and it is the only trusted domain. |
| `internal_smarthost` | yes | `false`: the cluster smarthost settings are applied at each start. `true`: mail is set in the Nextcloud admin panel. See [Mail](#mail). |
| `lets_encrypt` | no | Request a Let's Encrypt certificate for `host`. Needs a public DNS name pointing to the node. |
| `domain` | no | User domain of the cluster. Empty means local Nextcloud accounts only. |
| `password` | no | Password of the `admin` account, used only at the first install. Default `Nethesis,1234`. |
| `collabora_host` | no | Host name of a Collabora instance. See [Collabora Online](#collabora-online). |
| `tls_verify_collabora` | no | Verify the certificate of Collabora. |
| `exapps` | no | Run the deploy daemon of External Apps. Default `false`. See [External Apps](#external-apps). |

Each run of `configure-module` restarts every container of the module. Users lose their
session for about a minute.

### Admin password

Nextcloud reads `password` only when it installs itself, at the first start. After that,
changing the field does not change the `admin` account. Change it in Nextcloud, or:

```sh
runagent -m nextcloud-next1 occ user:resetpassword admin
```

## User domain

Set `domain` to a user domain of the cluster, internal or external, OpenLDAP or Active
Directory. Nextcloud then reads its users and groups through ldapproxy. The LDAP settings
are written again at each start of `nextcloud-app`, so a change made in the Nextcloud LDAP
page does not last.

Users log in with:

- OpenLDAP: `uid` or `mail`.
- Active Directory: `sAMAccountName` (`john`) or `userPrincipalName` (`john@ad.example.org`).

### Mail address of AD users

With Active Directory, Nextcloud takes the mail address of a user from `userPrincipalName`
by default. That is the AD login, not always the real mail address. To read the `mail`
attribute instead, and to let users log in with it too:

```sh
runagent -m nextcloud-next1 python3 -c "import agent; agent.set_env('LDAP_MAIL_ATTRIBUTE', 'mail')"
runagent -m nextcloud-next1 systemctl --user restart nextcloud-app
```

This variable has no effect with OpenLDAP, which always uses `mail`. A restore does not keep
it: set it again on the restored instance.

### Find the ID of a user

LDAP users have an internal Nextcloud ID, a UUID, not their login name:

```sh
runagent -m nextcloud-next1 occ user:list
```

```text
  - admin: admin
  - 0A1B2C3D-0000-4000-8000-000000000001: John Doe (john.doe)
```

Use that ID in every `occ` command about a user.

### Change the user domain

Set the new domain in Settings. The module binds it and writes the new LDAP settings.
Clearing the field does not remove the old LDAP configuration from Nextcloud. To stop using
LDAP:

```sh
runagent -m nextcloud-next1 occ ldap:set-config s01 ldapConfigurationActive 0
```

## Mail

With `internal_smarthost` set to `false`, the module copies the cluster smarthost settings to
Nextcloud at each start of `nextcloud-app`, and again when the smarthost changes. Mail goes
out as `no-reply@<domain of host>`. A self-signed smarthost certificate is accepted when the
smarthost is set to skip the TLS check.

With `false` and no cluster smarthost, the module deletes the SMTP settings typed in the
Nextcloud admin panel.

With `true`, the module does not touch the mail settings. Set them in
**Administration settings > Basic settings**.

## Collabora Online

Install the Collabora module on the cluster first. Then pick it in Settings, or set
`collabora_host` to its host name. The module installs and enables the **Nextcloud Office**
app (`richdocuments`) and points it to `https://<collabora_host>`. Leave
`tls_verify_collabora` off only when Collabora has a self-signed certificate.

Clearing the field does not disable the app. Disable it in Nextcloud if needed.

## External Apps

External Apps (ExApps) are Nextcloud apps shipped as containers, mostly in Python. Most of
them run AI on the server, without sending data to an outside service. Examples: Local
Machine Translation (`translate2`), Speech-To-Text (`stt_whisper2`), the local model of
Nextcloud Assistant (`llm2`).

Turn on **External Apps** in Settings, or set `exapps` to `true`. The module then starts
HaRP, the proxy of AppAPI, and registers it as the default deploy daemon `harp_proxy`.
Install ExApps from the Nextcloud app store, under **External apps**, like any other app.

Things to know before you turn it on:

- The images are large. `translate2` takes about 3 GB. They live in the home of the module
  user, on the disk of the node.
- ExApps run on the CPU. There is no GPU access. Translation works well, a local language
  model answers in minutes.
- ExApps and their data are not in the backup. Install them again after a restore.
- HaRP controls the containers of the module user through the podman API. It runs without
  SELinux isolation on Rocky Linux, because SELinux blocks the socket otherwise.

Turning the feature off stops HaRP and the ExApps. Their containers and data stay, so
turning it on again brings them back. To remove an ExApp for good, remove it in Nextcloud
first.

After a reboot or a restart of the module, the ExApps start again, except those disabled in
Nextcloud.

## Two-factor authentication

See the [Nextcloud documentation](https://docs.nextcloud.com/server/stable/admin_manual/configuration_user/two_factor-auth.html)
for every option. The TOTP app is part of Nextcloud. Users set it up themselves, see the
[user guide](user-guide.md#two-factor-authentication).

Enforce it for every user:

```sh
runagent -m nextcloud-next1 occ twofactorauth:enforce --on
```

Users without a second factor must set it up at their next login. To limit it to some
groups, add `--group <group>` or `--exclude <group>`. Check the policy with
`occ twofactorauth:enforce`, stop it with `occ twofactorauth:enforce --off`.

### A user lost the authenticator app

```sh
runagent -m nextcloud-next1 occ twofactorauth:disable 0A1B2C3D-0000-4000-8000-000000000001 totp
```

This deletes the TOTP secret, so the old entry in the app stops working. At the next login
the user sets up TOTP again with a new QR code: at once when TOTP is enforced, otherwise in
**Personal settings > Security**. Backup codes do not count as a second factor and do not
skip this step.

Check the result:

```sh
runagent -m nextcloud-next1 occ twofactorauth:state 0A1B2C3D-0000-4000-8000-000000000001
```

Do not run `occ twofactorauth:cleanup totp`: it removes TOTP for every user.

## Run occ

```sh
runagent -m nextcloud-next1 occ <args>
```

Examples: `occ status`, `occ setupchecks`, `occ app:list`, `occ user:list`.

## Tune PHP-FPM

The FPM pool settings are in `zzz_nethserver.conf`, in the module state:

```sh
runagent -m nextcloud-next1 vi zzz_nethserver.conf
runagent -m nextcloud-next1 systemctl --user restart nextcloud-app
```

The default is `pm.max_children = 50`. A module update and a restore write the file again
with the defaults. Keep a note of your changes.

PHP has a memory limit of 1024M. Uploads are limited to 10G by nginx.

## Database maintenance

Some database fixes that Nextcloud asks for are too slow to run during an update. Run them
outside office hours:

```sh
runagent -m nextcloud-next1 nextcloud-db-optimize
```

The script reads `occ setupchecks` and runs only the fixes it reports: the row format of the
tables, pending mimetype migrations, and missing indices.

## Backup and restore

The cluster backup holds the `nextcloud-app-data` volume, with the files of every user, the
Nextcloud code and `config.php`. It also holds a dump of the database, taken with
`mariadb-dump` at the start of the backup, and the module settings. Redis is not saved: it
only holds caches and locks.

Users can keep working during the backup. A file uploaded while the backup runs may be in
the volume but not in the dump, or the reverse. Run the backup at night.

### Restore

The restore creates a new instance, for example `nextcloud-next2`, on the node you choose.
MariaDB loads the dump at its first start, then the module runs `configure-module` with the
saved settings. Let's Encrypt is turned off on the restored instance. Turn it on again in
Settings once the host name points to the node.

The restored instance keeps the same host name. When the old instance still runs, both
answer on the same name and Traefik picks one. Remove the old instance, or give the new one
another host name.

Not restored: `LDAP_MAIL_ATTRIBUTE`, changes to `zzz_nethserver.conf`, and External Apps.
Set them again.

### Clone and move

Clone copies the volumes to a new instance with the same settings. It has the same problem
of two instances on one host name. Move keeps everything and removes the source.

## Update

```sh
update-module nextcloud-next1
```

The update restarts the containers. At its first start the new `nextcloud-app` image runs
the Nextcloud upgrade itself, and MariaDB upgrades its system tables. Users see a
maintenance page until it ends.

Nextcloud cannot skip a major version. Update one major version at a time.

## Uninstall

```sh
remove-module --no-preserve nextcloud-next1
```

This deletes the volumes, so every file and the database.

## Troubleshooting

**Nextcloud says "Access through untrusted domain".** The browser used a name other than
`host`. Use `host`, or change it in Settings.

**Setup checks say the last background job ran 56 years ago.** The instance is new. Cron
runs every 5 minutes inside `nextcloud-app`. Look again after that.

**LDAP users cannot log in.** Check the user domain in the cluster, then:

```sh
runagent -m nextcloud-next1 occ ldap:test-config s01
```

**A service is down.**

```sh
runagent -m nextcloud-next1 systemctl --user --failed
runagent -m nextcloud-next1 podman logs --tail 50 nextcloud-app
```

Each container logs to the journal under its own name: `nextcloud-app`, `nextcloud-db`,
`nextcloud-redis`, `nextcloud-nginx`, `nextcloud-notify_push`. The logs of every instance
on the node use the same names, so filter by time or use `podman logs` as above.
