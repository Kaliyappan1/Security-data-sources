## ✅ Post-Deployment Validation Checklist

### 1. Check syslog-ng Service Status
```bash
systemctl status syslog-ng
```
**Expected Output:**
```
Active: active (running)
```

---

### 2. Confirm Splunk Forwarding Configuration
```bash
cat /etc/syslog-ng/syslog-ng.conf | grep -A 5 destination
```
**Expected Output:**
```conf
destination d_splunk {
    network("35.179.4.112" transport("tcp") port(5514));
};
```

---

### 3. Confirm /var/log/secure Exists and is Readable
```bash
ls -l /var/log/secure
```
Ensure it exists with read permissions (e.g., readable by syslog-ng user).

---

### 4. Check Port 5514 is Open on Splunk Server
On the **Splunk server**:
```bash
sudo netstat -tulnp | grep 5514
```
**Expected Output:**
```
tcp  0  0 0.0.0.0:5514  0.0.0.0:*  LISTEN  <splunkd-pid>/splunkd
```

---

### 5. Verify Outgoing Traffic via TCP
On the **Syslog-ng (RHEL 9) sender**:
```bash
sudo tcpdump -nn port 5514 -i any
```
Then trigger a log manually:
```bash
sudo su
exit
```
You should see traffic going to Splunk IP on port 5514.

---

### 6. Confirm Log Reception on Splunk
In **Splunk Web UI**, go to **Search & Reporting**, and run:
```spl
index=* host="<RHEL IP>" sourcetype=syslog
```
You should see log events from the RHEL host.
