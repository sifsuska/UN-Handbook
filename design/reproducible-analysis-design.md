## Reproducible Analysis System for UN Handbook - Design Document

### Executive Summary

This document outlines the design for a "reproducible analysis" feature that allows readers to launch select chapters of the UN Handbook into a one-click, pre-configured Kubernetes environment.

**Scope**: This system is designed for chapters with local data dependencies (pre-computed models, training samples, cached results). Currently, 2 chapters are ready (ct_chile, ct_digital_earth_africa), with 2-5 additional chapters planned. Most handbook chapters (84%) are cloud-only or theoretical and access live satellite imagery via STAC catalogs without requiring reproducible containers.

- **For Readers**: A "Reproduce this analysis" button launches a JupyterLab session into Onyxia on the UN Global Platform with all code, data, and dependencies ready.
- **For Chapter Authors**: A zero-friction, git-native workflow. Authors push data to a tracked directory, and a CI pipeline automatically builds, versions, and deploys the data artifact. Minimal YAML configuration required (just `enabled: true` with smart defaults).
- **For Infrastructure**: The system leverages Onyxia to dynamically provision ephemeral sessions. This design is stateless, using a CSI image driver to mount OCI data artifacts directly as volumes, and pre-built images for the environment.

**Key Architectural Decisions**:

-  Onyxia-native Orchestration: Use Onyxia for UI, authentication, and service deployment.
-  Stateless Data Layer: Use a CSI Image Driver to mount OCI data artifacts directly as read-only volumes.
-  Implicit Performance: Startup speed (5-15s) is achieved via standard node-level container image caching, which is more robust than managed PVCs.
-  Automated Author Workflow: A fully CI-driven pipeline using Dagger SDK builds content-hashed (immutable) data artifacts and auto-commits the new hash back to the chapter, ensuring true reproducibility.
-  Portable & Decoupled Auth: Use standard Kubernetes Workload Identity (IRSA) as the primary mechanism for AWS credentials. This makes the core Helm chart portable and not dependent on Onyxia-specific injectors.
-  Curated & Isolated Environments: Start with a "base" Docker image, but the CI pipeline is designed to build chapter-specific compute images (from renv.lock) to prevent future dependency conflicts.

