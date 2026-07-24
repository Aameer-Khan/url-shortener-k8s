# Progress 001 - Project Foundation

## Date

24 July 2026

---

# Objective

Restructure the existing URL Shortener repository into a clean and scalable project layout that is easier to maintain and extend as new technologies are added.

---

# Why This Change?

The application was already working, but all the files were stored in the project root, making the repository difficult to navigate as it grows.

A well-organized repository improves maintainability, collaboration, and readability. It also reflects how production projects are typically structured.

---

# Work Completed

- Created the `app/` directory for application source code.
- Moved Flask application files into the `app/` directory.
- Created the `kubernetes/` directory for deployment manifests.
- Moved Kubernetes YAML files into a dedicated folder.
- Created the `docs/` directory.
- Created the `docs/progress/` directory for engineering journals.
- Created the `scripts/` directory for future automation scripts.

---

# Repository Structure
url-shortener-k8s/
├── app/
├── kubernetes/
├── docs/
├── scripts/
├── tests/
├── Dockerfile
└── README.md


---

# What I Learned

Today I realized that writing code is only one part of software engineering.

A good project should also be easy to understand, navigate, and maintain.

I also learned that repository organization becomes increasingly important as new technologies such as Terraform, Argo CD, monitoring, and security are introduced.

---

# Challenges

The application itself did not need any changes.

The challenge was deciding how to organize the repository so it could continue growing without becoming cluttered.

---

# Engineering Decision

Instead of creating a new repository, I decided to improve the existing project.

This preserves the complete engineering journey and shows how the project evolved over time.

---

# Future Improvements

- Add Terraform infrastructure.
- Introduce GitOps using Argo CD.
- Implement monitoring with Prometheus and Grafana.
- Add security scanning.
- Improve repository documentation.
- Deploy to AWS EKS.

---

# Engineering Reflection

This milestone did not introduce any new functionality.

Instead, it improved the project's foundation.

Although the changes are small, they make future development easier and prepare the repository for enterprise-level features.



## One Thing I Would Do Better

Although the repository structure is now cleaner and more organized, I believe the project documentation still needs improvement.

In the next milestone, I want to create a professional README that clearly explains the project, architecture, prerequisites, setup instructions, folder structure, and future roadmap.

Good documentation is just as important as good code because it helps other engineers understand and contribute to the project more effectively.
