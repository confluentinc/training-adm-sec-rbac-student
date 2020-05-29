#!/bin/bash

# Exit on error
set -e

# Ensure script fails if student source directory doesn't exist.
# Requires student to git clone https://github.com/training-adm-sec-rbac-student /home/training/rbac

GITHUB_SOURCE=https://github.com/training-adm-sec-rbac-student
SOURCE_DIR=/home/training/rbac
if [ ! -d "$SOURCE_DIR" ]; then
  echo "
  Directory $SOURCE_DIR doesn't exist. Make sure to
  git clone $GITHUB_SOURCE $SOURCE_DIR"
  exit 1
fi
cd $SOURCE_DIR


# Encrypt configuration secrets with confluent secrets

echo "
Encrypting properties files with confluent secrets
"

CONFLUENT_SECURITY_MASTER_KEY=$(confluent secret master-key generate \
    --local-secrets-file $SOURCE_DIR/security/secrets/secrets.properties  \
    --passphrase confluent | awk '/Master Key/ {print $5}')

# Make master key accessible to training user so student can use confluent secret CLI
echo "export CONFLUENT_SECURITY_MASTER_KEY=$CONFLUENT_SECURITY_MASTER_KEY" >> /home/training/.bashrc
chmod 640 /home/training/.bashrc

# Encrypt all properties containing "password"
for i in $SOURCE_DIR/client-properties/*.properties $SOURCE_DIR/cp-properties/*.properties; do
    confluent secret file encrypt --config-file "$i" \
        --local-secrets-file $SOURCE_DIR/security/secrets/secrets.properties \
        --remote-secrets-file $SOURCE_DIR/security/secrets/secrets.properties; done

# Encrypt ldap.java.naming.security.credentials property
for i in $SOURCE_DIR/challenges/server.properties $SOURCE_DIR/solutions/server.properties $SOURCE_DIR/cp-properties/server.properties; do
    confluent secret file encrypt \
    --config-file $i \
    --config ldap.java.naming.security.credentials \
    --local-secrets-file $SOURCE_DIR/security/secrets/secrets.properties \
    --remote-secrets-file $SOURCE_DIR/security/secrets/secrets.properties; done



# Link server properties files to files in $SOURCE_DIR/cp-properties.
# This allows systemd services to run without overriding ExecStart

echo "
Creating symbolic links from /etc/kafka/ to $SOURCE_DIR/cp-properties/
"

ln -sf $SOURCE_DIR/cp-properties/server.properties /etc/kafka/server.properties
ln -sf $SOURCE_DIR/cp-properties/zookeeper.properties /etc/kafka/zookeeper.properties
ln -sf $SOURCE_DIR/cp-properties/control-center.properties /etc/confluent-control-center/control-center-production.properties
ln -sf $SOURCE_DIR/cp-properties/schema-registry.properties /etc/schema-registry/schema-registry.properties
ln -sf $SOURCE_DIR/cp-properties/connect-avro-distributed.properties /etc/kafka/connect-distributed.properties
ln -sf $SOURCE_DIR/cp-properties/ksql-server.properties /etc/ksqldb/ksql-server.properties
ln -sf $SOURCE_DIR/cp-properties/kafka-rest.properties /etc/kafka-rest/kafka-rest.properties



# Create systemd override files for kafka <-> zookeeper SASL authentication.
# Systemd services must have access to the confluent secret master key to decrypt properties at runtime
# TODO: kafka <-> zookeeper mutual TLS instead of SASL

echo "
Modifying systemd unit files to include KAFKA_OPTS and CONFLUENT_SECURITY_MASTER_KEY
"

cat << EOF > /etc/systemd/system/confluent-zookeeper.service.d/override.conf
[Service]
Environment="KAFKA_OPTS=-Djava.security.auth.login.config=$SOURCE_DIR/cp-properties/zookeeper.jaas"
EOF

cat << EOF > /etc/systemd/system/confluent-server.service.d/override.conf
[Service]
Environment="KAFKA_OPTS=-Djava.security.auth.login.config=$SOURCE_DIR/cp-properties/zookeeper-client.jaas"
Environment="CONFLUENT_SECURITY_MASTER_KEY=$CONFLUENT_SECURITY_MASTER_KEY"
EOF



# Generate TLS certs, keys, keystores, and truststores
## Make sure keystores have proper permissions

echo "
Generating TLS certs, keys, keystores, and truststores with proper permissions
"

chmod +x $SOURCE_DIR/security/tls/tls-setup.sh
$SOURCE_DIR/security/tls/tls-setup.sh
chown cp-kafka:confluent $SOURCE_DIR/security/tls/**/*.keystore*
chmod 400 $SOURCE_DIR/security/tls/**/*.keystore*



# Add ca.crt to system certs under /usr/local/share/ca-certificates/confluent
# Doing this makes it so the confluent CLI and ldap clients implicitly trust our CA

mkdir /usr/share/ca-certificates/confluent
cp $SOURCE_DIR/security/tls/certificate-authority/ca.crt /usr/share/ca-certificates/confluent
update-ca-certificates



# Create keypair for token service

echo "
Creating keypair for token authorization service with proper permissions
"

rm -rf $SOURCE_DIR/security/token/*
openssl genrsa -out $SOURCE_DIR/security/token/tokenKeypair.pem 2048
openssl rsa -in $SOURCE_DIR/security/token/tokenKeypair.pem \
    -outform PEM -pubout -out $SOURCE_DIR/security/token/public.pem

chown cp-kafka:confluent $SOURCE_DIR/security/token/tokenKeypair.pem 
chmod 400 $SOURCE_DIR/security/token/tokenKeypair.pem

echo "
Complete! See instructions to create a secure LDAPS connection and import user and group data.
"

# Manual prerequisite steps for students after running this script:
## 1. Create ldap server in Apache Directory Studio configured with keystore from
### /home/training/rbac/security/tls/directory-service/directory-service.keystore.p12
## 2. Create an ldaps connection
## 3. Import the confluent company ldif file