**Guide – Install Terraform & Ansible and Use Them for OpenVPN Automation**

**Install Terraform**
On Ubuntu (WSL or EC2):

# Update package list
```
sudo apt update && sudo apt upgrade -y
```
# Install required packages
```
sudo apt install -y wget unzip
```
# Download Terraform
```
wget https://releases.hashicorp.com/terraform/1.9.2/terraform_1.9.2_linux_amd64.zip
```
# Unzip and move to /usr/local/bin
```
unzip terraform_1.9.2_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

# Verify
```
terraform -version
```
**Install Ansible**
**On Ubuntu (WSL or EC2):**

# Update package list
```
sudo apt update -y
```
# Install software-properties-common
```
sudo apt install -y software-properties-common
```
# Add Ansible repository
```
sudo add-apt-repository --yes --update ppa:ansible/ansible
```
# Install Ansible
```
sudo apt install -y ansible
```
# Verify
```
ansible --version
```
 **Process Explanation
 What Terraform Does**
  - Terraform is Infrastructure as Code (IaC).

  - It creates AWS resources (EC2, Security Groups, Key Pairs).

  In our case:

  - Launches Ubuntu 22.04 EC2 instance

  - Opens required VPN ports (22, 443, 943, 1194)

  - Generates SSH key (.pem)

  - Creates an inventory file for Ansible

** Command you run:**

```
terraform init
terraform apply -auto-approve
```
** What Ansible Does**

- Ansible is a configuration management tool.

- It connects to the EC2 instance via SSH and installs/configures OpenVPN automatically.

**In our case:**

  - Updates packages

  - Installs OpenVPN Access Server

  - Sets password for users

  - Restarts OpenVPN service

**Command you run:**
```
ansible-playbook -i inventory.ini openvpn.yml
```
** End Result**
  - OpenVPN server is ready on your EC2 instance.

  - Access it in browser:

  - Admin UI → https://<EC2-IP>:943/admin

  1. change Hostname: <your instance public ip>

  - Client UI → https://<EC2-IP>:943/

  - Login with username openvpn or ubuntu and password SoftMania@123.

