# Migration to New Deployment Structure

This document explains the migration from the old flat structure to the new organized structure.

## Changes Summary

### Before (Old Structure)
```
deployments/
├── .env_4g
├── .env_5g
├── .env
├── 4g-data-only-deploy.yaml
├── 5g-data-only-deploy.yaml
├── sa-deploy.yaml
└── ...other files...
```

**Command**:
```bash
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up -d
```

### After (New Structure)
```
deployments/
├── 4g/
│   ├── .env                     # Auto-loaded
│   ├── docker-compose.yaml
│   └── README.md
├── 5g/
│   ├── .env                     # Auto-loaded
│   ├── docker-compose.yaml
│   └── README.md
├── s1n2/
│   ├── .env                     # Auto-loaded
│   └── README.md
└── README.md
```

**Command**:
```bash
cd deployments/4g
docker compose up -d
```

## Benefits

1. ✅ **No `--env-file` option needed** - Docker Compose auto-loads `.env`
2. ✅ **No hardcoded IPs** - All variables in `.env` file
3. ✅ **Better organization** - Each deployment in its own directory
4. ✅ **Clearer documentation** - Deployment-specific READMEs
5. ✅ **Easier maintenance** - Isolated configurations
6. ✅ **Consistent patterns** - All deployments work the same way

## Docker Compose Environment Loading

Docker Compose loads environment variables in this order:

1. **Shell environment variables** (highest priority)
2. **`.env` file in same directory as compose file**
3. **`--env-file` option** (if specified)

By placing `.env` in the same directory as `docker-compose.yaml`, Docker Compose automatically loads it **without any command-line options**.

## Key Differences from Before

### Path Adjustments

In the new structure, paths are relative to `deployments/4g/`:

| Item | Old Path | New Path |
|------|----------|----------|
| Build context | `..` | `../..` |
| Config volumes | `../4g/mme` | `../../4g/mme` |
| Log volumes | `../log` | `../../log` |

### Environment File

| Aspect | Old | New |
|--------|-----|-----|
| Filename | `.env_4g` | `.env` |
| Location | `deployments/` | `deployments/4g/` |
| Loading | `--env-file .env_4g` | Automatic |

### Service-level env_file Directive

**Removed** from new structure:

```yaml
# Old (not needed anymore)
services:
  mme:
    env_file:
      - .env_4g
```

**Why?** The `.env` file is used for **variable substitution in the compose file** (like `${MME_IP}`), not for injecting environment variables into containers. The containers get their configuration from mounted config files in `/mnt/`.

## Migration Steps

### For 4G Deployment

1. **Stop old deployment**:
```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml down
```

2. **Use new structure**:
```bash
cd 4g
docker compose up -d
```

3. **Verify**:
```bash
docker compose ps
docker compose logs mme | head -20
```

### For S1-N2 Deployment

The S1-N2 deployment remains in `sXGP-5G/` directory but now:

**Old way**:
```bash
cd sXGP-5G
docker compose --env-file .env_s1n2 -f docker-compose.s1n2.yml up -d
```

**New way** (if you rename `.env_s1n2` to `.env`):
```bash
cd sXGP-5G
docker compose -f docker-compose.s1n2.yml up -d
```

Or even simpler, rename `docker-compose.s1n2.yml` to `docker-compose.yaml`:
```bash
cd sXGP-5G
docker compose up -d
```

## Testing the New Structure

### 1. Verify Configuration

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose config | grep "ipv4_address:"
```

Expected output:
```
ipv4_address: 192.168.10.30  # mongo
ipv4_address: 192.168.10.31  # hss
ipv4_address: 192.168.10.37  # mme
...
```

### 2. Check Environment Variables

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose config | grep -A 5 "mme:"
```

Should show correct IP addresses and volumes.

### 3. Dry Run

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose up --dry-run
```

### 4. Start and Verify

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments/4g
docker compose up -d
docker compose ps
```

## Backward Compatibility

The old files in `deployments/` directory still work:

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up -d
```

You can keep both structures during the transition period.

## Cleanup (Optional)

After verifying the new structure works, you can optionally move old files:

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
mkdir -p legacy
mv .env_4g .env_5g .env legacy/
mv 4g-data-only-deploy.yaml 5g-data-only-deploy.yaml legacy/
mv sa-deploy.yaml srsenb_zmq.yaml srsgnb_zmq.yaml legacy/
```

## Rollback

If you need to rollback:

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up -d
```

The old files are unchanged and still functional.

## Common Issues

### Issue: "service 'xxx' refers to undefined volume"

**Cause**: Volume names might differ between old and new structure.

**Solution**: Use the same volume names:
```yaml
volumes:
  mongodbdata:
    name: docker_open5gs_mongodbdata  # Same as old structure
```

### Issue: "network br-open5gs_4g not found"

**Cause**: Network doesn't exist.

**Solution**:
```bash
docker network create \
  --driver=bridge \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.2 \
  --opt com.docker.network.bridge.name=br-open5gs_4g \
  br-open5gs_4g
```

### Issue: Environment variables not substituted

**Cause**: `.env` file not in the correct location.

**Solution**: Ensure `.env` is in the same directory as `docker-compose.yaml`.

### Issue: Build context not found

**Cause**: Relative paths need adjustment.

**Solution**: Update build context from `..` to `../..` in the new structure.

## Summary

| Feature | Old Structure | New Structure |
## Tips: 外部SSHトンネル接続先IP（203.178.128.98）が変わった場合

- 4G/5Gの内部ネットワーク（192.168.10.0/24）やサービスIPは、すべて各`.env`ファイルで管理されています。
- 外部SSHトンネル接続先（203.178.128.98）が変更された場合は、`README_NETWORK_SETUP.md`の該当箇所（例: sshコマンドの接続先IP）だけ修正すればOKです。
- DockerやOpen5GSの構成ファイル（`docker-compose.yaml`や`.env`）は、外部IP変更の影響を受けません。
- 新構成では、外部ネットワーク変更の影響範囲が限定され、メンテナンス性が向上しています。

## Tips: sXGP-5G構成でも物理eNB（192.168.10.110）に接続したい場合

sXGP-5G構成（S1-N2コンバータ）を物理eNBに接続する方法は、`sXGP-5G/PHYSICAL_ENB_GUIDE.md`を参照してください。

**主な変更点:**
1. S1-N2コンバータを2つのネットワークに接続（マルチネットワーク）
   - 内部: `172.24.0.30`（5Gコアとの通信）
   - 外部: `192.168.10.x`（物理eNBとの通信）
2. 外部ブリッジネットワーク（br-open5gs_4g）を4G構成と共用
3. 物理インターフェース（eno1）をブリッジに接続

詳細な手順は専用ガイドを参照してください。
|---------|--------------|---------------|
| Command | `docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up` | `docker compose up` |
| Working Directory | `deployments/` | `deployments/4g/` |
| Env File | `.env_4g` | `.env` (auto-loaded) |
| Separation | All configs in one dir | Each deployment isolated |
| Documentation | Single README | Per-deployment READMEs |
| Paths | Relative to `deployments/` | Relative to `deployments/4g/` |

The new structure is **simpler, cleaner, and more maintainable** while preserving all functionality.
