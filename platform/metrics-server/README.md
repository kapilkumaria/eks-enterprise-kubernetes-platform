# Metrics Server

Metrics Server provides real-time CPU and memory metrics for Kubernetes nodes and pods.

## Platform purpose

It enables:

- `kubectl top nodes`
- `kubectl top pods`
- Horizontal Pod Autoscaler resource metrics
- Basic cluster resource troubleshooting

Metrics Server is not a long-term monitoring system. Prometheus will be used later for historical metrics, dashboards, alerting, and application-level observability.

## Installation

The component is installed using the official Metrics Server Helm chart and the configuration in:

```text
platform/metrics-server/values.yaml
