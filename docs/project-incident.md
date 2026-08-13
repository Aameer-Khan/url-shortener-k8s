Incident: AWS Load Balancer Controller CrashLoopBackOff

Environment:
AWS EKS
Kubernetes 1.33
us-east-1

Symptom:
Both AWS Load Balancer Controller replicas entered
CrashLoopBackOff.

Investigation:
Checked pod status and controller logs.

Root cause:
Controller attempted to discover the VPC ID through
EC2 instance metadata. Metadata access timed out.

Resolution:
Configured the AWS region and VPC ID explicitly through
the Helm release.

Validation:
Controller deployment returned to 2/2 Ready.
Both pods were Running with 0 restarts.

Result:
ALB/Ingress management functionality restored.
