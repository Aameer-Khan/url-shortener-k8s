                   User
                     │
                     ▼
              Kubernetes Ingress
                     │
                     ▼
        url-shortener-service (ClusterIP)
                     │
                     ▼
     +-------------------------------+
     |   URL Shortener Pods (x3)     |
     |  Flask Application            |
     +-------------------------------+
                     │
                     ▼
          postgres-service (ClusterIP)
                     │
                     ▼
             PostgreSQL Database

────────────────────────────────────────

Developer
     │
     ▼
 GitHub Repository
     │
     ▼
 GitHub Actions (CI)
     │
     ▼
 Docker Image
     │
     ▼
 Argo CD
     │
     ▼
 Kubernetes Cluster	
