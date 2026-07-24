# Enterprise URL Shortener Platform

## Project Overview

This project uses a Python Flask URL Shortener application as a sample workload to demonstrate real-world DevOps practices. While the application provides basic URL shortening and redirection functionality, its primary purpose is to serve as a foundation for implementing modern DevOps workflows and platform engineering concepts throughout the software delivery lifecycle.

This repository is intentionally developed in incremental milestones, with each milestone documenting not only the implementation but also the engineering decisions, lessons learned, and future improvements.

---

## Why This Project?

The objective of this project is not to build a feature-rich URL Shortener application, but to demonstrate how a DevOps engineer takes an application from development to production. Throughout this journey, the project will showcase containerization with Docker, orchestration using Kubernetes, CI/CD with GitHub Actions, GitOps using Argo CD, Infrastructure as Code with Terraform, deployment on AWS, monitoring, security, and production best practices. Each milestone represents a practical implementation of a real-world DevOps capability while documenting the engineering decisions made along the way.

---

## Features

- URL Shortening
- URL Redirection
- PostgreSQL Database
- Dockerized Application
- Kubernetes Deployment
- Horizontal Pod Autoscaler (HPA)
- Ingress
- Network Policies
- GitHub Actions CI

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

```text
(Add tree output here)
```

---

## Architecture

(Add diagram later)

---

## Getting Started

### Clone Repository

```bash
git clone ...
```

### Build Docker Image

```bash
docker build -t url-shortener .
```

### Deploy to Kubernetes

```bash
kubectl apply -f kubernetes/
```

---

## Roadmap

- [x] Flask Application
- [x] Docker
- [x] Kubernetes
- [ ] GitOps with Argo CD
- [ ] Terraform
- [ ] AWS EKS
- [ ] Monitoring
- [ ] Security
- [ ] Disaster Recovery

---

## Engineering Journal

Engineering progress is documented under:

docs/progress/

---

## License

MIT