These architectural decisions are implemented through **five custom software components** that operate in two distinct phases: a **Build-Time Flow** (automated CI/CD for authors) and a **Run-Time Flow** (one-click session launching for readers). See the [Architecture Overview](#architecture-overview) section for a detailed breakdown of how these components interact with existing platforms (Kubernetes, Onyxia, AWS) to enable reproducible analysis.

---

### Current State & Design Goals

#### Current State

The UN Handbook is a Quarto book with 48 chapters. **Only 2 chapters (4%) currently have local data dependencies** that would benefit from reproducible containers (ct_chile, ct_digital_earth_africa). Most chapters (84%) are cloud-only or theoretical, accessing satellite imagery directly via STAC catalogs. The few chapters with local data use it for pre-computed models, training samples, and cached results to avoid expensive recomputation. Chapters use R (with renv), some Python, and access both local cached data (RDS files, models) and remote cloud data (STAC catalogs).

**Project Type**: Quarto book for UN Handbook on Remote Sensing for Agricultural Statistics
**Repository**: https://github.com/FAO-EOSTAT/UN-Handbook
**Published**: https://FAO-EOSTAT.github.io/UN-Handbook/

**Content Organization** (48 chapters across 7 parts):


- Part 1: Theory (11 chapters) - Remote sensing fundamentals
- Part 2: Crop Type Mapping (6 chapters) - Poland, Mexico, Zimbabwe, China, Chile, DEA
- Part 3: Crop Yield Estimation (5 chapters) - Finland, Indonesia, Colombia, Poland, China
- Part 4: Crop Statistics (4 chapters) - Area estimation, regression, calibration
- Part 5: UAV Agriculture (4 chapters) - Field identification, crop monitoring
- Part 6: Disaster Response (1 chapter) - Flood monitoring
- Part 7: Additional Topics (2 chapters) - World Cereal, learning resources

#### Computational Characteristics

##### Analysis Types by Computational Load

**Light (Theory Chapters)**:

- Educational examples with small datasets
- Code snippets with `eval: false`
- **Resource allocation**: 2 CPU, 8GB RAM, 10GB storage (defined in Helm chart)
- **Typical runtime**: Minutes

**Medium (Crop Statistics)**:

- Google Earth Engine data access
- Sample-based area estimators
- Statistical methods
- **Resource allocation**: 6 CPU, 24GB RAM, 20GB storage (defined in Helm chart)
- **Typical runtime**: 15-30 minutes

**Heavy (Crop Type Mapping)**:

- Example: Chile chapter
  - Sentinel-2 imagery via STAC
  - 62,920 training points from 4,140 polygons
  - Random Forest classification
  - Self-Organizing Maps
  - 22 RDS files (models, samples, classifications)
- **Resource allocation**: 10 CPU, 48GB RAM, 50GB storage (defined in Helm chart)
- **Typical runtime**: 1-2 hours

**GPU (Deep Learning)**:

- Example: Colombia chapter (crop yield estimation)
  - Sentinel-1 SAR data processing
  - Deep learning with `luz` (PyTorch for R)
  - Requires GPU for reasonable performance
  - 23 cache entries
- **Resource allocation**: 8 CPU, 32GB RAM, 1 GPU, 50GB storage (defined in Helm chart)
- **Typical runtime**: 2-4 hours

#### Current Technology Stack

##### R Environment
- **R Version**: 4.5.1
- **Package Manager**: `renv` with lock file (7,383 lines, ~427KB)
- **Key Packages**:
  - Geospatial: `sits`, `sf`, `terra`, `stars`, `lwgeom`
  - Cloud Access: `rstac`, `earthdatalogin`, `arrow`, `gdalcubes`
  - Machine Learning: `randomForest`, `ranger`, `e1071`, `kohonen`
  - Deep Learning: `torch`, `luz`
  - Visualization: `ggplot2`, `tmap`, `leaflet`
  - Python Integration: `reticulate` (for Indonesia chapter)

##### Python Environment
- **Status**: One chapter (Indonesia) uses Python via `reticulate`
- **Solution**: Create `requirements.txt` for reproducibility

##### Data Sources

**Cloud Platforms (Remote Access)**:

- Microsoft Planetary Computer (MPC)
- AWS (Sentinel-2 L2A)
- Digital Earth Africa
- Brazil Data Cube (BDC)
- Copernicus Data Space Ecosystem (CDSE)
- NASA HLS (Harmonized Landsat-Sentinel)
- Google Earth Engine

**Local Storage**:

- `/data` directory: 59 MB across 2 chapter-specific subdirectories
  - `data/ct_chile/` (57 MB): Chile crop classification models, samples, ROI boundaries
  - `data/ct_digital_earth_africa/` (2 MB): Rwanda training data and validation results
- `/etc` directory: 227 MB of **shared teaching artifacts**
  - Purpose: Pre-computed models and cached results for theory chapters
  - Usage: Allows readers to explore concepts without expensive recomputation
  - **Note**: This is legitimate shared infrastructure, not misplaced chapter data
- **Data Types**: RDS files (models, cubes, samples), Shapefiles, Geoparquet, TIFF (gitignored)

**Data Organization Patterns**:

- **Chapter-specific data**: Stored in `data/<chapter>/` (e.g., `data/ct_chile/`) → Packaged in reproducible containers
- **Shared teaching artifacts**: Theory chapters use `etc/` directory for pre-computed demonstrations
- **Cloud-only chapters**: Most chapters (84%) access satellite imagery directly via STAC catalogs with no local data

**Access Pattern**:

- Preferred: Cloud-native via STAC protocol (most chapters follow this pattern)
- Hybrid: Some chapters combine local cached results with live cloud data access
- Reality: Only 2 chapters currently use local data for reproducible containers

#### Current Reproducibility Status

**Strengths**:

-  `renv` lock file with complete R package snapshot
-  Version control with clear structure
-  Modular design (each chapter independent)
-  Cloud-native workflows using STAC (84% of chapters)
-  Chapter-specific data directories already established (`data/<chapter>/` pattern)
-  Excellent data hygiene in chapters with local data

**Gaps for Reproducible Containers** (applies to ~4% of chapters with local data):

-  No containerization (no Dockerfile)
-  No CI/CD or automated testing
-  No YAML frontmatter for reproducible configuration
-  Python dependencies unmanaged (one chapter uses reticulate)
-  System dependencies (GDAL, PROJ, GEOS) versions unspecified
-  Computational requirements undocumented

**Note**: Pre-computed results (RDS files) are intentional for performance, not a gap. They enable demonstration of expensive analyses (e.g., 2-hour deep learning training) without requiring readers to re-run full computations.

---

### Design Requirements & Principles

#### Key Decisions

1. **Resource Allocation**: Dynamic (auto-scale per chapter based on metadata)
2. **Data Strategy**: Pre-packaged, content-hashed, and immutable OCI artifacts for local data; automatic OIDC-based credentials for live cloud data.
3. **User Interface**: JupyterLab (supports R/Python)
4. **Session Duration**: Ephemeral (e.g., 2-hour auto-cleanup)
5. **Platform Integration**: Orchestrated by Onyxia, but with a portable core
6. **Cloud Access**: Automatic, temporary AWS credentials via standard Kubernetes Workload Identity (IRSA)

#### Design Principles

**For Handbook Readers ("User Magic")**:

- One-click experience: Click button → JupyterLab ready
- No setup required: All dependencies pre-configured
- Immediate feedback: Show launch progress and estimated time
- Time-bounded: Clear session expiration with download option

**For Chapter Authors ("Developer Magic")**:

- Simple metadata: Add YAML frontmatter to chapter
- Zero-friction: Just `git push` data files, CI handles the rest
- No Docker or Helm knowledge required
- Version control: Content-hashed snapshots (immutable)

**For Infrastructure**:

- Cost-efficient: Dynamic resources, auto-cleanup
- Scalable: Handle concurrent users
- Observable: Monitoring and usage tracking
- Maintainable: Standard Helm charts, no custom operators
- Secure: Immutable images, no runtime privilege escalation
- Onyxia-native: Leverages existing platform features

---

### Architecture Overview

This reproducible analysis system consists of **five custom software components** that integrate with existing platforms (Kubernetes, Onyxia, AWS, and container registries) to enable one-click reproducible chapter sessions. The architecture operates in two distinct phases: a **Build-Time Flow** (automated CI/CD for chapter authors) and a **Run-Time Flow** (one-click session launching for readers).

#### Build-Time Flow: Automated CI/CD Pipeline

When a chapter author pushes changes to the repository, an automated CI/CD pipeline ensures that all data and compute dependencies are versioned, built, and deployed as immutable OCI artifacts.

```
                    [Chapter Author]
                          |
                          v
                    [git push]
                     /        \
                    /          \
         (data/ct_chile/)   (renv.lock / Dockerfile)
                  |                    |
                  v                    v
     [Portable CI Pipeline (Dagger)]  [Portable CI Pipeline (Dagger)]
          Data Packaging (#3)          Image Build (#2)
                  |                    |
                  v                    v
          [OCI Data Artifact]    [Curated Compute Image]
           (tag: sha256-abc...)   (tag: base:v1.1)
                  |                    |
                  +------[GHCR]--------+
                  |
                  v
          [Auto-commit hash back]
          (via Dagger pipeline)
                  |
                  v
           (ct_chile.qmd:
            data-snapshot: sha256-abc...)
```

**Key Components in Build-Time Flow**:

1. **Portable CI Pipeline - Data Packaging (#3)**: A Dagger SDK function that automatically detects changes to chapter `data/` directories, builds content-hashed OCI data artifacts, pushes them to the container registry (GHCR), and auto-commits the new hash back to the `.qmd` file's YAML frontmatter. Triggered by simple one-line wrappers in GitHub Actions, GitLab CI, or run locally. (See [Systems Design](#systems-design) for implementation)

2. **Portable CI Pipeline - Image Build (#2)**: A Dagger SDK function that builds pre-built, immutable container images containing specific R/Python versions, all `renv`/`pip` packages, and system libraries (GDAL, PROJ). These images are rebuilt via Dagger when `renv.lock` or Dockerfiles change. (See [Systems Design](#systems-design) for image variants)

3. **Portable CI Pipeline - Metadata Generation (#5)**: A Dagger SDK function that scans all `.qmd` files and aggregates their `reproducible:` metadata into a centralized `chapters.json` manifest, which can be used for cluster optimizations like image pre-warming. (See [Systems Design](#systems-design) for implementation)

#### Run-Time Flow: One-Click Reproducible Sessions

When a handbook reader clicks the "Reproduce this analysis" button, the system orchestrates a fully configured Kubernetes session with all code, data, and cloud credentials ready.

```
           [Handbook Reader]
                  |
                  v
       [Clicks "Reproduce" button]
                  |
                  v
       [Quarto Extension reads YAML]
               (#1)
                  |
                  v
       [Generates Onyxia deep link]
          (pre-filled with params)
                  |
                  v
       +---------[Onyxia]----------+
       |   (Existing Platform)     |
       |  - User Authentication    |
       |  - UI for Launch Params   |
       +---------------------------+
                  |
            [User clicks "Launch"]
                  |
                  v
       [Onyxia calls Helm Chart]
               (#4)
                  |
                  v
       +--------[Kubernetes API]--------+
       |    (Existing Platform)         |
       +---------------------------------+
              /              \
             /                \
            v                  v
    [Pull Compute Image]  [CSI Image Driver]
         (#2)              (Existing Cluster Component)
    (base:v1.1)                  |
                                 v
                         [Mount Data Artifact]
                            (sha256-abc...)
                         as read-only volume
            |                    |
            +--------------------+
                     |
                     v
              [Pod Running]
         +--------------------+
         | - JupyterLab       |
         | - All code         |
         | - Local data       |
         | - AWS credentials  |
         |   (via IRSA)       |
         +--------------------+
```

**Key Components in Run-Time Flow**:

1. **"Reproduce" Button Quarto Extension (#1)**: A Lua-based Quarto extension that reads `reproducible:` metadata from chapter YAML frontmatter and dynamically generates an Onyxia deep link URL, pre-filling all launch parameters (resource tier, image tag, data snapshot hash). (See [Onyxia Integration Strategy](#onyxia-integration-strategy-the-reproduce-button) and [Technical Implementation](#technical-implementation))

4. **"Chapter Session" Helm Chart (#4)**: An Onyxia-compatible Helm chart that defines the reproducible session in Kubernetes. It creates a `ServiceAccount` with IRSA annotations (for AWS cloud access), defines the `Deployment` (specifying which Compute Image to run), and configures a volume mount using the CSI Image Driver to attach the OCI data artifact as a read-only filesystem. (See [Systems Design](#systems-design) for chart structure)

**Existing Platform Components**: The system relies on standard Kubernetes features (CSI Image Driver for volume mounting, IRSA for AWS credential injection) and Onyxia for user authentication and service orchestration.

#### The Five Core Components

This system is built from five custom software components that work together to enable reproducible analysis:

**Build-Time Components** (automated CI/CD):

- **Component #1: Portable CI Pipeline (Dagger)** - Orchestrates all build-time tasks: building compute images, packaging data artifacts, and generating metadata. Runs identically on developer laptops, GitHub Actions, or GitLab CI. (See [Section 5.1](#the-portable-ci-pipeline-dagger))

- **Component #2: Curated Compute Images** - Pre-built Docker images containing R/Python environments, system libraries (GDAL, PROJ, GEOS), and all package dependencies from `renv.lock`. Available in `base` and `gpu` flavors. (See [Section 5.2](#curated-compute-images-docker))

- **Component #3: OCI Data Artifacts** - Content-hashed, immutable data snapshots packaged as OCI images. Mounted directly as read-only volumes using the CSI Image Driver, enabling fast startup (5-15s) via node-level caching. (See [Section 5.3](#oci-data-artifacts-csi-driver))

**Run-Time Components** (user-facing):

- **Component #4: "Reproduce" Button (Quarto Extension)** - A Lua-based Quarto extension that reads chapter metadata and generates an Onyxia deep-link URL. The user's entrypoint to launching a reproducible session. (See [Section 6.1](#the-reproduce-button-quarto-extension))

- **Component #5: "Chapter Session" (Helm Chart)** - An Onyxia-compatible Helm chart that deploys the Kubernetes session. Translates semantic tier names (`heavy`, `gpu`) into actual resource allocations, mounts data artifacts, and configures cloud credentials via IRSA. (See [Section 6.4](#the-chapter-session-helm-chart))

**Cross-Cutting Capabilities**:

- **Onyxia Deep Link Integration** - Bridges the button click to session deployment via pre-filled URL parameters. (See [Section 6.2](#onyxia-integration-the-deep-link))

- **Cloud Data Access (IRSA)** - Provides automatic AWS credentials for accessing S3-hosted satellite imagery via Kubernetes Workload Identity. (See [Section 6.3](#cloud-data-access-irsa--xonyxiacontext))

#### Decoupled Configuration Architecture

This system uses a **decoupled configuration architecture** where the Quarto site (frontend) is unaware of infrastructure details.

**Frontend (Quarto Site)**:
- **Knows**: Semantic names (`tier: "heavy"`, `imageFlavor: "gpu"`)
- **Doesn't know**: CPU counts, memory sizes, image repositories, version tags
- **Generates**: Deep-link URLs with semantic parameters

**Backend (Helm Chart)**:
- **Knows**: Resource tier mappings, image repositories, version tags
- **Translates**: Semantic names → Kubernetes resource specifications
- **Maintains**: Single Source of Truth for infrastructure config in `templates/deployment.yaml`

**Benefits**:

1. **Decoupling**: Infrastructure changes don't require re-rendering the Quarto book
2. **SSOT**: Resource tiers and image mappings defined once in Helm chart templates
3. **Versioning**: Helm chart version controls infrastructure config changes
4. **Testing**: Infrastructure team can update staging Helm chart independently
5. **Maintainability**: Change tier from 10 CPU → 12 CPU in one place (Helm chart)
6. **No Drift**: Frontend can never reference outdated resource values

**Example Workflow**:

When infrastructure needs to change the `heavy` tier from 10 CPU to 12 CPU:

1. Infrastructure team updates `templates/deployment.yaml`:
   ```yaml
   "heavy" (dict "cpu" "12000m" "memory" "48Gi" "storage" "50Gi")
   ```
2. Deploy new Helm chart version (`v1.1.0`)
3. No changes needed to Quarto site
4. Next user clicks "Reproduce" button → gets 12 CPU automatically

---

### Cloud Data Access Strategy

#### Overview: The Dual-Data Architecture

The reproducible analysis system provides seamless access to **two complementary data sources**:

1. **Local Packaged Data** (via CSI Image Driver)
   - Pre-computed models, cached results, reference datasets
   - Content-hashed snapshots for exact reproducibility
   - Fast access (5-15s startup via node-level caching)

2. **Cloud Data Sources** (via automatic AWS credentials)
   - Live satellite imagery from STAC catalogs (Sentinel-2, Landsat, etc.)
   - Cloud-optimized datasets (COG, Zarr, Parquet)
   - Accessed via standard R/Python libraries

**Key Insight**: The system uses **Kubernetes Workload Identity (IRSA)** as the primary mechanism for AWS credentials. This is a standard Kubernetes pattern that makes the Helm chart portable across any cluster with OIDC federation configured. Onyxia's `xOnyxiaContext` provides a fallback path for backward compatibility.

#### Primary Mechanism: Workload Identity (IRSA)

**IAM Roles for Service Accounts (IRSA)** is the cloud-native standard for granting AWS permissions to Kubernetes pods. The Helm chart creates a ServiceAccount annotated with an AWS IAM Role ARN. Kubernetes automatically provides a token that the pod's AWS SDK exchanges for credentials.

**How It Works**:

```
1. Onyxia injects IRSA configuration via region.customValues
   ↓
   Helm chart receives: serviceAccount.annotations.eks.amazonaws.com/role-arn
   ↓
2. Chart creates ServiceAccount with IRSA annotation
   ↓
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/handbook-reader
   ↓
3. Kubernetes IRSA webhook injects OIDC token into pod
   ↓
   AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
   AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/handbook-reader
   ↓
4. AWS SDK automatically detects IRSA environment
   ↓
   Calls: sts:AssumeRoleWithWebIdentity (no frontend involved)
   ↓
5. Pod receives auto-refreshing AWS credentials
   ↓
   R/Python libraries use them automatically
```

**Benefits**:

-  **Portable**: Works on any Kubernetes cluster with OIDC (EKS, GKE, AKS, self-hosted)
-  **Auto-refresh**: AWS SDK handles credential rotation automatically
-  **Decoupled**: Chart doesn't depend on Onyxia-specific features
-  **Secure**: Short-lived tokens, never stored in config
-  **Standard**: Uses official AWS SDK credential chain

##### Infrastructure Setup (One-Time)

**1. Enable OIDC provider for EKS cluster**:
```bash
eksctl utils associate-iam-oidc-provider --cluster=my-cluster --approve
```

**2. Create IAM role for handbook readers**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::142496269814:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/YOUR_CLUSTER_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "oidc.eks.us-west-2.amazonaws.com/id/YOUR_CLUSTER_ID:sub": "system:serviceaccount:user-*:*"
        }
      }
    }
  ]
}
```

**Or use eksctl** (recommended):
```bash
eksctl create iamserviceaccount \
  --name handbook-reader \
  --namespace default \
  --cluster my-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve
```

**3. Attach S3 access policy to role**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::sentinel-s2-l2a",
        "arn:aws:s3:::sentinel-s2-l2a/*",
        "arn:aws:s3:::usgs-landsat",
        "arn:aws:s3:::usgs-landsat/*"
      ]
    }
  ]
}
```

**4. Configure Onyxia region with IRSA** (via `region.customValues`):
```yaml
# In Onyxia Helm values or platform configuration
regions:
  - id: "jakarta"
    name: "Jakarta"
    services:
      customValues:
        # IRSA configuration injected into all Helm charts
        serviceAccount:
          create: true
          annotations:
            eks.amazonaws.com/role-arn: "arn:aws:iam::142496269814:role/handbook-reader"
        aws:
          region: "us-west-2"
      defaultConfiguration:
        ipprotection: true      # Enable IP-based access control by default
        networkPolicy: true     # Enable Kubernetes NetworkPolicy by default
```

The `region.customValues` configuration is automatically injected into Helm chart values when services are deployed via Onyxia. This allows region-wide defaults like ServiceAccount annotations for IRSA/Workload Identity to be applied consistently across all deployed services.

**Note on region.customValues**: While fully implemented in Onyxia's codebase, this feature is not yet documented in the official Onyxia region configuration documentation. The implementation allows arbitrary key-value pairs to be injected into all Helm charts via `onyxia.region.customValues`. Charts can access these values using the standard x-onyxia schema pattern:

```json
{
  "serviceAccount": {
    "annotations": {
      "x-onyxia": {
        "overwriteDefaultWith": "region.customValues.serviceAccount.annotations"
      }
    }
  }
}
```

#### Fallback Mechanism: xOnyxiaContext (Optional)

For backward compatibility or non-IRSA clusters, Onyxia can inject credentials via `xOnyxiaContext`. The Helm chart supports both mechanisms, with AWS SDK automatically preferring IRSA when available.

**How xOnyxiaContext works** (legacy/fallback path):

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

#### Using Cloud Credentials in Analysis Code

##### R Example: Accessing Sentinel-2 via STAC

```r
# Chapter code (e.g., ct_chile.qmd)
library(rstac)
library(sits)

# AWS credentials automatically detected from environment variables
# No configuration needed!

# Connect to AWS-hosted STAC catalog
s2_catalog <- stac("https://earth-search.aws.element84.com/v1")

# Search for Sentinel-2 imagery
items <- s2_catalog %>%
  stac_search(
    collections = "sentinel-2-l2a",
    bbox = c(-71.5, -33.5, -70.5, -32.5),
    datetime = "2023-01-01/2023-12-31"
  ) %>%
  post_request()

# Create data cube (sits automatically uses AWS credentials)
cube <- sits_cube(
  source = "AWS",
  collection = "SENTINEL-2-L2A",
  tiles = "19HDB",
  bands = c("B02", "B03", "B04", "B08"),
  start_date = "2023-01-01",
  end_date = "2023-12-31"
)

# Access works seamlessly - AWS SDK uses env vars
```

##### Python Example: Accessing Landsat via Arrow

```python
# For chapters using reticulate
import os
import pyarrow.fs as fs

# AWS credentials automatically detected
s3 = fs.S3FileSystem(
    region='us-west-2'
    # access_key_id, secret_access_key, session_token
    # automatically read from environment variables
)

# Read cloud-optimized Parquet file
dataset = pq.ParquetDataset(
    's3://usgs-landsat/collection02/level-2/',
    filesystem=s3
)
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

#### Benefits for Reproducible Analysis

1. **No Manual Credential Management**
   - Chapter authors never handle AWS keys
   - No `.aws/credentials` files in containers
   - No secrets to manage in Helm charts

2. **Token Lifecycle**
   - **AWS credentials**: 12 hours (sufficient for most analyses)
   - **OIDC access token**: ~15 minutes (injected at pod creation as static snapshot)
   - **OIDC refresh token**: ~30 days (also injected, but pods don't auto-refresh)
   - **Key insight**: Our analyses primarily use AWS credentials for S3 access, not OIDC tokens
   - **Token refresh**: Onyxia frontend handles refresh, but running pods receive static snapshots
   - **Workaround**: Restart pod for fresh credentials if session exceeds 12 hours

3. **Least Privilege Access**
   - Each user gets credentials scoped to their identity
   - AWS IAM policies control S3 bucket access
   - Audit trail: AWS CloudTrail logs show actual user

4. **Works with Standard Libraries**
   - R: `arrow`, `sits`, `rstac`, `terra`, `sf` all detect AWS credentials automatically
   - Python: `boto3`, `s3fs`, `rasterio` use standard AWS SDK credential chain
   - No custom code needed in analysis scripts

5. **Hybrid Data Strategy**
   - **Fast startup**: Local data from CSI-mounted OCI images (5-15s)
   - **Live data**: Cloud sources via AWS credentials
   - **Reproducibility**: Both data sources version-controlled (content-hashed artifacts + STAC queries in code)

#### Example: Complete Analysis Workflow

```r
# ct_chile.qmd - Complete reproducible analysis

library(sits)
library(sf)
library(rstac)

# ============================================================
# Part 1: Load local packaged data (from CSI-mounted OCI image)
# ============================================================

# Pre-trained model from local storage
model <- readRDS("/home/jovyan/handbook-chapter/data/ct_chile/rf_model.rds")

# Reference training data
training_samples <- readRDS("/home/jovyan/handbook-chapter/data/ct_chile/training.rds")

# Region of interest shapefile
roi <- st_read("/home/jovyan/handbook-chapter/data/ct_chile/chile_roi.shp")

# ============================================================
# Part 2: Access live satellite data (from AWS via STAC)
# ============================================================

# AWS credentials automatically available from environment
# No configuration needed!

# Query recent Sentinel-2 imagery
cube <- sits_cube(
  source = "AWS",
  collection = "SENTINEL-2-L2A",
  tiles = "19HDB",
  bands = c("B02", "B03", "B04", "B08"),
  start_date = Sys.Date() - 365,
  end_date = Sys.Date()
)

# ============================================================
# Part 3: Run analysis combining both data sources
# ============================================================

# Classify recent imagery using pre-trained model
classification <- sits_classify(
  data = cube,
  ml_model = model,
  roi = roi,
  output_dir = "/tmp/results"
)

# Compare with reference training data
accuracy <- sits_accuracy(classification, training_samples)

print(accuracy)
```

**Result**: The analysis seamlessly combines:


- Pre-trained model (CSI-mounted data) for reproducibility
- Live satellite data (AWS S3) for up-to-date results
- No credential management code required
- Fully reproducible (content-hashed data, STAC query in code)

#### Troubleshooting Cloud Access

If cloud data access fails, users can verify credentials:

```r
# Check AWS credentials are available
Sys.getenv("AWS_ACCESS_KEY_ID")        # Should show ASIA...
Sys.getenv("AWS_SECRET_ACCESS_KEY")    # Should show value
Sys.getenv("AWS_SESSION_TOKEN")        # Should show value

# Test S3 access
library(arrow)
s3_bucket <- s3_bucket("sentinel-s2-l2a")
s3_bucket$ls()  # Should list objects
```

Common issues:


- **Empty credentials**: Pod may have started before Onyxia STS call completed (rare)
- **Expired credentials**: Credentials last 12 hours; restart pod for fresh credentials
- **Wrong IAM policy**: Check AWS role has read access to required S3 buckets

---

### Onyxia Integration Strategy: The "Reproduce" Button

This section details the integration pattern used to launch ephemeral analysis sessions from the static Quarto handbook. The solution is designed for simplicity and security, requiring no token management or backend services on the handbook side.

#### The "Deep Link (UI)" Integration Method

The "Reproduce this analysis" button uses Onyxia's **Deep Link** integration pattern. This method involves generating a specific URL that directs the user to the Onyxia launcher frontend. The Quarto site *does not* call the Onyxia API directly.

**Key Characteristics:**

  * **No Authentication Handled:** The static Quarto page is "unauthenticated." It does not handle OIDC tokens, API keys, or any user credentials.
  * **Authentication Outsourced:** All authentication is handled by the Onyxia frontend (`datalab.officialstatistics.org`).
  * **Form Pre-population:** The generated URL contains query parameters that pre-fill all the necessary Helm chart options.

#### The User Authentication Flow

This is the key clarification: the user's **browser session** with Onyxia handles authentication, not the Quarto page.

1.  A user clicks the "Reproduce" button in the Quarto handbook.

2.  The browser is directed to a URL like:

    ```
    https://datalab.officialstatistics.org/launcher/handbook/chapter-session?
      autoLaunch=true&
      name=chapter-ct-chile&
      resources.limits.cpu=6000m&
      resources.limits.memory=«24Gi»&
      ...
    ```

3.  The Onyxia frontend receives this request. It immediately checks the user's browser for an existing, valid Onyxia session.

      * **Scenario A: User is already logged in**

        1.  Onyxia detects the active session.
        2.  It reads the `autoLaunch=true` parameter.
        3.  It bypasses the form and immediately triggers the `PUT /my-lab/app` API call *on the user's behalf*, automatically attaching the user's stored OIDC token.
        4.  The user sees the launch splash screen.

      * **Scenario B: User is logged out**

        1.  Onyxia's frontend intercepts the request as "unauthenticated."
        2.  It automatically redirects the user's browser to the Keycloak (OIDC) login page.
        3.  The user authenticates.
        4.  Keycloak redirects the user *back* to the original deep-link URL.
        5.  The flow now picks up as **Scenario A**.

#### Key URL Parameters for Developers

The Quarto Lua extension (detailed in Section 8.1) is responsible for generating this URL. The key parameters are:

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `autoLaunch` | boolean | **`autoLaunch=true`** is critical. It skips the form and provides the "one-click" experience. |
| `name` | string | A friendly name for the service (e.g., "chapter-ct-chile"). |
| `[helm.path]`| string/number | Any other parameter is treated as a Helm value override (e.g., `resources.limits.cpu=4000m`). |
| `[helm.path]` | encoded string | Helm values that are strings *must* be wrapped in `«...»` guillemets (e.g., `resources.limits.memory=«24Gi»`). |

---

### Technical Implementation

#### Quarto Extension (Handbook Reader Interface)

**Extension Structure**:
```
_extensions/reproducible-button/
├── _extension.yml
├── reproduce-button.lua (deep-link generator)
└── reproduce-button.js (optional UI enhancements)
```

**Minimal Usage (Recommended)**:
```yaml
---
title: "Crop Type Mapping - Chile"
reproducible:
  enabled: true
  # Smart defaults applied:
  # - tier: auto-detected (medium for RF, heavy for large datasets, gpu for torch/luz)
  # - image-flavor: auto-detected (gpu if torch/luz found, otherwise base)
  # - data-snapshot: auto-updated by CI
  # - estimated-runtime: auto-estimated from data size
  # - storage-size: auto-calculated from data/ directory
---

{{< reproduce-button >}}

# Chapter content...
```

**Advanced Usage (Optional Overrides)**:
```yaml
---
title: "Crop Type Mapping - Chile"
reproducible:
  enabled: true
  tier: heavy              # Override auto-detection
  image-flavor: gpu        # Override auto-detection
  estimated-runtime: "45 minutes"
  storage-size: "50Gi"
---

{{< reproduce-button >}}

# Chapter content...
```

**Rendered Output**:
```html
<div class="reproducible-banner">
  <a href="https://datalab.officialstatistics.org/launcher/handbook/chapter-session?autoLaunch=true&chapter.name=ct_chile&chapter.version=v1-2-3&resources.limits.cpu=6000m&resources.limits.memory=24Gi"
     target="_blank"
     class="btn btn-primary">
     Reproduce this analysis
  </a>
  <span class="metadata">
    Resources: Medium (6 CPU, 24GB RAM) |
    Estimated runtime: 20 minutes |
    Session expires after 2 hours
  </span>
</div>
```

**Extension Implementation** (`reproduce-button.lua`):
```lua
-- Quarto filter to inject Onyxia deep-link button

-- Helper function to encode Helm values for Onyxia URLs
local function encode_helm_value(value)
  if value == nil then return "null" end
  if value == true then return "true" end
  if value == false then return "false" end

  -- Convert to string
  local str = tostring(value)

  -- Check if pure number (no units like 'm' or 'Gi')
  if str:match("^%-?%d+%.?%d*$") then
    return str
  end

  -- String values: URL encode and wrap in «»
  local encoded = str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "«" .. encoded .. "»"
end

local function build_onyxia_url(meta)
  if not meta.reproducible or not meta.reproducible.enabled then
    return nil
  end

  -- Extract chapter metadata
  local chapter_file = quarto.doc.input_file
  local chapter_name = chapter_file:match("([^/]+)%.qmd$")

  -- Extract semantic values (no hard-coded infrastructure details)
  local tier = meta.reproducible.tier or "medium"
  local image_flavor = meta.reproducible["image-flavor"] or "base"
  local data_snapshot = meta.reproducible["data-snapshot"] or "v1.0.0"
  local storage_size = meta.reproducible["storage-size"] or "20Gi"
  local estimated_runtime = meta.reproducible["estimated-runtime"] or "Unknown"

  -- Normalize version (dots to hyphens)
  local version_normalized = data_snapshot:gsub("%.", "-")

  -- Build Onyxia deep-link URL
  local base_url = "https://datalab.officialstatistics.org/launcher/handbook/chapter-session"

  local params = {
    "autoLaunch=true",
    "name=" .. encode_helm_value("chapter-" .. chapter_name),

    -- Pass semantic tier and flavor (Helm chart will interpret)
    "tier=" .. encode_helm_value(tier),
    "imageFlavor=" .. encode_helm_value(image_flavor),

    -- Chapter parameters
    "chapter.name=" .. encode_helm_value(chapter_name),
    "chapter.version=" .. encode_helm_value(version_normalized),
    "chapter.storageSize=" .. encode_helm_value(storage_size)
  }

  local url = base_url .. "?" .. table.concat(params, "&")
  return url, estimated_runtime
end

function Meta(meta)
  local url, runtime = build_onyxia_url(meta)

  if url then
    -- Create HTML button
    local button_html = string.format([[
<div class="reproducible-banner" style="background: #e3f2fd; padding: 15px; margin: 20px 0; border-radius: 5px;">
  <a href="%s" target="_blank" class="btn btn-primary" style="background: #1976d2; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">
     Reproduce this analysis
  </a>
  <span class="metadata" style="margin-left: 15px; color: #555;">
    Estimated runtime: %s | Session expires after 2 hours
  </span>
</div>
]], url, runtime)

    -- Prepend button to document
    local button = pandoc.RawBlock('html', button_html)
    table.insert(quarto.doc.body.blocks, 1, button)
  end

  return meta
end
```

---

### Systems Design

#### Resource Tier Mapping (Helm Chart Configuration)

Resource tiers are defined in the Helm chart templates, not in the Quarto site or author frontmatter. This ensures infrastructure changes don't require updates to the static handbook site.

**Helm Chart Implementation** (`templates/deployment.yaml`):

```yaml
{{- $resourceTiers := dict
      "light"  (dict "cpu" "2000m"  "memory" "8Gi"   "storage" "10Gi")
      "medium" (dict "cpu" "6000m"  "memory" "24Gi"  "storage" "20Gi")
      "heavy"  (dict "cpu" "10000m" "memory" "48Gi"  "storage" "50Gi")
      "gpu"    (dict "cpu" "8000m"  "memory" "32Gi"  "storage" "50Gi")
    -}}
{{- $tier := .Values.tier | default "medium" -}}
{{- $tierConfig := index $resourceTiers $tier -}}
```

**Author Experience** (chapter frontmatter):

Authors only specify semantic tier names:

```yaml
reproducible:
  enabled: true
  tier: heavy        # Just the name
  image-flavor: gpu  # Just the flavor
```

The Helm chart translates these to actual resource allocations.

**Available Tiers**:

- **`light`**: 2 CPU, 8GB RAM, 10GB storage - Theory chapters, small demonstrations
- **`medium`**: 6 CPU, 24GB RAM, 20GB storage - Crop type mapping, Random Forest training, most case studies
- **`heavy`**: 10 CPU, 48GB RAM, 50GB storage - Large-scale classification, SAR preprocessing
- **`gpu`**: 8 CPU, 32GB RAM, 1 GPU, 50GB storage - Deep learning (Colombia chapter), torch/luz models

#### Curated Image Flavors (System Dependencies)

**Problem**: System libraries (GDAL, PROJ, GEOS) cannot be managed by `renv`. Allowing runtime `apt-get install`:


-  Requires `root` access (security vulnerability)
-  Adds 2-5 minutes to startup time
-  Not reproducible (package versions can change)

**Solution**: Pre-built, immutable Docker images maintained by infrastructure team.

**Helm Chart Implementation** (`templates/deployment.yaml`):

```yaml
{{- $imageFlavors := dict
      "base" (dict "repo" "ghcr.io/fao-eostat/handbook-base"     "tag" "v1.0")
      "gpu"  (dict "repo" "ghcr.io/fao-eostat/handbook-base-gpu" "tag" "v1.0")
    -}}
{{- $imageFlavor := .Values.imageFlavor | default "base" -}}
{{- $imageConfig := index $imageFlavors $imageFlavor -}}
```

**Image Catalog**:

| Image Flavor | Repository | Parent Base | System Packages | Use Case |
|--------------|------------|-------------|-----------------|----------|
| `base` | `ghcr.io/fao-eostat/handbook-base:v1.0` | jupyter/r-notebook:r-4.5.1 | GDAL 3.6.2, PROJ 9.1.1, GEOS 3.11.1 | 95% of chapters |
| `gpu` | `ghcr.io/fao-eostat/handbook-base-gpu:v1.0` | nvidia/cuda:12.1-cudnn8 | Same as base + CUDA, cuDNN | Deep learning (Colombia) |

**Author Experience**:
```yaml
reproducible:
  enabled: true
  image-flavor: base  # or "gpu" - just the semantic name
```

**Updating Image Versions**:

Infrastructure team updates the Helm chart template's `$imageFlavors` dictionary and deploys new chart version. No changes needed to Quarto site or chapter files.

**Adding New System Dependency** (governed process):


1. Author opens GitHub issue requesting new package
2. Infrastructure team reviews and approves
3. PR updates Dockerfile: `apt-get install libmagick++-dev`
4. CI builds new image: `handbook-base:v1.1`
5. Update Helm chart values or Quarto extension
6. Deploy via new handbook render

**Security Benefits**:

-  All system packages installed at build time in trusted CI
-  No `root` access in user containers
-  Immutable, auditable images
-  Versioned (can roll back if needed)

#### Stateless Data Layer: CSI Image Driver

**Why CSI Image Driver?**


-  **Stateless**: No PVC management, cleanup jobs, or golden PVC coordination
-  **Implicit Performance**: Node-level caching provides 5-15s startup automatically
-  **Simpler**: Kubernetes treats data images like compute images
-  **Immutable**: Each content hash is a unique, reproducible artifact

**How It Works**:

The CSI (Container Storage Interface) Image Driver allows Kubernetes to mount OCI (Docker/container) images directly as volumes. Instead of managing PVCs and DataVolumes, we simply reference the data image in the pod spec:

```yaml
volumes:
- name: chapter-data
  csi:
    driver: csi-image.k8s.io
    volumeAttributes:
      image: "ghcr.io/fao-eostat/handbook-data:ct_chile-sha256-abcdef123"
    readOnly: true
```

When the pod starts:
1. Kubernetes pulls the data image to the node (just like a compute image)
2. The CSI driver mounts the image contents as a read-only filesystem
3. The container sees the data at `/home/jovyan/handbook-chapter/`
4. Node-level caching means subsequent launches are instant (<15s)

**Benefits**:

- **No state management**: No PVCs to create, clone, or clean up
- **Automatic caching**: Kubernetes image cache handles performance
- **Content-addressed**: Each SHA256 hash guarantees exact reproducibility
- **Garbage collection**: Standard Kubernetes image GC removes unused data

#### Portable CI/CD: The "Pipeline-as-Code" SDK (Dagger)

**Problem**: The CI/CD logic for building compute images, hashing data, and auto-committing hashes is complex. While it could be implemented using GitHub Actions YAML, that approach is platform-specific and tightly coupled to a single CI system. This creates a significant barrier to adoption for organizations using GitLab, Bitbucket, or other platforms.

**Solution**: Abstract the entire build-time logic (Components #2, #3, and #5) into a portable "Pipeline-as-Code" SDK using the Dagger framework.

This SDK (implemented in `ci/pipeline.py`) uses the Dagger Python SDK to define pipeline functions. The CI platform's YAML file becomes a simple, one-line wrapper that just executes the Dagger pipeline.

**How It Works: The Transformation**

This design turns complex, platform-specific CI configurations into simple, portable declarations.

**After: GitHub Actions (Simple & Portable)**

```yaml
# .github/workflows/package-data.yml
jobs:
  build-data:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dagger/setup-dagger@v1
      - name: Build, Push, and Commit Data
        run: dagger run python ./ci/pipeline.py package-data --registry-prefix "ghcr.io/fao-eostat/handbook-data"
        env:
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_COMMIT_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_REPO_URL: "github.com/fao-eostat/un-handbook"
```

**After: GitLab CI (Nearly Identical)**

```yaml
# .gitlab-ci.yml
build_data_artifacts:
  image: registry.gitlab.com/dagger-io/dagger/dagger:latest
  script:
    - dagger run python ./ci/pipeline.py package-data --registry-prefix "registry.gitlab.com/my-org/handbook-data"
  variables:
    REGISTRY_USER: $CI_REGISTRY_USER
    REGISTRY_TOKEN: $CI_REGISTRY_PASSWORD
    GIT_COMMIT_TOKEN: $GITLAB_PUSH_TOKEN
    GIT_REPO_URL: "gitlab.com/my-org/un-handbook"
```

**Dagger SDK Implementation** (`ci/pipeline.py`):

The core logic moves into a Python script using the Dagger SDK. Dagger runs pipeline steps in isolated containers, providing automatic caching, parallelization, and portability.

```python
import dagger
import anyio
import sys
import os
import re

# --- CLI Argument Parsing ---
if len(sys.argv) < 2:
    print("Usage: python pipeline.py <command>")
    sys.exit(1)

COMMAND = sys.argv[1]

# --- Helper Functions ---

def get_registry_auth(client: dagger.Client):
    """Configures registry authentication from environment variables."""
    user = os.environ.get("REGISTRY_USER")
    token_secret = client.set_secret(
        "REGISTRY_TOKEN",
        os.environ.get("REGISTRY_TOKEN")
    )
    if not user or not token_secret:
        raise ValueError("REGISTRY_USER and REGISTRY_TOKEN must be set")
    return user, token_secret

def get_git_commit_token(client: dagger.Client):
    """Gets the Git token for committing back to the repo."""
    token = os.environ.get("GIT_COMMIT_TOKEN")
    if not token:
        raise ValueError("GIT_COMMIT_TOKEN must be set for auto-commit")
    return client.set_secret("GIT_COMMIT_TOKEN", token)

def get_git_repo_url():
    """Gets the Git repo URL from an env var."""
    url = os.environ.get("GIT_REPO_URL")
    if not url:
        raise ValueError("GIT_REPO_URL env var must be set (e.g., github.com/fao-eostat/un-handbook)")
    return url

def get_git_commit_base(client: dagger.Client, base_image: str = "alpine/git:latest"):
    """
    Creates a base container pre-configured with Git
    and credentials, ready to clone and commit.
    """
    git_token = get_git_commit_token(client)
    git_repo_url = get_git_repo_url()

    auth_url = f"https://oauth2:{git_token}@{git_repo_url}"

    container = (
        client.container()
        .from_(base_image)
        .with_secret_variable("GIT_TOKEN", git_token)
        # Configure Git
        .with_exec(["git", "config", "--global", "user.name", "github-actions[bot]"])
        .with_exec(["git", "config", "--global", "user.email", "github-actions[bot]@users.noreply.github.com"])
        # Clone repo using token
        .with_exec(["git", "clone", auth_url, "/repo"])
        .with_workdir("/repo")
    )
    return container

# --- Dagger Pipeline Functions ---

async def build_compute_image(client: dagger.Client, dockerfile: str, tag: str):
    """
    (Component #2) Builds and publishes a curated compute image.
    e.g., python pipeline.py build-image --dockerfile .docker/base.Dockerfile --tag ghcr.io/fao-eostat/handbook-base:v1.0
    """
    print(f"Building compute image for {dockerfile}...")
    user, token = get_registry_auth(client)

    # Get source context
    src = client.host().directory(".")

    # Build and publish
    image_ref = await (
        client.container()
        .build(context=src, dockerfile=dockerfile)
        .with_registry_auth(
            address=tag.split("/")[0],
            username=user,
            secret=token
        )
        .publish(address=tag)
    )
    print(f"Published compute image to: {image_ref}")

async def package_data_artifacts(client: dagger.Client, registry_prefix: str):
    """
    (Component #3) Builds, content-hashes, publishes, and auto-commits
    all changed chapter data artifacts.
    """
    print("Starting data packaging pipeline...")
    user, token = get_registry_auth(client)
    git_token = get_git_commit_token(client)

    # 1. Get repository source and find changed chapters
    src = client.host().directory(".")

    # Use a container with git to find changed data dirs
    # Note: Using HEAD~1 HEAD works for single commits.
    # For multi-commit pushes, consider: git diff --name-only origin/main...HEAD
    changed_chapters = await (
        client.container()
        .from_("alpine/git:latest")
        .with_mounted_directory("/src", src)
        .with_workdir("/src")
        .with_exec(["sh", "-c", "git diff --name-only HEAD~1 HEAD | grep '^data/' | cut -d/ -f2 | sort -u"])
        .stdout()
    )

    changed_chapters = changed_chapters.strip().split("\n")
    if not changed_chapters or (len(changed_chapters) == 1 and changed_chapters[0] == ''):
        print("No chapter data changes detected. Exiting.")
        return

    print(f"Detected changes in: {', '.join(changed_chapters)}")

    # 2. Build, Hash, and Push artifacts
    updated_files = {} # dict to store { "ct_chile.qmd": "sha256-abcdef..." }

    for chapter in changed_chapters:
        chapter_data_dir = f"data/{chapter}"
        print(f"Processing data for: {chapter}")

        # Build 'scratch' artifact
        artifact = (
            client.container()
            .from_("scratch")
            .with_directory(f"/data/{chapter}", src.directory(chapter_data_dir))
        )

        # Get Dagger's automatic content-based digest (the hash)
        digest = await artifact.digest() # e.g., "sha256:abc..."
        hash_suffix = f"sha256-{digest.split(':')[-1][:12]}" # "sha256-abcdef123"

        # Push the artifact
        image_tag = f"{registry_prefix}:{chapter}-{hash_suffix}"
        image_ref = await (
            artifact
            .with_registry_auth(
                address=registry_prefix,
                username=user,
                secret=token
            )
            .publish(address=image_tag)
        )
        print(f"Pushed data artifact: {image_ref}")

        # Store for commit
        updated_files[f"{chapter}.qmd"] = hash_suffix

    # 3. Auto-commit hashes back to repo
    # Get the base git container
    commit_container = get_git_commit_base(client)

    # Add python dependencies
    commit_container = (
        commit_container
        .with_exec(["apk", "add", "py3-pip", "python3"])
        .with_exec(["pip", "install", "pyyaml"])
    )

    # Python script to update YAML (more robust than 'yq' or 'sed')
    py_script = """
import yaml, sys, os
file_path = sys.argv[1]
new_hash = sys.argv[2]
if not os.path.exists(file_path):
    print(f"Warning: {file_path} not found, skipping.")
    sys.exit(0)
with open(file_path, 'r') as f:
    content = f.read()
parts = content.split('---')
if len(parts) < 3:
    print(f"No YAML frontmatter in {file_path}")
    sys.exit(1)
data = yaml.safe_load(parts[1])
if 'reproducible' not in data:
    data['reproducible'] = {}
data['reproducible']['data-snapshot'] = new_hash
parts[1] = yaml.dump(data)
with open(file_path, 'w') as f:
    f.write('---'.join(parts))
"""

    commit_container = commit_container.with_new_file("/src/update_yaml.py", py_script)

    # Run update for each changed file
    commit_message = "chore: update data snapshots [skip ci]\\n\\n"
    for file_name, hash_value in updated_files.items():
        commit_container = commit_container.with_exec([
            "python", "/src/update_yaml.py", file_name, hash_value
        ])
        commit_container = commit_container.with_exec(["git", "add", file_name])
        commit_message += f"- Updates {file_name} to {hash_value}\\n"

    # Commit and Push
    commit_container = commit_container.with_exec(["git", "commit", "-m", commit_message])
    commit_container = commit_container.with_exec(["git", "push"])

    # Run the final container
    await commit_container.sync()
    print("Successfully committed updated data snapshot hashes.")

async def generate_metadata(client: dagger.Client):
    """
    (Component #5) Scans all .qmd files and commits an updated chapters.json.
    """
    print("Starting metadata generation pipeline...")

    # 1. Get the base git container, using an R-based image
    commit_container = get_git_commit_base(client, base_image="r-base:4.5.1")

    # 2. Add R dependencies
    commit_container = (
        commit_container
        .with_exec(["apt-get", "update"])
        .with_exec(["apt-get", "install", "-y", "libgit2-dev"]) # for R 'git2r' if needed
        # Install R packages
        .with_exec(["Rscript", "-e", "install.packages(c('yaml', 'jsonlite', 'purrr'), repos='https://cloud.r-project.org')"])
    )

    # 3. Run the R script, commit, and push
    final_container = (
        commit_container
        # Run the R script from the repo and redirect output
        # Assumes scan-all-chapters.R is in a 'scripts' dir
        .with_exec(["Rscript", "scripts/scan-all-chapters.R"], redirect_stdout="chapters.json")
        # Commit the result
        .with_exec(["git", "add", "chapters.json"])
        .with_exec(["git", "commit", "-m", "chore: update chapter metadata [skip ci]"])
        .with_exec(["git", "push"])
    )

    # Run the final container
    await final_container.sync()
    print("Successfully generated and committed chapters.json.")

# --- Main Execution ---

async def run_pipeline():
    async with dagger.Connection() as client:
        if COMMAND == "build-image":
            dockerfile = sys.argv[2].split("=")[1]
            tag = sys.argv[3].split("=")[1]
            await build_compute_image(client, dockerfile, tag)

        elif COMMAND == "package-data":
            registry_prefix = sys.argv[2].split("=")[1]
            await package_data_artifacts(client, registry_prefix)

        elif COMMAND == "generate-metadata":
            await generate_metadata(client)

        else:
            print(f"Unknown command: {COMMAND}")
            sys.exit(1)

if __name__ == "__main__":
    anyio.run(run_pipeline)
```

**Key Benefits of this Dagger-based Design**:

1. **Extreme Portability**: The logic runs identically on GitHub-hosted runners, GitLab instances, or a developer's laptop. The only requirement is the Dagger engine.

2. **Local Testing**: Developers can run the exact production CI pipeline on their local machine by executing `dagger run python ./ci/pipeline.py package-data ...`. This is impossible with traditional CI.

3. **Automatic Caching**: Dagger automatically caches every step of the pipeline. If the `data/ct_chile` directory hasn't changed, `artifact.digest()` will be instant, and the build will be skipped.

4. **Simplified CI**: The CI YAML files are reduced to simple, declarative "runners," making them easy to read and manage. All complex logic is in a single, version-controlled, and testable Python script.

5. **Robust Hashing**: We no longer rely on `find | sha256sum` shell scripting. Dagger's `artifact.digest()` calculates a reproducible, content-addressed digest of the OCI artifact layer, which is a more robust and correct form of content-hashing.

6. **Zero-Friction Author Workflow**: Authors simply commit data files to the repository. The Dagger pipeline automatically handles all five steps: detecting changes, calculating content hash, building OCI artifacts, pushing to registry, and auto-committing hashes back to chapter frontmatter.

**Result**: True immutability. The chapter always references an exact, content-addressed data snapshot, and the entire build pipeline is portable across any CI platform.

---

### Detailed Implementation

#### Repository Structure

```
UN-Handbook/
├── _extensions/
│   └── reproducible-button/       # Quarto extension
│       ├── _extension.yml
│       └── reproduce-button.lua   # Deep-link generator
│
├── handbook-catalog/               # Onyxia Helm catalog
│   ├── chapter-session/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values.schema.json
│   │   └── templates/
│   │       ├── serviceaccount.yaml  # For IRSA
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml
│   ├── index.yaml                 # Helm repo index
│   └── chapter-session-1.0.0.tgz
│
├── ci/                            # NEW: Portable Dagger pipeline logic
│   ├── __init__.py
│   └── pipeline.py                # Dagger SDK script (Components #2, #3, #5)
│
├── .docker/
│   ├── base.Dockerfile            # R + renv + GDAL
│   ├── gpu.Dockerfile             # CUDA + torch
│   └── .dockerignore
│
├── .github/
│   └── workflows/
│       ├── build-images.yml       # SIMPLIFIED: One-line 'dagger run' wrapper
│       ├── package-data.yml       # SIMPLIFIED: One-line 'dagger run' wrapper
│       └── generate-metadata.yml  # SIMPLIFIED: One-line 'dagger run' wrapper
│
├── requirements.txt               # Python deps (Indonesia chapter)
│
├── data/
│   ├── ct_chile/                  # Chapter-specific data
│   └── ...
│
└── chapters/
    ├── ct_chile.qmd               # With reproducible: { data-snapshot: sha256-... }
    ├── cy_colombia.qmd
    └── ...
```

#### Container Images

##### Base Image (`ghcr.io/fao-eostat/handbook-base:v1.0`)

**Dockerfile** (`.docker/base.Dockerfile`):
```dockerfile
FROM jupyter/r-notebook:r-4.5.1

USER root

# Install system dependencies (fixed versions for reproducibility)
RUN apt-get update && apt-get install -y \
    libgdal-dev=3.6.2+dfsg-1~jammy \
    libproj-dev=9.1.1-1~jammy \
    libgeos-dev=3.11.1-1~jammy \
    libudunits2-dev \
    libnode-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

USER ${NB_UID}

# Copy renv files
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Install R packages from renv.lock
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"
RUN R -e "renv::restore()"

# Install Python dependencies (for Indonesia chapter)
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Pre-warm key packages (reduce first-run latency)
RUN R -e "library(sits); library(terra); library(sf)"

# Set working directory
WORKDIR /home/jovyan

# Labels
LABEL org.opencontainers.image.version="v1.0" \
      org.opencontainers.image.title="UN Handbook Base Image" \
      org.opencontainers.image.description="R 4.5.1 + geospatial stack"
```

**Python Requirements** (`requirements.txt`):
```
# For Indonesia chapter (reticulate integration)
numpy>=1.24.0
pandas>=2.0.0
geopandas>=0.13.0
rasterio>=1.3.0
```

##### GPU Image (`ghcr.io/fao-eostat/handbook-base-gpu:v1.0`)

**Dockerfile** (`.docker/gpu.Dockerfile`):
```dockerfile
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

USER root

# Install R 4.5.1
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:c2d4u.team/c2d4u4.0+ \
    && apt-get update && apt-get install -y \
    r-base=4.5.1* \
    r-base-dev=4.5.1* \
    python3 python3-pip \
    libgdal-dev libproj-dev libgeos-dev \
    # ... (same system deps as base)

# Create jovyan user
RUN useradd -m -s /bin/bash -N -u 1000 jovyan
USER jovyan

# Install R packages (same as base)
# ... (copy renv restore steps)

# Install torch with CUDA support
RUN R -e "install.packages('torch', repos='https://cloud.r-project.org')"
RUN R -e "torch::install_torch(type='cuda', version='2.1.0')"

# Verify GPU access
RUN R -e "stopifnot(torch::cuda_is_available())"

WORKDIR /home/jovyan

LABEL org.opencontainers.image.version="v1.0-gpu" \
      handbook.requires-gpu="true"
```

**Build and Push** (CI workflow):
```bash
docker build -f .docker/base.Dockerfile -t ghcr.io/fao-eostat/handbook-base:v1.0 .
docker build -f .docker/gpu.Dockerfile -t ghcr.io/fao-eostat/handbook-base-gpu:v1.0 .
docker push ghcr.io/fao-eostat/handbook-base:v1.0
docker push ghcr.io/fao-eostat/handbook-base-gpu:v1.0
```

#### Onyxia Helm Chart

**Chart Structure**:
```
handbook-catalog/
├── chapter-session/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   └── templates/
│       ├── serviceaccount.yaml  # ← NEW: For IRSA
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
```

**Chart.yaml**:
```yaml
apiVersion: v2
name: chapter-session
version: 1.0.0
description: UN Handbook reproducible analysis session
type: application
keywords:
  - jupyter
  - r
  - reproducibility
  - geospatial
home: https://fao-eostat.github.io/UN-Handbook/
sources:
  - https://github.com/FAO-EOSTAT/UN-Handbook
maintainers:
  - name: UN Handbook Team
    email: un-handbook@example.org
icon: https://jupyter.org/assets/homepage/main-logo.svg
```

**values.yaml**:
```yaml
# Semantic tier selection (passed from Quarto button)
tier: "medium"
imageFlavor: "base"

# Chapter information (passed via Onyxia deep-link)
chapter:
  name: "ct_chile"
  version: "v1.0.0"
  storageSize: "20Gi"

# Legacy/override: Direct resource specification (optional)
# If empty, resources are derived from tier in deployment template
resources:
  requests:
    cpu: ""
    memory: ""
  limits:
    cpu: ""
    memory: ""

# ServiceAccount for IRSA (Workload Identity)
serviceAccount:
  create: true
  annotations: {}
  # Populated by Onyxia region.customValues:
  # annotations:
  #   eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/handbook-reader

# AWS configuration
aws:
  region: "us-west-2"
  # No credentials - IRSA provides them automatically

# Service configuration
service:
  type: ClusterIP
  port: 8888
  targetPort: 8888

# Ingress (Onyxia auto-configures subdomain)
ingress:
  enabled: true
  className: "{{onyxia.k8s.ingressClassName}}"
  hostname: "chapter-{{onyxia.k8s.randomSubdomain}}.{{onyxia.k8s.domain}}"
  tls: true

# Security (chart-specific implementation of region defaults)
security:
  ipProtection:
    enabled: "{{onyxia.region.defaultIpProtection}}"
    ip: "{{onyxia.user.ip}}"
  networkPolicy:
    enabled: "{{onyxia.region.defaultNetworkPolicy}}"

# Ephemeral session (no home persistence)
persistence:
  enabled: false

# Onyxia context (injected at deploy time)
onyxia:
  s3:
    AWS_BUCKET_NAME: ""
    AWS_S3_ENDPOINT: ""
    # Fallback credentials (only if IRSA not available)
    AWS_ACCESS_KEY_ID: ""
    AWS_SECRET_ACCESS_KEY: ""
    AWS_SESSION_TOKEN: ""
```

**templates/serviceaccount.yaml** (NEW):
```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "chapter-session.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "chapter-session.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

**templates/deployment.yaml**:
```yaml
{{- /* Define resource tier mappings (SSOT for infrastructure) */}}
{{- $resourceTiers := dict
      "light"  (dict "cpu" "2000m"  "memory" "8Gi"   "storage" "10Gi")
      "medium" (dict "cpu" "6000m"  "memory" "24Gi"  "storage" "20Gi")
      "heavy"  (dict "cpu" "10000m" "memory" "48Gi"  "storage" "50Gi")
      "gpu"    (dict "cpu" "8000m"  "memory" "32Gi"  "storage" "50Gi")
    -}}
{{- $tier := .Values.tier | default "medium" -}}
{{- $tierConfig := index $resourceTiers $tier -}}

{{- /* Define image flavor mappings (SSOT for images) */}}
{{- $imageFlavors := dict
      "base" (dict "repo" "ghcr.io/fao-eostat/handbook-base"     "tag" "v1.0")
      "gpu"  (dict "repo" "ghcr.io/fao-eostat/handbook-base-gpu" "tag" "v1.0")
    -}}
{{- $imageFlavor := .Values.imageFlavor | default "base" -}}
{{- $imageConfig := index $imageFlavors $imageFlavor -}}

{{- /* Allow override via explicit resources */}}
{{- $cpu := .Values.resources.limits.cpu | default $tierConfig.cpu -}}
{{- $memory := .Values.resources.limits.memory | default $tierConfig.memory -}}
{{- $storage := .Values.chapter.storageSize | default $tierConfig.storage -}}

apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "chapter-session.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "chapter-session.selectorLabels" . | nindent 8 }}
        chapter: {{ .Values.chapter.name }}
        tier: {{ $tier }}
    spec:
      serviceAccountName: {{ include "chapter-session.serviceAccountName" . }}
      securityContext:
        runAsUser: 1000
        runAsGroup: 100
        fsGroup: 100
      containers:
      - name: jupyterlab
        image: "{{ $imageConfig.repo }}:{{ $imageConfig.tag }}"
        imagePullPolicy: IfNotPresent
        command:
          - jupyter
          - lab
          - --ip=0.0.0.0
          - --port=8888
          - --no-browser
          - --NotebookApp.token=''
          - --NotebookApp.password=''
        ports:
        - name: http
          containerPort: 8888
          protocol: TCP
        env:
        - name: CHAPTER_NAME
          value: {{ .Values.chapter.name }}
        - name: CHAPTER_VERSION
          value: {{ .Values.chapter.version }}
        - name: ONYXIA_USER
          value: {{ .Values.onyxia.user.idep | quote }}
        # AWS region (always needed)
        - name: AWS_DEFAULT_REGION
          value: {{ .Values.aws.region | default "us-west-2" | quote }}
        # S3 endpoint and bucket info
        {{- if .Values.onyxia.s3 }}
        - name: AWS_S3_ENDPOINT
          value: {{ .Values.onyxia.s3.AWS_S3_ENDPOINT | default "https://s3.amazonaws.com" | quote }}
        - name: AWS_BUCKET_NAME
          value: {{ .Values.onyxia.s3.AWS_BUCKET_NAME | quote }}
        {{- end }}
        # FALLBACK: xOnyxiaContext credentials (only if IRSA not available)
        # AWS SDK automatically prefers IRSA when ServiceAccount has annotation
        {{- if and .Values.onyxia.s3 .Values.onyxia.s3.AWS_ACCESS_KEY_ID }}
        - name: AWS_ACCESS_KEY_ID
          value: {{ .Values.onyxia.s3.AWS_ACCESS_KEY_ID | quote }}
        - name: AWS_SECRET_ACCESS_KEY
          value: {{ .Values.onyxia.s3.AWS_SECRET_ACCESS_KEY | quote }}
        - name: AWS_SESSION_TOKEN
          value: {{ .Values.onyxia.s3.AWS_SESSION_TOKEN | quote }}
        {{- end }}
        resources:
          requests:
            cpu: {{ $cpu }}
            memory: {{ $memory }}
          limits:
            cpu: {{ $cpu }}
            memory: {{ $memory }}
            {{- if eq $tier "gpu" }}
            nvidia.com/gpu: 1
            {{- end }}
        volumeMounts:
        - name: chapter-data
          mountPath: /home/jovyan/handbook-chapter
          readOnly: true
        - name: dshm
          mountPath: /dev/shm
        livenessProbe:
          httpGet:
            path: /api
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: chapter-data
        csi:
          driver: csi-image.k8s.io
          volumeAttributes:
            image: "ghcr.io/fao-eostat/handbook-data:{{ .Values.chapter.name }}-{{ .Values.chapter.version }}"
          readOnly: true
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 2Gi
      {{- if .Values.gpu.enabled }}
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      {{- end }}
```

**templates/service.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  type: {{ .Values.service.type }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: http
    protocol: TCP
    name: http
  selector:
    {{- include "chapter-session.selectorLabels" . | nindent 4 }}
```

**templates/ingress.yaml**:
```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
  annotations:
    {{- if .Values.security.ipProtection.enabled }}
    nginx.ingress.kubernetes.io/whitelist-source-range: {{ .Values.security.ipProtection.ip }}
    {{- end }}
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: {{ .Values.ingress.className }}
  tls:
  - hosts:
    - {{ .Values.ingress.hostname }}
    secretName: {{ include "chapter-session.fullname" . }}-tls
  rules:
  - host: {{ .Values.ingress.hostname }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ include "chapter-session.fullname" . }}
            port:
              number: {{ .Values.service.port }}
{{- end }}
```

**Packaging for Onyxia Catalog**:
```bash
# Package the chart
helm package handbook-catalog/chapter-session/

# Generate index
helm repo index handbook-catalog/ --url https://fao-eostat.github.io/handbook-catalog

# Host on GitHub Pages
git add handbook-catalog/index.yaml handbook-catalog/chapter-session-1.0.0.tgz
git commit -m "Add handbook chapter session chart"
git push
```

#### Supporting Script: Chapter Metadata Extraction

**R Script** (`scripts/scan-all-chapters.R`):

This script is executed by the Dagger `generate_metadata()` pipeline function (Component #5) to scan all chapter `.qmd` files and extract reproducible metadata.

```r
#!/usr/bin/env Rscript
library(yaml)
library(jsonlite)
library(purrr)

# Find all .qmd files
qmd_files <- list.files(
  path = ".",
  pattern = "\\.qmd$",
  recursive = TRUE,
  full.names = TRUE
)

# Function to extract reproducible metadata
extract_metadata <- function(file) {
  tryCatch({
    lines <- readLines(file, warn = FALSE)

    # Find YAML frontmatter
    yaml_start <- which(lines == "---")[1]
    yaml_end <- which(lines == "---")[2]

    if (is.na(yaml_start) || is.na(yaml_end)) {
      return(NULL)
    }

    yaml_text <- paste(lines[(yaml_start+1):(yaml_end-1)], collapse = "\n")
    metadata <- yaml.load(yaml_text)

    # Check if reproducible metadata exists
    if (is.null(metadata$reproducible) || !isTRUE(metadata$reproducible$enabled)) {
      return(NULL)
    }

    # Extract chapter name
    chapter_name <- tools::file_path_sans_ext(basename(file))

    # Build metadata object
    list(
      tier = metadata$reproducible$tier %||% "medium",
      image_flavor = metadata$reproducible$`image-flavor` %||% "base",
      version = metadata$reproducible$`data-snapshot` %||% "v1.0.0",
      oci_image = sprintf(
        "ghcr.io/fao-eostat/handbook-data:%s-%s",
        chapter_name,
        metadata$reproducible$`data-snapshot` %||% "v1.0.0"
      ),
      estimated_runtime = metadata$reproducible$`estimated-runtime` %||% "Unknown",
      storage_size = metadata$reproducible$`storage-size` %||% "20Gi"
    )
  }, error = function(e) {
    warning(sprintf("Error parsing %s: %s", file, e$message))
    return(NULL)
  })
}

# Scan all chapters
chapters <- qmd_files %>%
  set_names(tools::file_path_sans_ext(basename(.))) %>%
  map(extract_metadata) %>%
  compact()  # Remove NULLs

# Output as JSON
cat(toJSON(chapters, pretty = TRUE, auto_unbox = TRUE))
```

---

### Implementation Roadmap

#### Phase 1: Foundation
-  Build base/GPU Docker images with curated system dependencies
-  Configure EKS cluster for OIDC provider (IRSA)
-  Create IAM role with S3 read permissions
-  **Spike**: Validate CSI Image Driver installation and functionality

#### Phase 2: Portable CI/CD with Dagger
- Implement Dagger SDK pipeline in Python (`ci/pipeline.py`)
- Build `package_data_artifacts()` function with content-hash calculation (SHA256)
- Build `build_compute_image()` function for Docker image builds
- Build `generate_metadata()` function for chapter metadata scanning
- Create thin GitHub Actions wrappers (`.github/workflows/*.yml`)
- Configure auto-commit of hashes back to `.qmd` files within Dagger pipeline
- Test OCI artifact builds and pushes to GHCR via Dagger
- Validate pipeline portability (local execution, GitHub Actions, GitLab CI)
- Validate immutable, content-addressed artifacts
- Document pipeline development and local testing workflow

#### Phase 3: Helm Chart & Integration
- Develop Onyxia Helm chart with ServiceAccount for IRSA
- Implement CSI image volume mounting
- Configure `region.customValues` in Onyxia for IRSA role ARN
- Build Quarto extension for "Reproduce" button generation
- Test hybrid credential approach (IRSA primary, xOnyxiaContext fallback)

#### Phase 4: Long-Term Dependency Management
- Extend CI pipeline to detect `renv.lock` changes
- Build chapter-specific compute images automatically
- Implement versioning strategy for compute images
- Handle dependency conflicts across chapters

#### Phase 5: Production Launch
- Rollout to production environment
- Conduct load testing (concurrent users)
- Establish monitoring and alerting
- Document author workflow
- Train chapter authors


#### Performance Comparison

| Metric | Old Approach (PVC Cloning) | New Approach (CSI Image Driver) | Improvement |
|--------|----------------------------|----------------------------------|-------------|
| First user startup | 60s (create golden PVC) | 15-30s (node pulls image) | **2-4× faster** |
| Second user startup | 5-15s (clone PVC) | **5-15s** (node cache hit) | **Same performance** |
| State management | Golden PVCs + cleanup jobs | **Stateless** (K8s image cache) | **Zero management** |
| Storage overhead | 1 golden PVC per chapter | **None** (standard image cache) | **Infrastructure simplified** |
| Reproducibility | Version tags | **Content hashes** (SHA256) | **Immutable artifacts** |
| Author workflow | Manual script execution | **Fully automated CI** | **Zero friction** |


**Template Syntax Notes**:

- Omit `{{}}` in `values.schema.json` `overwriteDefaultWith` field: `"user.email"`
- Include `{{}}` in `values.yaml` default values: `"{{onyxia.user.email}}"`
- Concatenation: `"{{project.id}}-{{k8s.randomSubdomain}}.{{k8s.domain}}"`
- Arrays: `"overwriteDefaultWith": ["value1", "{{region.oauth2.clientId}}"]`
- Objects: `"overwriteDefaultWith": {"foo": "bar", "bar": "{{region.oauth2.clientId}}"}`
