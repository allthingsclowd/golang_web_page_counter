#!/usr/bin/env bash

generate_certificate_config () {
  if [ ! -d /${ROOTCERTPATH}/consul.d ]; then
    sudo mkdir --parents /${ROOTCERTPATH}/consul.d
  fi

  sudo tee /${ROOTCERTPATH}/consul.d/consul_ssl_setup.hcl <<EOF

datacenter = "hashistack1"
data_dir = "/usr/local/consul"
encrypt = "${ConsulKeygenOutput}"
log_level = "INFO"
server = ${1}
node_name = "${HOSTNAME}"
addresses {
    https = "0.0.0.0"
}
ports {
    https = 8321
    http = -1
    grpc = 8502
}
connect {
    enabled = true
}
enable_central_service_config = true
verify_incoming = true
verify_outgoing = true
key_file = "${2}"
cert_file = "${3}"
ca_file = "${4}"
EOF


}

setup_environment () {
  set -x
  sleep 5
  source /usr/local/bootstrap/var.env

  
  IFACE=`route -n | awk '$1 == "192.168.9.0" {print $8;exit}'`
  CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.9" {print $2}'`
  IP=${CIDR%%/24}
  
  # export ConsulKeygenOutput=`/usr/local/bin/consul keygen` [e.g. mUIJq6TITeenfVa2yMSi6yLwxrz2AYcC0dXissYpOxE=]

  if [ -d /vagrant ]; then
    LOG="/vagrant/logs/consul_${HOSTNAME}.log"
  else
    LOG="consul.log"
  fi

  if [ "${TRAVIS}" == "true" ]; then
    ROOTCERTPATH=tmp
    IP=${IP:-127.0.0.1}
  else
    ROOTCERTPATH=etc
  fi

  export ROOTCERTPATH

}

configure_ssh_CAs () {

  export BootstrapSSHTool="https://raw.githubusercontent.com/allthingsclowd/BootstrapCertificateTool/${certbootstrap_version}/scripts/Generate_Access_Certificates.sh"

  # Generate OpenSSH Certs
  wget -O - ${BootstrapSSHTool} | bash -s "hashistack" "iac4me" ",81.143.215.2"
    

}

install_consul () {
  AGENT_CONFIG="-config-dir=/${ROOTCERTPATH}/consul.d -enable-script-checks=true"

  # sudo /usr/local/bootstrap/scripts/create_certificate.sh consul hashistack1 30 ${IP} client
  export BootStrapCertTool="https://raw.githubusercontent.com/allthingsclowd/BootstrapCertificateTool/${certbootstrap_version}/scripts/Generate_PKI_Certificates_For_Lab.sh"
  wget -O - ${BootStrapCertTool} | sudo bash -s consul "server.node.global.consul" "client.node.global.consul" "${IP}"
  
  # Configure consul environment variables for use with certificates 
  export CONSUL_HTTP_ADDR=https://127.0.0.1:8321
  export CONSUL_CACERT=/${ROOTCERTPATH}/ssl/certs/consul-ca-chain.pem
  export CONSUL_CLIENT_CERT=/${ROOTCERTPATH}/consul.d/pki/tls/certs/consul-cli.pem
  export CONSUL_CLIENT_KEY=/${ROOTCERTPATH}/consul.d/pki/tls/private/consul-cli-key.pem

  # check for consul hostname or travis => server
  if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
    echo "Starting a Consul Agent in Server Mode"

    generate_certificate_config true "/${ROOTCERTPATH}/consul.d/pki/tls/private/consul-server-key.pem" "/${ROOTCERTPATH}/consul.d/pki/tls/certs/consul-server.pem" "/${ROOTCERTPATH}/ssl/certs/consul-ca-chain.pem"

    /usr/local/bin/consul members 2>/dev/null || {
      if [ "${TRAVIS}" == "true" ]; then

        # Travis-CI grant access to /tmp for all users
        sudo chmod -R 777 /${ROOTCERTPATH}
        sudo /usr/local/bin/consul agent -server -log-level=debug -ui -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1 >${TRAVIS_BUILD_DIR}/${LOG} &
        sleep 5
        sudo ls -al ${TRAVIS_BUILD_DIR}/${LOG}
        sudo cat ${TRAVIS_BUILD_DIR}/${LOG}
      else

        sudo sed -i "/ExecStart=/c\ExecStart=/usr/local/bin/consul agent -server -log-level=debug -ui -client=0.0.0.0 -join=${IP} -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -bootstrap-expect=1" /etc/systemd/system/consul.service
        sudo systemctl enable consul
        sudo systemctl start consul
      fi
      sleep 15
      # upload vars to consul kv
      # ls -al /${ROOTCERTPATH}/consul.d/pki/tls/certs/ /${ROOTCERTPATH}/consul.d/pki/tls/private/ /${ROOTCERTPATH}/ssl/certs /${ROOTCERTPATH}/ssl/private
      echo "Quick test of the Consul KV store - upload the var.env parameters"
      while read a b; do
        k=${b%%=*}
        v=${b##*=}

        consul kv put "development/$k" $v

      done < /usr/local/bootstrap/var.env
    }
  else
    echo "Starting a Consul Agent in Client Mode"
    
    generate_certificate_config false "/${ROOTCERTPATH}/consul.d/pki/tls/private/consul-peer-key.pem" "/${ROOTCERTPATH}/consul.d/pki/tls/certs/consul-peer.pem" "/${ROOTCERTPATH}/ssl/certs/consul-ca-chain.pem"

    /usr/local/bin/consul members 2>/dev/null || {
        
        sudo sed -i "/ExecStart=/c\ExecStart=/usr/local/bin/consul agent -log-level=debug -client=0.0.0.0 -bind=${IP} ${AGENT_CONFIG} -data-dir=/usr/local/consul -join=${LEADER_IP}" /etc/systemd/system/consul.service
        sudo systemctl enable consul
        sudo systemctl start consul
        echo $HOSTNAME
        hostname
        sleep 15
    }
  fi

  /usr/local/bin/consul members

  echo "Consul Service Started"
}

setup_environment
[ ! -z ${TRAVIS} ] ||  configure_ssh_CAs
install_consul
exit 0
