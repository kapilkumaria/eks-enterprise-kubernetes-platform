# cert-manager

cert-manager automates TLS certificate issuance, renewal, rotation, and storage for Kubernetes workloads.

## Problem solved

Manually managing certificates creates operational risk:

- certificates can expire;
- private keys may be handled insecurely;
- renewals require human intervention;
- different environments can use inconsistent certificate processes.

cert-manager introduces Kubernetes-native certificate lifecycle management.

## Platform responsibilities

This component provides:

- cert-manager controller;
- cert-manager webhook;
- cert-manager CA injector;
- cert-manager CRDs;
- Gateway API integration;
- Prometheus metrics;
- automatic certificate renewal;
- Kubernetes TLS Secret management.

## Installation model

cert-manager is installed through Argo CD using:

- the official Jetstack OCI Helm chart;
- a pinned chart version;
- custom Helm values stored in this repository;
- automated reconciliation and self-healing.

## Gateway API integration

Gateway API support is enabled so certificates can be used by Traefik Gateway HTTPS listeners.

The intended traffic path is:

```text
Client
  ↓ HTTPS
AWS Load Balancer
  ↓
Traefik Gateway
  ↓
TLS Secret managed by cert-manager
  ↓
HTTPRoute
  ↓
Application Service
