#!/bin/bash
set -e -x

# Install Java for Jenkins
sudo yum install -y java-1.8.0-openjdk

# Config jenkins user on slave node
sudo useradd --home-dir /home/jenkins --create-home --shell /bin/bash jenkins
sudo mkdir /home/jenkins/jenkins-slave
sudo chown -R jenkins:jenkins /home/jenkins

# Get dependencies from master node
wget -P /home/opc/tmp ${jenkins_master_url}/jnlpJars/jenkins-cli.jar
wget -P /home/opc/tmp ${jenkins_master_url}/jnlpJars/slave.jar
sudo mv /home/opc/tmp/slave.jar /home/jenkins/jenkins-slave/

# Get Jenkins User Password
sudo mv /home/opc/initialUserPassword /home/jenkins/initialUserPassword
USER=$(sudo bash -c "cat /home/jenkins/initialUserPassword | grep JENKINS_USER | cut -d'=' -f2")
PASS=$(sudo bash -c "cat /home/jenkins/initialUserPassword | grep JENKINS_PASS | cut -d'=' -f2")

# Give default username and password if initialUserPassword file is not provided
[[ -z "$PASS" ]] && export USER="admin" || export USER=$USER
[[ -z "$PASS" ]] && export PASS="admin" || export PASS=$PASS

# Register node as Slave
cat <<EOF | java -jar /home/opc/tmp/jenkins-cli.jar -s ${jenkins_master_url} -auth admin:$PASS create-node $1
<slave>
  <name>$1</name>
  <remoteFS>/home/jenkins</remoteFS>
  <numExecutors>2</numExecutors>
  <launcher class="hudson.slaves.JNLPLauncher" />
  <label>build</label>
</slave>
EOF


export TOKEN=$(curl --user "$USER:$PASS" -s ${jenkins_master_url}/crumbIssuer/api/json | python -c 'import sys,json;j=json.load(sys.stdin);print j["crumbRequestField"] + "=" + j["crumb"]')

cat > /home/opc/secret.groovy <<EOF
for (aSlave in hudson.model.Hudson.instance.slaves) {
  if (aSlave.name == "$1") {
    println aSlave.name + "," + aSlave.getComputer().getJnlpMac()
  }
}
EOF

export SECRET=$(curl --user "$USER:$PASS" -d "$TOKEN" --data-urlencode "script=$(</home/opc/secret.groovy)" ${jenkins_master_url}/scriptText | awk -F',' '{print $2}')

# Run from service definition
sudo chown -R jenkins:jenkins /home/jenkins/jenkins-slave
cmd="java -jar /home/jenkins/jenkins-slave/slave.jar -jnlpUrl ${jenkins_master_url}/computer/$1/slave-agent.jnlp -secret $SECRET"
echo $cmd
nohup sudo -u jenkins $cmd &>/home/opc/jenkins.log &

sleep 10

# Echo Master admin init password for login
echo "Jenkins Master Login User/Password: $USER/$PASS"
