# Enterprise URL Shortener Platform

## Project Overview

This project uses a Python Flask URL Shortener application as a sample workload to demonstrate real-world DevOps practices. While the application provides basic URL shortening and redirection functionality, its primary purpose is to serve as a foundation for implementing modern DevOps workflows and platform engineering concepts throughout the software delivery lifecycle.

This repository is intentionally developed in incremental milestones, with each milestone documenting not only the implementation but also the engineering decisions, lessons learned, and future improvements.

---

## Why This Project?

The objective of this project is not to build a feature-rich URL Shortener application, but to demonstrate how a DevOps engineer takes an application from development to production. Throughout this journey, the project will showcase containerization with Docker, orchestration using Kubernetes, CI/CD with GitHub Actions, GitOps using Argo CD, Infrastructure as Code with Terraform, deployment on AWS, monitoring, security, and production best practices. Each milestone represents a practical implementation of a real-world DevOps capability while documenting the engineering decisions made along the way.

---

## Architecture

See [docs/architecture.md](docs/architecture.md)

---
## Features

- URL shortening service
- PostgreSQL persistence
- Kubernetes deployment
- ConfigMaps and Secrets
- Health probes
- Resource requests and limits
- Horizontal Pod Autoscaler
- Network Policies
- Kustomize base configuration
- GitOps-ready structure

---

## Tech Stack

| Category | Technology |
|----------|------------|
| Language | Python |
| Framework | Flask |
| Database | PostgreSQL |
| Container | Docker |
| Orchestration | Kubernetes |
| CI/CD | GitHub Actions |
| Version Control | Git |

---

## Project Structure

app/

kubernetes/

argocd/

docs/

scripts/

---

## Skills Demonstrated

- Docker
- Kubernetes
- GitHub Actions
- Kustomize
- Argo CD
- PostgreSQL
- Python
- GitOps

---

## Roadmap

- [x] Flask Application
- [x] Docker
- [x] Kubernetes
- [x] Kustomize
- [ ] GitOps with Argo CD
- [ ] Terraform
- [ ] AWS EKS
- [ ] Monitoring
- [ ] Security
- [ ] Disaster Recovery

---

## Project Journey

- ✅ Dockerized the application
- ✅ Deployed on Kubernetes
- ✅ Added health probes
- ✅ Configured HPA
- ✅ Implemented Network Policies
- ✅ Organized manifests using Kustomize
- ✅ Prepared GitOps with Argo CD
- 🚧 GitHub Actions (In Progress)

---
## Engineering Journal

Engineering progress is documented under:

docs/progress/

---

## License

MIT
