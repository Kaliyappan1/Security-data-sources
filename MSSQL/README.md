# ✅ Manual MSSQL Setup Verification Checklist

## 🔹 1. Check MSSQL service status

```bash
sudo systemctl status mssql-server
```
✅ Look for `active (running)`

---

## 🔹 2. Check pip and Python 3.12 setup

```bash
/usr/bin/python3.12 -m pip --version
```
✅ Should return pip version

```bash
/usr/bin/python3.12 -m pip show packaging pexpect
```
✅ Should show both installed packages

---

## 🔹 3. Verify PATH update for SQL tools

```bash
echo $PATH | grep "/opt/mssql-tools/bin"
```
✅ Should include `/opt/mssql-tools/bin`

```bash
which sqlcmd
```

---

## 🔹 4. Test SA login

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Kaliya123!' -C -Q "SELECT @@VERSION;"
```
✅ Should return SQL Server version info

---

## 🔹 5. Verify TestDB is created

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Kaliya123!' -C \
-Q "SELECT name FROM sys.databases WHERE name = 'TestDB';"
```
✅ Should return `TestDB`

---

## 🔹 6. Verify Inventory table and data

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Kaliya123!' -C -d TestDB \
-Q "SELECT * FROM dbo.Inventory;"
```
✅ Should return 5 rows of data

---

## 🔹 7. Verify contained database authentication is enabled

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Kaliya123!' -C \
-Q "EXEC sp_configure 'contained database authentication';"
```
✅ `config_value` and `run_value` should be `1`

---

## 🔹 8. Check user Test123 exists

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Kaliya123!' -C -d TestDB \
-Q "SELECT name FROM sys.database_principals WHERE name = 'Test123';"
```
✅ Should return `Test123`

---

## 🔹 9. Test login as Test123

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U Test123 -P 'Admin@1234' -C -d TestDB \
-Q "SELECT TOP 1 * FROM dbo.Inventory;"
```
✅ Should return 1 row# mssql-codebuild-automation
