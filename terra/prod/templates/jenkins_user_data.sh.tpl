#!/bin/bash
set -euxo pipefail

# Update system
apt-get update -y
apt-get upgrade -y

# Install Java 21 (Jenkins minimum version requirement is now Java 21)
apt-get install -y openjdk-21-jdk

# Install Jenkins
mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# Install Docker
apt-get install -y docker.io
usermod -aG docker jenkins

# Install AWS CLI
apt-get install -y awscli

# Install Git
apt-get install -y git

# Configure Jenkins to run behind a reverse proxy at /jenkins/
# This sets the prefix so Jenkins serves at http://<ip>:8080/jenkins/
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'CONF'
[Service]
Environment="JENKINS_OPTS=--prefix=/jenkins"
CONF

# Reload and start services
systemctl daemon-reload
systemctl enable docker
systemctl start docker
systemctl enable jenkins
systemctl restart jenkins
