### Fallback Mechanism: xOnyxiaContext (Optional)

For backward compatibility or non-IRSA clusters, Onyxia can inject credentials via `xOnyxiaContext`. The Helm chart supports both mechanisms, with AWS SDK automatically preferring IRSA when available.

#### How xOnyxiaContext Works (Legacy/Fallback Path)

```yaml
# Automatically injected by Onyxia
onyxia:
  user:
    idep: "john.doe"
    email: "john.doe@un.org"
    accessToken: "eyJhbGci..."  # Keycloak OIDC token
    refreshToken: "eyJhbGci..."
    # Additional user fields: name, password, ip, darkMode, lang,
    # decodedIdToken, profile
  s3:
    isEnabled: true
    AWS_ACCESS_KEY_ID: "ASIA..."      # ← From AWS STS
    AWS_SECRET_ACCESS_KEY: "..."      # ← From AWS STS
    AWS_SESSION_TOKEN: "..."          # ← From AWS STS
    AWS_DEFAULT_REGION: "us-west-2"
    AWS_BUCKET_NAME: "datalab-142496269814-user-bucket"
    # Additional S3 fields: AWS_S3_ENDPOINT, port, pathStyleAccess,
    # objectNamePrefix, workingDirectoryPath, isAnonymous
  region:
    defaultIpProtection: true
    defaultNetworkPolicy: true
    customValues: {}  # Region-wide custom values
    # Additional region fields: allowedURIPattern, kafka, tolerations,
    # nodeSelector, startupProbe, sliders, resources, openshiftSCC
  k8s:
    domain: "dev.officialstatistics.org"
    randomSubdomain: "123456"
    # Additional k8s fields: ingressClassName, ingress, route, istio,
    # initScriptUrl, useCertManager, certManagerClusterIssuer
  # Optional context sections:
  # - proxyInjection: httpProxyUrl, httpsProxyUrl, noProxy
  # - packageRepositoryInjection: cranProxyUrl, condaProxyUrl, pypiProxyUrl
  # - certificateAuthorityInjection: cacerts, pathToCaBundle
  # - vault: VAULT_ADDR, VAULT_TOKEN, VAULT_MOUNT, VAULT_TOP_DIR
  # - git: name, email, credentials_cache_duration, token
```

Our Helm chart automatically exposes these as environment variables:

```yaml
# templates/deployment.yaml
env:
- name: AWS_ACCESS_KEY_ID
  value: {{ .Values.onyxia.s3.AWS_ACCESS_KEY_ID }}
- name: AWS_SECRET_ACCESS_KEY
  value: {{ .Values.onyxia.s3.AWS_SECRET_ACCESS_KEY }}
- name: AWS_SESSION_TOKEN
  value: {{ .Values.onyxia.s3.AWS_SESSION_TOKEN }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.onyxia.s3.AWS_DEFAULT_REGION | default "us-west-2" }}
```

#### Credential Flow Architecture

The system uses **Workload Identity (IRSA)** as the primary mechanism, with xOnyxiaContext as an optional fallback:

```
Primary Flow: IRSA (Workload Identity)
  ├─► ServiceAccount has eks.amazonaws.com/role-arn annotation
  ├─► Kubernetes injects AWS_WEB_IDENTITY_TOKEN_FILE
  ├─► AWS SDK automatically calls sts:AssumeRoleWithWebIdentity
  └─► Pod receives auto-refreshing AWS credentials

Fallback Flow: xOnyxiaContext (Optional)
  ├─► Onyxia frontend calls AWS STS
  ├─► Credentials injected as environment variables
  └─► AWS SDK uses static credentials (12-hour TTL)
```

**Result**: The Helm chart is portable across any Kubernetes cluster with OIDC federation configured.

#### Credential Lifecycle

- **AWS credentials**: 12 hours (sufficient for most analyses)
- **OIDC access token**: ~15 minutes (injected at pod creation as static snapshot)
- **OIDC refresh token**: ~30 days (also injected, but pods don't auto-refresh)
- **Key insight**: Our analyses primarily use AWS credentials for S3 access, not OIDC tokens
- **Token refresh**: Onyxia frontend handles refresh, but running pods receive static snapshots
- **Workaround**: Restart pod for fresh credentials if session exceeds 12 hours

#### Benefits for Reproducible Analysis

1. **No Manual Credential Management**
   - Chapter authors never handle AWS keys
   - No `.aws/credentials` files in containers
   - No secrets to manage in Helm charts

2. **Least Privilege Access**
   - Each user gets credentials scoped to their identity
   - AWS IAM policies control S3 bucket access
   - Audit trail: AWS CloudTrail logs show actual user

3. **Works with Standard Libraries**
   - R: `arrow`, `sits`, `rstac`, `terra`, `sf` all detect AWS credentials automatically
   - Python: `boto3`, `s3fs`, `rasterio` use standard AWS SDK credential chain
   - No custom code needed in analysis scripts

4. **Hybrid Data Strategy**
   - **Fast startup**: Local data from CSI-mounted OCI images (5-15s)
   - **Live data**: Cloud sources via AWS credentials
   - **Reproducibility**: Both data sources version-controlled (content-hashed artifacts + STAC queries in code)
