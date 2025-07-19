
# Manual Verification Steps for Jenkins Setup on RHEL (EC2)

## 1. Check Jenkins Service Status
SSH into the EC2 instance:

```bash
sudo systemctl status jenkins
```

You should see:
```
Active: active (running)
```

---

## 2. Check Jenkins Admin User Creation
Check if the Groovy script exists:

```bash
sudo ls -l /var/lib/jenkins/init.groovy.d/basic-security.groovy
```

View its contents:

```bash
sudo cat /var/lib/jenkins/init.groovy.d/basic-security.groovy
```

Make sure it contains your `jenkins_admin_user` and `jenkins_admin_password`.

---

## 3. Initial Admin Password File (Jenkins Default)
Check if the initial password file exists:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

> Note: This may be unused if your Ansible script created the admin user.

---

## 4. Firewall Port Check
Make sure Jenkins port (default: 8080) is open:

```bash
sudo firewall-cmd --list-ports
```

Expected output:
```
8080/tcp
```

If not, run:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## 5. Access Jenkins in Browser

Navigate to:

```
http://<your-ec2-public-ip>:8080
```

Login with:

- **Username:** from `group_vars/all.yml` → `jenkins_admin_user`
- **Password:** from `group_vars/all.yml` → `jenkins_admin_password`

You should directly see the Jenkins dashboard.

---

## Optional: Test a Jenkins Job

1. Click **"New Item"**
2. Select **"Freestyle project"**
3. Add a shell step:
   ```bash
   echo "Jenkins setup verified"
   ```
4. Save and run the job.
