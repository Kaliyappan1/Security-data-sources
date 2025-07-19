# ✅ MySQL Server Setup and Validation (Ansible Automation)

---

## ✅ 1. Re-run the Playbook (Idempotency Test)

Run:

```bash
ansible-playbook -i inventory.ini mysql-setup.yml
```

Check the output:

- If all tasks show `ok:`, it means everything was already applied and your playbook is **idempotent ✅**.
- If you see `changed:` for anything other than `yum clean all`, investigate further.

---

## 🔍 2. Manual Validation Per Task

### 🔸 Subscription Manager Plugin Disabled

```bash
cat /etc/yum/pluginconf.d/subscription-manager.conf | grep enabled
```

Expected:

```text
enabled=0
```

---

### 🔸 MySQL Installed

```bash
mysql --version
```

Should return:

```text
mysql  Ver 8.0.x for Linux on x86_64...
```

---

### 🔸 MySQL Running and Enabled

```bash
systemctl is-active mysqld   # → active
systemctl is-enabled mysqld # → enabled
```

---

### 🔸 MySQL Root Password Set

Login test:

```bash
mysql -u root -p
# Enter: <your-root-password>
```

Should show:

```text
mysql>
```

---

### 🔸 Anonymous Users Removed

Inside MySQL:

```sql
SELECT user, host FROM mysql.user WHERE user = '';
```

Expected:

```text
Empty set
```

---

### 🔸 Remote Root Access Removed

```sql
SELECT user, host FROM mysql.user WHERE user = 'root';
```

Expected: Should **not** contain `%` in the host column.

---

### 🔸 Test DB Removed

```sql
SHOW DATABASES;
```

Expected: `test` should **not** be listed.

---

### 🔸 Splunk User Created

Check:

```sql
SELECT user, host FROM mysql.user WHERE user = '<your-splunk-user>';
```

Expected:

```text
<your-splunk-user>@%
```

Verify login:

```bash
mysql -u <your-splunk-user> -p
# Enter: <your-splunk-password>
```

---

## ✅ 3. MySQL Database & Table Creation Steps

### Step 1: Run Ansible Playbook

```bash
ansible-playbook -i inventory.ini mysql-database-creation.yml
```

---

### Step 2: Login to MySQL

```bash
mysql -u root -p
# Enter: <your-root-password>
```

---

### Step 3: Check if `movies` Database Exists

```sql
SHOW DATABASES;
```

Expected output:

```
+--------------------+
| Database           |
+--------------------+
| information_schema |
| movies             |
| mysql              |
| ...                |
+--------------------+
```

---

### Step 4: Use the `movies` Database

```sql
USE movies;
```

---

### Step 5: Check if `movies` Table Exists

```sql
SHOW TABLES;
```

Expected:

```
+------------------+
| Tables_in_movies |
+------------------+
| movies           |
+------------------+
```

---

### Step 6: Check Table Structure

```sql
DESCRIBE movies;
```

Expected structure:

```
+--------------+-------------+------+-----+---------+-------+
| Field        | Type        | Null | Key | Default | Extra |
+--------------+-------------+------+-----+---------+-------+
| title        | varchar(50) | NO   | PRI | NULL    |       |
| genre        | varchar(30) | NO   |     | NULL    |       |
| director     | varchar(60) | NO   |     | NULL    |       |
| release_year | int         | NO   |     | NULL    |       |
+--------------+-------------+------+-----+---------+-------+
```

---

### Step 7: Validate Inserted Data

```sql
SELECT * FROM movies;
```

Expected output:

```
+-----------+------------------------+--------------------+--------------+
| title     | genre                  | director           | release_year |
+-----------+------------------------+--------------------+--------------+
| Joker     | psychological thriller | Todd Phillips      | 2019         |
| Inception | sci-fi                 | Christopher Nolan  | 2010         |
+-----------+------------------------+--------------------+--------------+
```

---

### Step 8: Exit MySQL

```sql
EXIT;
```