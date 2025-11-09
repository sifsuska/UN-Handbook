### Using Cloud Credentials in Analysis Code

#### R Example: Accessing Sentinel-2 via STAC

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

#### Python Example: Accessing Landsat via Arrow

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

#### Complete Analysis Workflow

This example demonstrates how to combine both local packaged data (from CSI-mounted OCI artifacts) and live cloud data (via AWS credentials):

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

# Apply pre-trained model to current satellite data
classification <- sits_classify(
  data = cube,
  ml_model = model
)

# Compare to reference training samples
accuracy <- sits_accuracy(classification, training_samples)

# ============================================================
# Result: Reproducible analysis with version-controlled setup
# ============================================================
# - Model: Content-hashed in OCI artifact
# - Training data: Content-hashed in OCI artifact
# - Satellite imagery: STAC query in code (reproducible time range)
# - AWS access: Automatic via IRSA (no secrets in code)
```

#### Data Access Patterns

| Data Type | Source | Access Method | Reproducibility Guarantee |
|-----------|--------|---------------|---------------------------|
| Pre-trained models | CSI-mounted OCI artifact | Local filesystem | Content hash (SHA256) |
| Training samples | CSI-mounted OCI artifact | Local filesystem | Content hash (SHA256) |
| Reference data | CSI-mounted OCI artifact | Local filesystem | Content hash (SHA256) |
| Satellite imagery | AWS S3 (STAC catalog) | `sits`/`rstac` + AWS credentials | STAC query parameters in code |
| Cloud-optimized GeoTIFF | AWS S3 | `terra`/`rasterio` + AWS credentials | S3 URI in code |
| Parquet datasets | AWS S3 | `arrow`/`pyarrow` + AWS credentials | S3 URI in code |

#### Key Takeaways

1. **Zero-Configuration Cloud Access**: R and Python libraries automatically detect AWS credentials from environment variables set by IRSA or xOnyxiaContext

2. **Hybrid Data Strategy**: Combine fast local data (pre-computed models, training samples) with live cloud data (current satellite imagery)

3. **Reproducibility**: Both data sources are version-controlled through different mechanisms:
   - Local data: Content-addressed OCI artifacts with SHA256 hashes
   - Cloud data: STAC queries and S3 URIs embedded in analysis code

4. **Author-Friendly**: No credential management, no infrastructure knowledge required - just standard R/Python data access patterns
