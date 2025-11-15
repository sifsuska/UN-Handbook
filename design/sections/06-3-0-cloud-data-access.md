##### Cloud Data Access Strategy

###### Overview: The Dual-Data Architecture

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
