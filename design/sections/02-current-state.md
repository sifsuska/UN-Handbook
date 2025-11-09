#### Current State & Design Goals

##### Current State

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

##### Computational Characteristics

###### Analysis Types by Computational Load

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

::: {.callout-important}
###### GPU Support Availability
GPU-enabled sessions are subject to funding availability and cluster configuration. While the infrastructure design includes GPU support for deep learning workloads, actual GPU resource allocation on the UN Global Platform depends on budget and infrastructure capacity. GPU support is not part of the initial deployment.
:::

**GPU (Deep Learning)**:

- Example: Colombia chapter (crop yield estimation)
  - Sentinel-1 SAR data processing
  - Deep learning with `luz` (PyTorch for R)
  - Requires GPU for reasonable performance
  - 23 cache entries
- **Resource allocation**: 8 CPU, 32GB RAM, 1 GPU, 50GB storage (defined in Helm chart)
- **Typical runtime**: 2-4 hours

##### Current Technology Stack

###### R Environment
- **R Version**: 4.5.1
- **Package Manager**: `renv` with lock file (7,383 lines, ~427KB)
- **Key Packages**:
  - Geospatial: `sits`, `sf`, `terra`, `stars`, `lwgeom`
  - Cloud Access: `rstac`, `earthdatalogin`, `arrow`, `gdalcubes`
  - Machine Learning: `randomForest`, `ranger`, `e1071`, `kohonen`
  - Deep Learning: `torch`, `luz`
  - Visualization: `ggplot2`, `tmap`, `leaflet`
  - Python Integration: `reticulate` (for Indonesia chapter)

###### Python Environment
- **Status**: One chapter (Indonesia) uses Python via `reticulate`
- **Solution**: Create `requirements.txt` for reproducibility

###### Data Sources

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

##### Current Reproducibility Status

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

##### Design Requirements & Principles

###### Key Decisions

1. **Resource Allocation**: Dynamic (auto-scale per chapter based on metadata)
2. **Data Strategy**: Pre-packaged, content-hashed, and immutable OCI artifacts for local data; automatic OIDC-based credentials for live cloud data.
3. **User Interface**: JupyterLab (supports R/Python)
4. **Session Duration**: Ephemeral (e.g., 2-hour auto-cleanup)
5. **Platform Integration**: Orchestrated by Onyxia, but with a portable core
6. **Cloud Access**: Automatic, temporary AWS credentials via standard Kubernetes Workload Identity (IRSA)

###### Design Principles

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

