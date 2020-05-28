# Confluent Secret Protection

## Passphrase and Master Key

The passphrase is used to generate or change the master key. It is highly recommended to store the passphrase in a secure vault.

Passphrase:

        confluent

The `confluent secrets` command uses the environment variable `CONFLUENT_SECURITY_MASTER_KEY` to encrypt and decrypt sensitive configuration settings. This environment variable needs to be in scope for any process that needs to decrypt configuration secrets.

WARNING: Confluent server needs to run with this evironment variable in scope, so it has been added to the systemd service and is visible to anyone with access to the command `systemctl cat confluent-server`. In production, you should lock down who has access to `systemctl` restricting file permissions on `/bin/systemctl`.

## Documentation

For more information, see [the Confluent secrets documentation](https://docs.confluent.io/current/security/secrets.html)