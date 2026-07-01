aws_region   = "us-east-1"
project_name = "eks-enterprise-platform"
environment  = "dev"

vpc_cidr = "10.30.0.0/16"

cluster_version = "1.34"

node_instance_types = ["t3.medium"]

desired_size = 2
min_size     = 1
max_size     = 3
