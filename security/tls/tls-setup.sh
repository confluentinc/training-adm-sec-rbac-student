#!/bin/bash

# Exit on error and don't allow unset (empty) variables
set -o nounset \
    -o errexit \
    -o verbose
#    -o xtrace

#####
##### Initialize Variables #####
#####

# Declare directories for keys, certs, truststores, and keystores
declare -A tls-dirs
tls-dirs[CA]="certificate-authority"
tls-dirs[DS]="directory-service"
tls-dirs[KAFKA]="kafka"
tls-dirs[CLIENT]="kafka-client"

declare -A keystores
# directory service needs keystore for ldaps
keystores[DS]="directory-service"
# kafka needs keystore for TLS encrypted communication with clients
keystores[KAFKA]="kafka"

declare -A truststores
# kafka needs to trust directory service
truststores[KAFKA]="kafka"
# kafka client needs to trust kafka
truststores[CLIENT]="kafka-client"

#####
##### Define Functions #####
#####

# Function to clean up files
function cleanup(){
    for dir in "${tls-dirs[@]}"; do
        echo "cleaning ${dir} directory"
        mkdir ${dir}
        rm ${dir}/*
    done
}

# Function to create a certificate authority key and certificate
function create_ca(){
    echo "creating CA key and certificate"
    openssl req -new -x509 -keyout "${tls-drs[CA]}"/ca.key \
        -out "${tls-drs[CA]}"/ca.crt -days 365 \
        -subj '/CN=ca.confluent.io/OU=TEST/O=CONFLUENT/L=PaloAlto/S=Ca/C=US' \
        -passin pass:confluent -passout pass:confluent
}

# Function to create a private key for a service
function create_private_key(){
    echo "creating private key for ${1}"
    openssl genrsa -out "${1}"/"${1}"-private.key 2048
}

# Function to create a certificate signing request using server private key
# input: service private key
# output: certificate signing request
function create_csr(){
    echo "creating certificate signing request for $1"
    openssl req -new -sha256 \
        -key "${1}"/"${1}"-private.key \
        -out "${1}"/"${1}".csr \
        -subj "/C=US/ST=CA/L=PaloAlto/O=Confluent/OU=training/CN=$1"
}


# Function to create server certificate signed by certificate authority
# input: service's certificate signing request
# output: signed certificate for service
function sign_crt(){
    echo "creating signed certificate for $1"
    openssl x509 -req -CA "${tls-drs[CA]}"/ca.crt -CAkey "${tls-drs[CA]}"/ca.key \
        -in "${1}"/"${1}".csr \
        -out "${1}"/"${1}"-signed.crt \
        -days 9999 -CAcreateserial -passin pass:confluent
}


# Function to make a certificate chain
# input: signed service certificate and CA certificate
function create_cert_chain(){
    echo "creating certificate chain for $1"
    cat "${1}"/"${1}"-signed.crt \
        "${tls-drs[CA]}"/ca.crt > "${1}"/"${1}"-chain.crt
}


# Function to create a .p12 keystore file using cert chain and server private key
function create_keystore(){
    echo "creating keystore for $1"
    openssl pkcs12 -export -in "${1}"/"${1}"-chain.crt \
        -inkey "${1}"/"${1}"-private.key \
        -out "${1}"/"${1}".keystore.p12 \
        -name "${1}" -password pass:confluent
}

function create_truststore(){
        keytool -noprompt -keystore "${1}"/"${1}".truststore.jks \
            -alias CARoot -import -file "${tls-drs[CA]}"/ca.crt \
            -storepass confluent -keypass confluent
}

#####
##### Main Program #####
#####

cleanup

create_ca

for i in "${keystores}"; do
    create_private_key $i
    create_csr $i
    sign_crt $i
    create_cert_chain $i
    create_keystore $i
done

for i in "${truststores}"; do
    create_truststore $i
done