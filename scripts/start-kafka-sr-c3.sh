#!/bin/bash

# Need to first start directory service UI with
# ~/ApacheDirectoryStudio/ApacheDirectoryStudio &
# then manually start the directory service in the ApacheDS UI

echo -e "\n#################### Starting ZK and CP Server ##################\n"
systemctl start confluent-zookeeper confluent-server

while [[ -z $(nc -z -v mds 8090 2>&1 | grep 'open') ]]; do
    sleep 5
    echo "waiting for MDS to start"
done

export KAFKA_CLUSTER_ID=$(curl -k -s https://mds:8090/v1/metadata/id | jq -r .id)
echo -e "\nKafka Cluster ID: $KAFKA_CLUSTER_ID\n"

echo -e "\n################ Log into CP ###################\n"
expect <<EOF
spawn confluent login --url https://mds:8090
expect "Username: "
send "kafka\r"
expect "Password: "
send "kafka-secret\r"
expect "Logged in as"
EOF

################################### SCHEMA REGISTRY ###################################
echo -e "\nCreating role bindings and starting Schema Registry\n"

# SecurityAdmin on SR cluster itself
confluent iam rolebinding create \
    --principal User:schema-registry \
    --role SecurityAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID \
    --schema-registry-cluster-id schema-registry

# ResourceOwner for groups and topics on broker
for resource in Topic:_schemas Group:schema-registry
do
    confluent iam rolebinding create \
        --principal User:schema-registry \
        --role ResourceOwner \
        --resource $resource \
        --kafka-cluster-id $KAFKA_CLUSTER_ID
done

systemctl start confluent-schema-registry

############################## Control Center ###############################
echo -e "\nCreating role binding and starting Control Center\n"

# C3 only needs SystemAdmin on the kafka cluster itself
confluent iam rolebinding create \
    --principal User:control-center \
    --role SystemAdmin \
    --kafka-cluster-id $KAFKA_CLUSTER_ID

systemctl start confluent-control-center