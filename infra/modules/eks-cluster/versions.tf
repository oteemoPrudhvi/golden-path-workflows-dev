terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Used by data.tls_certificate.oidc to read the cluster's OIDC issuer
    # thumbprint for the IRSA provider. Declared explicitly — an undeclared
    # provider resolves to whatever version happens to be available, which is
    # exactly the kind of drift pinning is meant to prevent.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
