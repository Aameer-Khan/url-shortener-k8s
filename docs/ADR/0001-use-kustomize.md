# ADR-0001: Why Kustomize?

## Context

The project contains multiple Kubernetes resources that will eventually require different configurations for development and production.

## Decision

Kustomize was selected because it is built into Kubernetes and allows environment-specific customization without duplicating YAML files.

## Consequences

- Cleaner repository
- Easier GitOps integration
- Better compatibility with Argo CD
