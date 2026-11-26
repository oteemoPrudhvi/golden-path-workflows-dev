variable "cluster_name" {
  description = "Cluster name, e.g. omf-dev-backstage."
  type        = string
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version for the control plane and nodes.

    Pinned rather than defaulted to 'latest' on purpose: EKS auto-upgrades are
    not something you want discovering themselves mid-demo.
  EOT
  type        = string
  default     = "1.35"
}

variable "subnet_ids" {
  description = "Private subnet ids for the nodes and control plane ENIs."
  type        = list(string)
}

variable "instance_types" {
  description = "Node instance types. Issue #5: t3.large for Backstage, t3.medium for Argo."
  type        = list(string)
}

variable "desired_size" {
  description = "Desired node count."
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum node count."
  type        = number
  default     = 1
}

variable "max_size" {
  description = <<-EOT
    Maximum node count. The Argo cluster sets this higher than desired so
    workflow bursts can scale out, per issue #5.
  EOT
  type        = number
  default     = 2
}

variable "disk_size_gb" {
  description = "Node root volume size."
  type        = number
  default     = 30
}

variable "enable_ebs_csi" {
  description = <<-EOT
    Install the EBS CSI driver add-on.

    Needed by anything claiming a PersistentVolume. Backstage itself does not
    (its state is in RDS and S3), but leaving it on costs nothing and avoids a
    confusing failure the first time something does.
  EOT
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public Kubernetes API endpoint.

    Defaults to open because a demo needs kubectl from laptops and CI without
    a bastion. NARROW THIS for anything longer-lived — it is the single widest
    permission in this module.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  description = <<-EOT
    How long CloudWatch keeps these logs.

    EKS writes the API, audit and authenticator logs here. A log group that is never created by Terraform is created
    implicitly with NO retention — it keeps logs forever and the cost grows
    quietly — and is not deleted on destroy. Owning it here fixes retention, tags
    and destroy together. Zero ("never expire") is deliberately not accepted.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch accepts, and not 0 (never expire)."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
